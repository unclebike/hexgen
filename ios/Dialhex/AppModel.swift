// AppModel.swift — Screens, input routing, and turning game events into sound,
// haptics, and effects

import DialhexCore
import GameController
import Observation

enum Screen { case menu, playing }

/// What the SwiftUI overlay shows. Only republished when it changes, so the
/// HUD doesn't re-render every frame.
struct HUDState: Equatable {
    var score = 0
    var mode = Mode.main
    var phase = Phase.playing
    var won = false
    var isNewHighScore = false
    var sprintSeconds: Int?
    var activeColors: [Int] = []
    var hexesCleared = 0
}

@Observable @MainActor
final class AppModel {
    static let modes: [Mode] = [.main, .endless, .sprint]

    private(set) var screen = Screen.menu
    var menuSelection = 0
    private(set) var hud = HUDState()
    private(set) var controllerConnected = false

    @ObservationIgnored private(set) var game: Game?
    @ObservationIgnored let scene = GameScene()
    @ObservationIgnored let highScores = HighScores()
    @ObservationIgnored private let sound = SoundEngine()
    @ObservationIgnored private let haptics = Haptics()
    @ObservationIgnored private let controls = ControllerInput()
    @ObservationIgnored private var isNewHighScore = false

    init() {
        scene.model = self
        controls.onAction = { [weak self] action in self?.handle(action) }
        controls.onControllerChange = { [weak self] controller in self?.controllerChanged(controller) }
        controls.start()
    }

    // MARK: - Screens

    func start(_ mode: Mode) {
        sound.start()
        game = Game(mode: mode)
        isNewHighScore = false
        menuSelection = Self.modes.firstIndex(of: mode) ?? 0
        screen = .playing
        scene.reset()
        sound.startDrone(colorCount: game!.activeColors.count)
        showColor(game!.activeColors.last!)
        refreshHUD()
    }

    func toMenu() {
        game = nil
        screen = .menu
        sound.stopDrone()
        scene.reset()
    }

    func togglePause() {
        game?.togglePause()
        refreshHUD()
    }

    /// The app went to the background or a controller dropped: stop the clock.
    func pauseIfPlaying() {
        guard game?.phase == .playing else { return }
        togglePause()
    }

    // MARK: - Input

    func rotate(_ direction: RotationDirection) {
        guard var game else { return }
        let events = game.rotate(direction)
        self.game = game
        handle(events)
    }

    /// A tap on the board, already converted to lattice units by the scene.
    func tap(at point: LatticePoint) {
        guard var game else { return }
        let events = game.tap(at: point)
        self.game = game
        handle(events)
        refreshHUD()
    }

    private func handle(_ action: ControlAction) {
        switch screen {
        case .menu: handleMenu(action)
        case .playing: handleGame(action)
        }
    }

    private func handleMenu(_ action: ControlAction) {
        switch action {
        case .move(.up):
            menuSelection = (menuSelection + Self.modes.count - 1) % Self.modes.count
        case .move(.down):
            menuSelection = (menuSelection + 1) % Self.modes.count
        case .confirm:
            start(Self.modes[menuSelection])
        case .quickStart(let mode):
            start(mode)
        default:
            break
        }
    }

    private func handleGame(_ action: ControlAction) {
        guard var game else { return }
        switch (game.phase, action) {
        case (.gameOver, .confirm), (.gameOver, .cancel), (.paused, .cancel):
            toMenu()
        case (.paused, .pause), (.paused, .confirm), (.playing, .pause), (.playing, .cancel):
            togglePause()
        case (.playing, .move(let direction)):
            game.moveCursor(direction)
            self.game = game
        case (.playing, .rotate(let direction)):
            rotate(direction)
        case (.playing, .confirm):
            rotate(.clockwise)
        default:
            break
        }
    }

    private func controllerChanged(_ controller: GCController?) {
        haptics.setController(controller)
        if controller == nil && controllerConnected { pauseIfPlaying() }
        controllerConnected = controller != nil
        if let game { showColor(game.activeColors.last!) }
    }

    // MARK: - Frame

    /// Advance the game; called by the scene once per frame.
    func tick(_ dt: Double) {
        guard var game else { return }
        let events = game.update(by: dt)
        self.game = game
        handle(events)
        refreshHUD()
    }

    private func handle(_ events: [GameEvent]) {
        guard let game else { return }
        for event in events {
            switch event {
            case .rotate:
                sound.play(.rotate)
                haptics.play(.rotate)
            case .spawn(let color):
                sound.play(.place(color: color))
            case .clear(let hexes, _):
                for hex in hexes { sound.play(.clear(color: hex.color)) }
                haptics.play(.clear(hexes: hexes.count))
                scene.showClear(hexes)
            case .power:
                haptics.play(.power)
                scene.shake(duration: 0.3, intensity: 4)
            case .levelUp(let color):
                sound.play(.levelUp(color: color))
                sound.startDrone(colorCount: game.activeColors.count)
                haptics.play(.levelUp)
                showColor(color)
            case .gameOver:
                sound.play(.gameOver)
                sound.stopDrone()
                haptics.play(.gameOver)
                isNewHighScore = highScores.record(game.score, for: game.mode)
            }
        }
    }

    private func showColor(_ color: Int) {
        controls.setLightColor(Palette.colors[color])
    }

    private func refreshHUD() {
        guard let game else { return }
        let next = HUDState(
            score: game.score,
            mode: game.mode,
            phase: game.phase,
            won: game.won,
            isNewHighScore: isNewHighScore,
            sprintSeconds: game.sprintTimeRemaining.map { Int($0.rounded(.up)) },
            activeColors: game.activeColors,
            hexesCleared: game.hexesCleared
        )
        if next != hud { hud = next }
    }
}
