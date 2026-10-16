// ControllerInput.swift — Game controller and hardware keyboard input
//
// Uses the GameController framework for both gamepads (extendedGamepad
// profile) and hardware keyboards (GCKeyboard), so no UIKit key commands.
// GameController calls its handlers on `handlerQueue` (main by default), so
// handlers enter the main actor with `onMainActor` (`MainActor.assumeIsolated`).

import GameController
import DialhexCore
import UIKit

enum ControlAction: Equatable {
    case move(Direction)               // d-pad, left thumbstick (with auto-repeat while held), arrows/WASD
    case rotate(RotationDirection)     // shoulders/triggers (left = counterClockwise, right = clockwise), X = ccw, Y = cw, keyboard Q/Z = ccw, E/X = cw
    case confirm                       // A / Return  (menu: start; in-game the app treats it as rotate clockwise)
    case cancel                        // B / Options(View) button / Escape (menu-level back, in-game: quit to menu from pause/game over)
    case pause                         // Menu(Start) button / Space
    case quickStart(Mode)              // keyboard 1/2/3 = main/endless/sprint
}

/// Runs `body` on the main actor from a callback already on the main queue (traps otherwise).
private func onMainActor(_ body: @MainActor () -> Void) {
    MainActor.assumeIsolated(body)
}

@MainActor
final class ControllerInput {
    /// Called on the main actor for every action.
    var onAction: ((ControlAction) -> Void)?
    /// Called when the current game controller changes (nil = none connected). Keyboards don't count.
    var onControllerChange: ((GCController?) -> Void)?
    private(set) var controller: GCController?

    private var observers: [NSObjectProtocol] = []
    private var lightColor: GCColor?
    /// The input (button, stick or key) whose direction is auto-repeating.
    private var held: (source: ObjectIdentifier, direction: Direction)?
    private var repeatTask: Task<Void, Never>?
    /// Last 4-way direction of each thumbstick, for hysteresis.
    private var stickDirections: [ObjectIdentifier: Direction] = [:]

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
        // A lost device or app focus can swallow a button release, so these also stop auto-repeat.
        let resetting: [Notification.Name] = [
            .GCControllerDidDisconnect, .GCKeyboardDidDisconnect, UIApplication.willResignActiveNotification,
        ]
        for name in refreshing + resetting {
            let resets = resetting.contains(name)
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                onMainActor {
                    if resets { self?.resetHolds() }
                    self?.refresh()
                }
            })
        }
        refresh()
    }

    /// Tint a controller light bar (DualShock/DualSense), 0xRRGGBB.
    func setLightColor(_ rgb: UInt32) {
        let color = GCColor(red: Float((rgb >> 16) & 0xFF) / 255,
                            green: Float((rgb >> 8) & 0xFF) / 255,
                            blue: Float(rgb & 0xFF) / 255)
        lightColor = color
        for controller in GCController.controllers() { controller.light?.color = color }
    }

    // MARK: - Connections

    /// Rebinds every connected gamepad and the keyboard (setting a handler is idempotent),
    /// then tracks the current controller.
    private func refresh() {
        let gamepads = GCController.controllers().filter { $0.extendedGamepad != nil }
        for gamepad in gamepads { bind(gamepad) }
        bindKeyboard()

        let current = gamepads.first { $0 === GCController.current } ?? gamepads.first
        for gamepad in gamepads where gamepad !== current && gamepad.playerIndex == .index1 {
            gamepad.playerIndex = .indexUnset
        }
        current?.playerIndex = .index1
        if current !== controller {
            controller = current
            onControllerChange?(current)
        }
    }

    private func bind(_ controller: GCController) {
        guard let pad = controller.extendedGamepad else { return }
        if let lightColor { controller.light?.color = lightColor }

        onHold(pad.dpad.up, .up)
        onHold(pad.dpad.down, .down)
        onHold(pad.dpad.left, .left)
        onHold(pad.dpad.right, .right)
        pad.leftThumbstick.valueChangedHandler = { [weak self] stick, x, y in
            onMainActor { self?.stickMoved(stick, x: x, y: y) }
        }

        onPress(pad.buttonA, .confirm)
        onPress(pad.buttonB, .cancel)
        onPress(pad.buttonX, .rotate(.counterClockwise))
        onPress(pad.buttonY, .rotate(.clockwise))
        onPress(pad.leftShoulder, .rotate(.counterClockwise))
        onPress(pad.leftTrigger, .rotate(.counterClockwise))
        onPress(pad.rightShoulder, .rotate(.clockwise))
        onPress(pad.rightTrigger, .rotate(.clockwise))
        onPress(pad.buttonMenu, .pause)
        onPress(pad.buttonOptions, .cancel)
    }

    /// Fires `action` on each press (not on release).
    private func onPress(_ button: GCControllerButtonInput?, _ action: ControlAction) {
        button?.pressedChangedHandler = { [weak self] _, _, pressed in
            guard pressed else { return }
            onMainActor { self?.emit(action) }
        }
    }

    /// Moves on press and auto-repeats until released.
    private func onHold(_ button: GCControllerButtonInput, _ direction: Direction) {
        button.pressedChangedHandler = { [weak self] button, _, pressed in
            onMainActor { self?.setHeld(direction, pressed, from: button) }
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
            setHeld(direction, pressed, from: button)
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
        default: action = nil
        }
        if let action { emit(action) }
    }

    // MARK: - Movement and auto-repeat

    /// Treats the stick as a 4-way pad: a direction engages past `stickPress` and
    /// holds until it drops under `stickRelease` or another axis clearly wins.
    private func stickMoved(_ stick: GCControllerDirectionPad, x: Float, y: Float) {
        let id = ObjectIdentifier(stick)
        let old = stickDirections[id]
        let new = Self.stickDirection(x: x, y: y, current: old)
        guard new != old else { return }
        stickDirections[id] = new
        if old != nil { release(from: stick) }
        if let new { hold(new, from: stick) }
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

    private func setHeld(_ direction: Direction, _ pressed: Bool, from source: AnyObject) {
        if pressed { hold(direction, from: source) } else { release(from: source) }
    }

    /// Moves once now, then repeats after `repeatDelay` every `repeatInterval`.
    private func hold(_ direction: Direction, from source: AnyObject) {
        repeatTask?.cancel()
        held = (ObjectIdentifier(source), direction)
        emit(.move(direction))
        repeatTask = Task { [weak self] in
            try? await Task.sleep(for: Self.repeatDelay)
            while !Task.isCancelled, let input = self {
                input.emit(.move(direction))
                try? await Task.sleep(for: Self.repeatInterval)
            }
        }
    }

    /// Stops repeating if `source` is the input currently driving it.
    private func release(from source: AnyObject) {
        guard held?.source == ObjectIdentifier(source) else { return }
        stopRepeat()
    }

    private func stopRepeat() {
        repeatTask?.cancel()
        repeatTask = nil
        held = nil
    }

    private func resetHolds() {
        stopRepeat()
        stickDirections.removeAll()
    }

    private func emit(_ action: ControlAction) {
        onAction?(action)
    }
}
