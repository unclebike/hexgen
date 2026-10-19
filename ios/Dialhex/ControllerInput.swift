// ControllerInput.swift — Game controller, hardware keyboard, and phone input
//
// Uses the GameController framework for both gamepads (extendedGamepad
// profile) and hardware keyboards (GCKeyboard), so no UIKit key commands.
// GameController calls its handlers on `handlerQueue` (main by default), so
// handlers enter the main actor with `onMainActor` (`MainActor.assumeIsolated`).
//
// Every action carries the device it came from, so several players can play
// at once; each device auto-repeats its own held direction. Phones used as
// controllers feed in through `phone(_:…)` and repeat the same way.

import GameController
import DialhexCore
import UIKit

enum ControlAction: Equatable {
    case move(Direction)               // d-pad, left thumbstick (with auto-repeat while held), arrows/WASD, remote swipes and edge clicks
    case place(Vertex)                 // a phone's mini bin: put the dial straight there
    case rotate(RotationDirection)     // shoulders/triggers (left = counterClockwise, right = clockwise), X = ccw, Y = cw, keyboard Q/Z = ccw, E/X = cw, remote Play/Pause = ccw
    case confirm                       // A / Return / remote click  (menu: start; in-game the app treats it as rotate clockwise)
    case cancel                        // B / Options(View) button / Escape / remote Back (menu-level back, in-game: quit to menu from pause/game over)
    case pause                         // Menu(Start) button / Space
    case quickStart(Mode)              // keyboard 1/2/3 = main/endless/sprint
    case cycleSkin                     // keyboard K (menu: next unlocked skin)
}

/// The device an action came from.
enum InputSource: Hashable {
    case controller(ObjectIdentifier)  // a gamepad or a remote
    case keyboard
    case remote                        // the remote as UIKit presses (see `press(_:pressed:)`)
    case phone(String)                 // a phone controller, by its peer id
    case online                        // the other player in online co-op, on their own device
}

/// The kind of input the player is using, so hints and tips name the right buttons.
enum InputKind: String {
    case touch, keyboard, gamepad, remote, phone

    /// What a fresh launch assumes the player holds: the screen on iPhone, the remote on Apple TV.
    #if os(tvOS)
    static let initial = InputKind.remote
    #else
    static let initial = InputKind.touch
    #endif
}

/// Runs `body` on the main actor from a callback already on the main queue (traps otherwise).
private func onMainActor(_ body: @MainActor () -> Void) {
    MainActor.assumeIsolated(body)
}

@MainActor
final class ControllerInput {
    /// Called on the main actor for every action, with the device it came from.
    var onAction: ((ControlAction, InputSource) -> Void)?
    /// Called when a hardware keyboard connects or disconnects.
    var onKeyboardChange: ((Bool) -> Void)?
    /// Called when the current game controller changes (nil = none connected). Keyboards don't count.
    var onControllerChange: ((GCController?) -> Void)?
    /// Called when a device goes away: a controller or keyboard disconnects, or a phone drops.
    var onSourceLost: ((InputSource) -> Void)?
    /// Single player: the current controller is player 1. Multiplayer turns this off
    /// and numbers the controllers itself.
    var tracksCurrentController = true {
        didSet { if tracksCurrentController { refresh() } }
    }
    private(set) var controller: GCController?

    private var observers: [NSObjectProtocol] = []
    private var lightColor: GCColor?
    /// Per-controller light colours (a player's colour) that win over `lightColor`.
    private var playerLights: [ObjectIdentifier: GCColor] = [:]
    /// Each device's auto-repeating direction, and the input (button, stick, key) driving it.
    private var holds: [InputSource: Hold] = [:]
    /// Last 4-way direction of each thumbstick, for hysteresis.
    private var stickDirections: [ObjectIdentifier: Direction] = [:]
    private var keyboardConnected = false

    private struct Hold {
        let input: AnyHashable
        let direction: Direction
        let task: Task<Void, Never>
    }

    private static let repeatDelay: Duration = .milliseconds(300)
    private static let repeatInterval: Duration = .milliseconds(120)
    private static let stickPress: Float = 0.5
    private static let stickRelease: Float = 0.35

    init() {}

    /// Begin observing connections; wires up already-connected controllers/keyboards too.
    func start() {
        guard observers.isEmpty else { return }
        GCController.shouldMonitorBackgroundEvents = false
        let center = NotificationCenter.default
        let refreshing: [Notification.Name] = [
            .GCControllerDidConnect, .GCControllerDidBecomeCurrent, .GCControllerDidStopBeingCurrent,
            .GCKeyboardDidConnect,
        ]
        for name in refreshing {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                onMainActor { self?.refresh() }
            })
        }
        // A lost device can swallow a button release, so losing one also stops its auto-repeat
        observers.append(center.addObserver(forName: .GCControllerDidDisconnect, object: nil, queue: .main) { [weak self] note in
            let id = (note.object as? GCController).map(ObjectIdentifier.init)
            onMainActor {
                if let id { self?.lose(.controller(id)) }
                self?.refresh()
            }
        })
        observers.append(center.addObserver(forName: .GCKeyboardDidDisconnect, object: nil, queue: .main) { [weak self] _ in
            onMainActor {
                self?.lose(.keyboard)
                self?.refresh()
            }
        })
        // So can losing app focus, for every device at once
        observers.append(center.addObserver(forName: UIApplication.willResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            onMainActor { self?.resetHolds() }
        })
        refresh()
    }

    /// Tint every controller's light bar (DualShock/DualSense), 0xRRGGBB.
    func setLightColor(_ rgb: UInt32) {
        let color = Self.color(rgb)
        lightColor = color
        for controller in GCController.controllers() {
            controller.light?.color = playerLights[ObjectIdentifier(controller)] ?? color
        }
    }

    /// Tint one controller's light bar in its player's colour; nil hands it back to `setLightColor`.
    func setLightColor(_ rgb: UInt32?, for source: InputSource) {
        guard case .controller(let id) = source else { return }
        playerLights[id] = rgb.map(Self.color)
        if let controller = controller(for: source), let color = playerLights[id] ?? lightColor {
            controller.light?.color = color
        }
    }

    /// Number a controller's player LEDs (multiplayer); nil clears them.
    func setPlayerIndex(_ index: Int?, for source: InputSource) {
        guard let controller = controller(for: source) else { return }
        let indices: [GCControllerPlayerIndex] = [.index1, .index2, .index3, .index4]
        controller.playerIndex = index.flatMap { indices.indices.contains($0) ? indices[$0] : nil } ?? .indexUnset
    }

    /// The connected controller behind a source, if it is one.
    func controller(for source: InputSource) -> GCController? {
        guard case .controller(let id) = source else { return nil }
        return GCController.controllers().first { ObjectIdentifier($0) == id }
    }

    private static func color(_ rgb: UInt32) -> GCColor {
        GCColor(red: Float((rgb >> 16) & 0xFF) / 255,
                green: Float((rgb >> 8) & 0xFF) / 255,
                blue: Float(rgb & 0xFF) / 255)
    }

    // MARK: - Phones

    /// A phone's direction went down or came up; repeats like a held d-pad.
    func phone(_ peer: String, direction: Direction, pressed: Bool) {
        setHeld(direction, pressed, from: peer, source: .phone(peer))
    }

    /// A phone pressed a button.
    func phone(_ peer: String, _ action: ControlAction) {
        emit(action, from: .phone(peer))
    }

    /// A phone disconnected or timed out.
    func phoneLost(_ peer: String) {
        lose(.phone(peer))
    }

    // MARK: - UIKit presses

    /// The remote as UIKit presses, for when GameController doesn't present it as a
    /// controller (the tvOS Simulator does this): arrows move and repeat while held,
    /// select confirms, Play/Pause turns back, Menu cancels. Returns whether it was used.
    func press(_ type: UIPress.PressType, pressed: Bool) -> Bool {
        let direction: Direction?
        switch type {
        case .upArrow: direction = .up
        case .downArrow: direction = .down
        case .leftArrow: direction = .left
        case .rightArrow: direction = .right
        default: direction = nil
        }
        if let direction {
            setHeld(direction, pressed, from: type.rawValue, source: .remote)
            return true
        }
        let action: ControlAction
        switch type {
        case .select: action = .confirm
        case .playPause: action = .rotate(.counterClockwise)
        case .menu: action = .cancel
        default: return false
        }
        if pressed { emit(action, from: .remote) }
        return true
    }

    /// What kind of input a source is: a controller with only the micro profile is a remote.
    func kind(of source: InputSource) -> InputKind {
        switch source {
        case .controller:
            let controller = controller(for: source)
            return controller?.extendedGamepad == nil && controller?.microGamepad != nil ? .remote : .gamepad
        case .keyboard: return .keyboard
        case .remote: return .remote
        case .phone: return .phone
        case .online: return InputKind.initial // never pressed here: its input arrives over the network
        }
    }

    // MARK: - Connections

    /// Rebinds every connected gamepad, remote, and the keyboard (setting a handler is
    /// idempotent), then tracks the current controller. Remotes play but never count as
    /// "the controller": an Apple TV always has one, and it has no light or rumble.
    private func refresh() {
        let gamepads = GCController.controllers().filter { $0.extendedGamepad != nil }
        for gamepad in gamepads { bind(gamepad) }
        for remote in GCController.controllers() where remote.extendedGamepad == nil { bindRemote(remote) }
        bindKeyboard()
        let keyboard = GCKeyboard.coalesced != nil
        if keyboard != keyboardConnected {
            keyboardConnected = keyboard
            onKeyboardChange?(keyboard)
        }

        let current = gamepads.first { $0 === GCController.current } ?? gamepads.first
        if tracksCurrentController {
            for gamepad in gamepads where gamepad !== current && gamepad.playerIndex == .index1 {
                gamepad.playerIndex = .indexUnset
            }
            current?.playerIndex = .index1
        }
        if current !== controller {
            controller = current
            onControllerChange?(current)
        }
    }

    private func bind(_ controller: GCController) {
        guard let pad = controller.extendedGamepad else { return }
        let source = InputSource.controller(ObjectIdentifier(controller))
        if let light = playerLights[ObjectIdentifier(controller)] ?? lightColor { controller.light?.color = light }

        onHold(pad.dpad.up, .up, source)
        onHold(pad.dpad.down, .down, source)
        onHold(pad.dpad.left, .left, source)
        onHold(pad.dpad.right, .right, source)
        pad.leftThumbstick.valueChangedHandler = { [weak self] stick, x, y in
            onMainActor { self?.stickMoved(stick, x: x, y: y, source: source) }
        }

        onPress(pad.buttonA, .confirm, source)
        onPress(pad.buttonB, .cancel, source)
        onPress(pad.buttonX, .rotate(.counterClockwise), source)
        onPress(pad.buttonY, .rotate(.clockwise), source)
        onPress(pad.leftShoulder, .rotate(.counterClockwise), source)
        onPress(pad.leftTrigger, .rotate(.counterClockwise), source)
        onPress(pad.rightShoulder, .rotate(.clockwise), source)
        onPress(pad.rightTrigger, .rotate(.clockwise), source)
        onPress(pad.buttonMenu, .pause, source)
        onPress(pad.buttonOptions, .cancel, source)
    }

    /// The Siri Remote and the iPhone's Control Center remote (micro gamepad profile):
    /// swipe the touch surface to move (holding the swipe repeats, like a stick), click
    /// to confirm, Play/Pause turns back, Back cancels. The second-generation remote's
    /// clickpad also moves on an edge click, so there only a centre click confirms.
    private func bindRemote(_ controller: GCController) {
        guard let pad = controller.microGamepad else { return }
        let source = InputSource.controller(ObjectIdentifier(controller))
        pad.dpad.valueChangedHandler = { [weak self] dpad, x, y in
            onMainActor { self?.stickMoved(dpad, x: x, y: y, source: source) }
        }
        let profile = controller.physicalInputProfile
        if let ring = profile.dpads[GCInputDirectionalCardinalDpad],
           let center = profile.buttons[GCInputDirectionalCenterButton] {
            onHold(ring.up, .up, source)
            onHold(ring.down, .down, source)
            onHold(ring.left, .left, source)
            onHold(ring.right, .right, source)
            onPress(center, .confirm, source)
        } else {
            onPress(pad.buttonA, .confirm, source)
        }
        onPress(pad.buttonX, .rotate(.counterClockwise), source)
        onPress(pad.buttonMenu, .cancel, source)
    }

    /// Fires `action` on each press (not on release).
    private func onPress(_ button: GCControllerButtonInput?, _ action: ControlAction, _ source: InputSource) {
        button?.pressedChangedHandler = { [weak self] _, _, pressed in
            guard pressed else { return }
            onMainActor { self?.emit(action, from: source) }
        }
    }

    /// Moves on press and auto-repeats until released.
    private func onHold(_ button: GCControllerButtonInput, _ direction: Direction, _ source: InputSource) {
        button.pressedChangedHandler = { [weak self] button, _, pressed in
            onMainActor { self?.setHeld(direction, pressed, from: ObjectIdentifier(button), source: source) }
        }
    }

    private func bindKeyboard() {
        GCKeyboard.coalesced?.keyboardInput?.keyChangedHandler = { [weak self] input, button, key, pressed in
            onMainActor { self?.keyChanged(key, pressed: pressed, button: button, input: input) }
        }
    }

    // MARK: - Keyboard

    private func keyChanged(_ key: GCKeyCode, pressed: Bool, button: GCControllerButtonInput, input: GCKeyboardInput) {
        // Leave ⌘-shortcuts to the system (releases still go through so repeats stop).
        let command = input.button(forKeyCode: .leftGUI)?.isPressed == true
            || input.button(forKeyCode: .rightGUI)?.isPressed == true
        if pressed && command { return }

        let direction: Direction?
        switch key {
        case .keyW, .upArrow: direction = .up
        case .keyS, .downArrow: direction = .down
        case .keyA, .leftArrow: direction = .left
        case .keyD, .rightArrow: direction = .right
        default: direction = nil
        }
        if let direction {
            setHeld(direction, pressed, from: ObjectIdentifier(button), source: .keyboard)
            return
        }
        guard pressed else { return }

        let action: ControlAction?
        switch key {
        case .keyQ, .keyZ: action = .rotate(.counterClockwise)
        case .keyE, .keyX: action = .rotate(.clockwise)
        case .returnOrEnter, .keypadEnter: action = .confirm
        case .escape: action = .cancel
        case .spacebar: action = .pause
        case .one, .keypad1: action = .quickStart(.main)
        case .two, .keypad2: action = .quickStart(.endless)
        case .three, .keypad3: action = .quickStart(.sprint)
        case .keyK: action = .cycleSkin
        default: action = nil
        }
        if let action { emit(action, from: .keyboard) }
    }

    // MARK: - Movement and auto-repeat

    /// Treats the stick as a 4-way pad: a direction engages past `stickPress` and
    /// holds until it drops under `stickRelease` or another axis clearly wins.
    private func stickMoved(_ stick: GCControllerDirectionPad, x: Float, y: Float, source: InputSource) {
        let id = ObjectIdentifier(stick)
        let old = stickDirections[id]
        let new = Self.stickDirection(x: x, y: y, current: old)
        guard new != old else { return }
        stickDirections[id] = new
        if old != nil { release(from: id, source: source) }
        if let new { hold(new, from: id, source: source) }
    }

    private static func stickDirection(x: Float, y: Float, current: Direction?) -> Direction? {
        func along(_ direction: Direction) -> Float {
            switch direction {
            case .right: return x
            case .left: return -x
            case .up: return y
            case .down: return -y
            }
        }
        let dominant: Direction = abs(x) >= abs(y) ? (x >= 0 ? .right : .left) : (y >= 0 ? .up : .down)
        if let current, along(current) > stickRelease, along(current) * 1.25 >= along(dominant) {
            return current
        }
        return along(dominant) > stickPress ? dominant : nil
    }

    private func setHeld(_ direction: Direction, _ pressed: Bool, from input: AnyHashable, source: InputSource) {
        if pressed { hold(direction, from: input, source: source) } else { release(from: input, source: source) }
    }

    /// Moves once now, then repeats after `repeatDelay` every `repeatInterval`,
    /// until this device lets go or holds another direction.
    private func hold(_ direction: Direction, from input: AnyHashable, source: InputSource) {
        holds[source]?.task.cancel()
        emit(.move(direction), from: source)
        let task = Task { @MainActor [weak self] in
            try? await Task.sleep(for: Self.repeatDelay)
            while !Task.isCancelled, let controls = self {
                controls.emit(.move(direction), from: source)
                try? await Task.sleep(for: Self.repeatInterval)
            }
        }
        holds[source] = Hold(input: input, direction: direction, task: task)
    }

    /// Stops this device repeating if `input` is the one driving it.
    private func release(from input: AnyHashable, source: InputSource) {
        guard let hold = holds[source], hold.input == input else { return }
        hold.task.cancel()
        holds[source] = nil
    }

    private func resetHolds() {
        for hold in holds.values { hold.task.cancel() }
        holds.removeAll()
        stickDirections.removeAll()
    }

    /// A device went away: stop its repeat and tell the app.
    private func lose(_ source: InputSource) {
        holds[source]?.task.cancel()
        holds[source] = nil
        if case .controller(let id) = source { playerLights[id] = nil }
        onSourceLost?(source)
    }

    private func emit(_ action: ControlAction, from source: InputSource) {
        onAction?(action, source)
    }
}
