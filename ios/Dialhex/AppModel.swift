// AppModel.swift — Screens, input routing, and turning game events into sound,
// haptics, and effects

import DialhexCore
import Foundation
import GameController
import Observation
import TipKit
import UIKit

enum Screen { case menu, playing, lobby, versus }

/// Where a dial turn came from, for the tips that teach the other ways to turn.
enum TurnSource { case touch, corner, twist, pad }

/// The first game's walkthrough: the bot is playing, or it's just handed over.
enum GuideStage: Equatable { case watching, yourTurn }

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
    /// Ids of the skins the game that just ended unlocked.
    var unlocked: [String] = []
    /// The six pieces under the dial, for the spinner.
    var dial = DialPieces.empty
    /// Hexes cleared this game, by colour index.
    var colorHexes = Array(repeating: 0, count: Progression.colorCount)
    /// The walkthrough's banner, while it shows.
    var guide: GuideStage?
    /// What just shifted in play, while its callout shows.
    var callout: Callout?
}

@Observable @MainActor
final class AppModel {
    static let modes: [Mode] = [.main, .endless, .sprint]
    /// Menu items: the modes, then versus (Apple TV only), then online co-op, then the skin,
    /// speed, connect (iPhone only), and how-to tiles (one row on screen, so they must stay
    /// adjacent and in this order).
    #if os(tvOS)
    static let versusRow: Int? = modes.count
    static let connectRow: Int? = nil
    #else
    static let versusRow: Int? = nil
    static let connectRow: Int? = speedRow + 1
    #endif
    static let onlineRow = modes.count + (versusRow == nil ? 0 : 1)
    static let skinRow = onlineRow + 1
    static let speedRow = skinRow + 1
    static let howToRow = speedRow + (connectRow == nil ? 1 : 2)
    static let menuCount = howToRow + 1
    /// The menu as a controller walks it: rows on screen, top to bottom, left to right.
    static let menuGrid: [[Int]] = {
        var rows = [Array(modes.indices)]
        if let versusRow { rows.append([versusRow]) }
        rows.append([onlineRow])
        rows.append(Array(skinRow...howToRow))
        return rows
    }()
    private static let skinKey = "dialhex_skin"
    private static let speedKey = "dialhex_speed"
    private static let handKey = "dialhex_left_handed"
    private static let walkthroughKey = "dialhex_walkthrough_seen"
    /// Finished assisted games so far; set to the limit by a MAIN win.
    private static let assistedGamesKey = "dialhex_assisted_games"
    /// The walkthrough hands over once the bot has cleared this many hexes,
    /// or after this long if it hasn't managed to.
    private static let guideHexes = 3
    private static let guideTimeLimit = 90.0
    /// How long "your turn" stays up after the handover.
    private static let yourTurnTime = 2.5
    /// Never flash a hard cut more than three times a second.
    private static let hardCutGap: TimeInterval = 1.0 / 3
    /// Taps on the logo that open every skin, and the longest pause allowed between them.
    private static let logoTapsToUnlock = 20
    private static let logoTapGap: TimeInterval = 1.5

    var screen = Screen.menu
    var menuSelection = 0
    private(set) var hud = HUDState()
    private(set) var controllerConnected = false
    /// The input last used; hints and tips name its buttons.
    private(set) var inputKind = InputKind.initial
    private(set) var skin: Skin
    /// The pace solo games start at; saved between launches.
    private(set) var speed: Speed
    /// Landscape iPhone play puts the spinner on the left of the bin; saved between launches.
    private(set) var leftHanded = UserDefaults.standard.bool(forKey: AppModel.handKey)
    /// Bumped on every hard-cut flash; the overlay flashes when it changes.
    private(set) var flashCount = 0
    /// How many skins are open. Mirrors `unlocks` so the menu updates when it changes.
    private(set) var unlockedCount = 1
    /// The launch intro is playing over the menu.
    private(set) var showingIntro = true
    /// The menu has started building in; set as the intro begins to fade, a beat before it ends.
    private(set) var menuRevealed = false
    /// The how-to-play page is open over the menu.
    private(set) var showingHowTo = false
    /// The how-to-play line a controller has scrolled to: a rule, or the back button after the last.
    private(set) var howToLine = 0
    /// Who's in for versus: set from the lobby until back on the menu.
    var lobby: Lobby?
    /// What the versus overlay shows; only republished when it changes.
    var versusHUD = VersusHUD()
    /// The code a phone enters to join, while the TV is taking phones.
    var joinCode: String?
    /// Why online co-op just ended or couldn't start, shown on the menu until the next try.
    var onlineNoticeText: String?

    /// The versus match on screen, if any.
    @ObservationIgnored var versus: Versus?
    /// The co-op game on screen, if any (the lobby starts one or the other). On an
    /// online guest it's the replica's copy, redrawn from the host's snapshots.
    @ObservationIgnored var coop: CoopGame?
    /// Online co-op with a Game Center friend.
    @ObservationIgnored let online = OnlineSession()
    /// The guest's copy of the host's game, in online co-op.
    @ObservationIgnored var replica: CoopReplica?
    /// Each versus player's controller rumble.
    @ObservationIgnored var playerHaptics: [PlayerID: Haptics] = [:]
    /// Sends a haptic to a phone controller, by peer id (set while phones can join).
    @ObservationIgnored var phoneHaptic: ((String, HapticEvent) -> Void)?
    /// The TV's listener for phone controllers (a `PhoneHost`, which needs tvOS 26).
    @ObservationIgnored var phoneHost: AnyObject?
    /// The phone-as-controller screen is open (iPhone). Game Center's access point
    /// would sit over its title, and has nothing to do there, so it steps aside.
    var showingController = false {
        didSet { scores.setOnMenu(screen == .menu && !showingController && !showingConnect) }
    }
    /// The connect page is open over the menu (iPhone): the paired gamepads, and the way
    /// to the phone-as-controller screen.
    private(set) var showingConnect = false {
        didSet { scores.setOnMenu(screen == .menu && !showingController && !showingConnect) }
    }

    @ObservationIgnored private(set) var game: Game?
    /// Turns the game (solo, co-op, or versus) into music; nil when there's none.
    @ObservationIgnored var conductor: Conductor?
    /// The auto-played game behind the menu: drawn, but silent and unscored.
    @ObservationIgnored private var demo: Game?
    @ObservationIgnored private var demoPlayer = DemoPlayer()
    /// Seconds a finished demo lingers before the next one starts.
    @ObservationIgnored private var demoRestart: Double?
    /// Plays the player's first game for them until it has cleared a few hexes.
    @ObservationIgnored private var guide: DemoPlayer?
    @ObservationIgnored private var guideTime = 0.0
    /// Seconds "your turn" has left on screen after the guide hands over.
    @ObservationIgnored private var yourTurnLeft = 0.0
    @ObservationIgnored let scene = GameScene()
    /// Each mode's best score and its Game Center leaderboard (observable itself).
    @ObservationIgnored let scores = Scores()
    @ObservationIgnored let sound = SoundEngine()
    @ObservationIgnored private let haptics = Haptics()
    @ObservationIgnored let controls = ControllerInput()
    @ObservationIgnored private var isNewHighScore = false
    @ObservationIgnored let unlocks = SkinUnlocks(skinCount: Brand.tokens.skins.count,
                                                  milestones: Brand.tokens.unlocks.milestones)
    @ObservationIgnored var unlockedNow: [String] = []
    @ObservationIgnored private var progressRecorded = false
    @ObservationIgnored private var lastHardCut = Date.distantPast
    @ObservationIgnored private var logoTaps = 0
    @ObservationIgnored private var lastLogoTap = Date.distantPast
    // This run's tallies for the tip rules; flushed into `TipState` at pause and game over
    @ObservationIgnored private var runTouchTurns = 0
    @ObservationIgnored private var runPadTurns = 0
    @ObservationIgnored private var runSingleClears = 0
    @ObservationIgnored private var runGlowSeen = false
    @ObservationIgnored private var runHoldRetired = false
    /// The in-play callouts beside the bin, and what they watch between events.
    @ObservationIgnored private let callouts = CalloutFeed()
    @ObservationIgnored private var wasTense = false
    @ObservationIgnored private var runFinaleCalled = false
    @ObservationIgnored private var runRescueCalled = false
    /// This game's hexes cleared, by colour index, for the HUD.
    @ObservationIgnored private var colorHexes = Array(repeating: 0, count: Progression.colorCount)
    /// An assisted game's hint: a dial where one turn finishes a hex, once one
    /// has been there a while without the player finding it.
    @ObservationIgnored private(set) var hint: Vertex?
    /// Seconds there's been a hex one turn away, unfound.
    @ObservationIgnored private var hintWait = 0.0
    /// Seconds until the board is next searched for a hint.
    @ObservationIgnored private var hintSearchLeft = 0.0
    /// Whether the idle timer is off because a game is running.
    @ObservationIgnored private var keepingAwake = false

    init() {
        let skins = Brand.tokens.skins
        let open = skins.prefix(SkinUnlocks(skinCount: skins.count, milestones: Brand.tokens.unlocks.milestones).unlockedCount)
        let saved = UserDefaults.standard.string(forKey: Self.skinKey)
        skin = Skin(open.first { $0.id == saved } ?? skins[0])
        unlockedCount = open.count
        speed = UserDefaults.standard.string(forKey: Self.speedKey).flatMap(Speed.init(rawValue:)) ?? .normal
        sound.style = skin.spec.sound
        scene.model = self
        online.model = self
        GameScene.spinnerOnLeft = leftHanded
        controls.onAction = { [weak self] action, source in self?.handle(action, from: source) }
        controls.onControllerChange = { [weak self] controller in self?.controllerChanged(controller) }
        controls.onKeyboardChange = { [weak self] connected in
            if !connected, self?.inputKind == .keyboard { self?.used(InputKind.initial) }
        }
        controls.onSourceLost = { [weak self] source in self?.sourceLost(source) }
        controls.start()
        // Apple TV takes phone controllers from the start: on the menu they steer it
        // like a remote, and in a game they play it
        #if os(tvOS)
        startTakingPhones()
        #endif
        scores.authenticate()
        startDemo()
        Lessons.start()
    }

    // MARK: - Screens

    /// The game the board shows: the player's, or the demo behind the menu.
    var boardGame: Game? { game ?? demo }

    /// The rules on the how-to page: the touch one only while playing by touch
    /// (so never on Apple TV, which has no touch screen).
    var howToRules: [BrandTokens.HowToCopy.Rule] {
        Brand.copy.howTo.rules.filter { $0.art != "touch" || inputKind == .touch }
    }

    /// On the top-level menu, Back belongs to the system (on Apple TV it returns
    /// to the Home Screen); everywhere else the game takes it.
    var backLeavesApp: Bool { screen == .menu && !showingHowTo && !showingIntro }

    /// The intro is over (or was skipped): hand over to the menu.
    func finishIntro() {
        menuRevealed = true
        showingIntro = false
    }

    /// The intro has started to fade: build the menu in underneath it.
    func revealMenu() {
        menuRevealed = true
    }

    /// A hex in the intro just formed: a tap, and a bigger one for the last.
    /// Silent on purpose: starting the audio engine during launch isn't safe,
    /// and opening the app shouldn't duck the player's music.
    func introBeat(_ index: Int) {
        haptics.play(index == 6 ? .levelUp : .rotate)
    }

    func showHowTo() {
        howToLine = 0
        showingHowTo = true
    }

    func hideHowTo() {
        showingHowTo = false
    }

    func showConnect() {
        showingConnect = true
    }

    func hideConnect() {
        showingController = false
        showingConnect = false
    }

    func start(_ mode: Mode) {
        sound.start()
        showingIntro = false
        showingHowTo = false
        demo = nil
        demoRestart = nil
        // A new player's first games are eased in. Not sprint: a slower clock
        // there would only cost them points.
        let assisted = mode != .sprint
            && UserDefaults.standard.integer(forKey: Self.assistedGamesKey) < Progression.assistedGames
        game = Game(mode: mode, speed: speed, assisted: assisted)
        colorHexes = Array(repeating: 0, count: Progression.colorCount)
        isNewHighScore = false
        unlockedNow = []
        progressRecorded = false
        runTouchTurns = 0
        runPadTurns = 0
        runSingleClears = 0
        runGlowSeen = false
        runHoldRetired = false
        runRescueCalled = false
        hint = nil
        hintWait = 0
        hintSearchLeft = 0
        callouts.reset()
        wasTense = false
        runFinaleCalled = false
        if mode == .sprint { SprintTip().invalidate(reason: .actionPerformed) }
        // The first game opens with the bot showing how it's played. Not in sprint,
        // where it would spend the player's clock; they'll see it in their first other game.
        yourTurnLeft = 0
        guideTime = 0
        if mode != .sprint && !UserDefaults.standard.bool(forKey: Self.walkthroughKey) {
            UserDefaults.standard.set(true, forKey: Self.walkthroughKey)
            guide = DemoPlayer(pace: 2)
        } else {
            guide = nil
        }
        skin.resetStrobe()
        menuSelection = Self.modes.firstIndex(of: mode) ?? 0
        screen = .playing
        scores.setOnMenu(false)
        scene.reset()
        scene.setLayout(.play, animated: true)
        conductor = Conductor(score: .forSkin(skin.id), stepTime: game!.stepTime, colors: game!.activeColors)
        sound.lofi = conductor?.score.groove != nil
        showColor(game!.activeColors.last!)
        refreshHUD()
    }

    func toMenu() {
        guide = nil
        recordGame()
        flushTipTallies()
        hint = nil
        game = nil
        conductor = nil
        screen = .menu
        scores.setOnMenu(true)
        scene.reset()
        startDemo()
        scene.setLayout(.menu, animated: true)
    }

    // MARK: - Demo

    func startDemo() {
        demo = Game(mode: .endless)
        // Play stays in the bin's lower bowl, under the logo
        demoPlayer = DemoPlayer(floor: Marks.logoBottomInBin)
        demoRestart = nil
        scene.reset()
    }

    private func tickDemo(_ dt: Double) {
        if let wait = demoRestart {
            demoRestart = wait - dt
            if wait - dt <= 0 { startDemo() }
            return
        }
        guard var demo else { return }
        let events = demoPlayer.update(&demo, by: dt)
        self.demo = demo
        for event in events {
            switch event {
            case .clear(let hexes, _): scene.showClear(hexes)
            case .gameOver: emptyDemo()
            default: break
            }
        }
        // The pile has climbed up to the letters: empty the bin and start over
        if demoRestart == nil, demo.board.contains(where: { cell, piece in
            !piece.isClearing && Grid.center(of: cell).x - 1.0 / 3 < Marks.logoBottomInBin && Dropper.isResting(demo.board, cell)
        }) {
            emptyDemo()
        }
    }

    /// Fade the demo's pieces away, then begin a new one.
    private func emptyDemo() {
        scene.emptyBoard()
        demoRestart = 0.6
    }

    // MARK: - Walkthrough

    /// The player has done something: the bot stops and the game is theirs.
    private func takeOver() {
        guard guide != nil else { return }
        guide = nil
        yourTurnLeft = Self.yourTurnTime
    }

    /// Advance the player's game, with the guide playing it while the walkthrough runs.
    private func advance(_ game: inout Game, by dt: Double) -> [GameEvent] {
        if yourTurnLeft > 0 && game.phase == .playing { yourTurnLeft -= dt }
        guard var guide else { return game.update(by: dt) }
        let events = guide.update(&game, by: dt)
        self.guide = guide
        if game.phase == .playing { guideTime += dt }
        if game.phase == .gameOver {
            self.guide = nil
        } else if game.hexesCleared >= Self.guideHexes || guideTime >= Self.guideTimeLimit {
            takeOver()
        }
        return events
    }

    func togglePause() {
        game?.togglePause()
        if game?.phase == .paused { flushTipTallies() }
        refreshHUD()
    }

    /// The app went to the background or a controller dropped: stop the clock.
    func pauseIfPlaying() {
        pauseVersusIfPlaying()
        guard game?.phase == .playing else { return }
        togglePause()
    }

    // MARK: - Skins

    /// The skins open so far, in unlock order.
    var unlockedSkins: [SkinSpec] { Array(Brand.tokens.skins.prefix(unlockedCount)) }

    /// Hidden shortcut: tap the logo 20 times in a row to open every skin.
    func logoTapped() {
        let now = Date()
        logoTaps = now.timeIntervalSince(lastLogoTap) <= Self.logoTapGap ? logoTaps + 1 : 1
        lastLogoTap = now
        guard logoTaps >= Self.logoTapsToUnlock, unlockedCount < Brand.tokens.skins.count else { return }
        logoTaps = 0
        unlocks.unlockAll()
        unlockedCount = unlocks.unlockedCount
        haptics.play(.levelUp)
        sound.play(.levelUp(color: 0))
    }

    /// Switch to the next unlocked skin, wrapping around.
    func cycleSkin() {
        let open = unlockedSkins
        let i = open.firstIndex { $0.id == skin.id } ?? 0
        skin = Skin(open[(i + 1) % open.count])
        SkinTip().invalidate(reason: .actionPerformed)
        sound.style = skin.spec.sound
        UserDefaults.standard.set(skin.id, forKey: Self.skinKey)
    }

    /// Switch to the next speed, wrapping around.
    func cycleSpeed() {
        let all = Speed.allCases
        speed = all[((all.firstIndex(of: speed) ?? 0) + 1) % all.count]
        UserDefaults.standard.set(speed.rawValue, forKey: Self.speedKey)
    }

    /// Bank this game's hexes (and a MAIN win) toward skin unlocks, once per game.
    private func recordGame() {
        guard let game, !progressRecorded else { return }
        progressRecorded = true
        bankProgress(hexes: game.hexesCleared, mainWin: game.won)
        // Only finished games use up the assist, so quitting early doesn't spend it
        if game.assisted && game.phase == .gameOver {
            let played = UserDefaults.standard.integer(forKey: Self.assistedGamesKey)
            UserDefaults.standard.set(game.won ? Progression.assistedGames : played + 1, forKey: Self.assistedGamesKey)
        }
    }

    /// Bank hexes (and a MAIN win) toward skin unlocks, noting any skins that opened.
    func bankProgress(hexes: Int, mainWin: Bool) {
        let opened = unlocks.record(hexes: hexes, mainWin: mainWin)
        unlockedCount = unlocks.unlockedCount
        unlockedNow = opened.map { Brand.tokens.skins[$0].id }
        if !opened.isEmpty { Task { await TipState.skinUnlocked.donate() } }
    }

    /// Bank this run's turns and clears into the tip rules.
    private func flushTipTallies() {
        if runTouchTurns > 0 { TipState.touchTurns += runTouchTurns }
        if runSingleClears > 0 { TipState.singleClears += runSingleClears }
        runTouchTurns = 0
        runSingleClears = 0
    }

    /// Feed a finished run to the tips: short losses, controller-only play, MAIN games, new bests.
    private func gameEndedForTips(_ game: Game) {
        let binFull = !game.won && game.sprintTimeRemaining != 0
        if binFull && game.hexesCleared < TipState.shortRunHexes {
            Task { await TipState.shortRun.donate() }
        }
        // Someone who only ever turns with a controller has no use for the twist
        if runPadTurns >= TipState.twistAfterTurns && runTouchTurns == 0 {
            TwistTip().invalidate(reason: .actionPerformed)
        }
        if game.mode == .main { TipState.mainGames += game.won ? 3 : 1 }
        if isNewHighScore { TipState.bestMode = game.mode.rawValue }
        flushTipTallies()
    }

    /// Open the leaderboard for a mode, from the Game Center tip.
    func showLeaderboard(for mode: Mode) {
        GameCenterTip().invalidate(reason: .actionPerformed)
        scores.showLeaderboard(for: mode)
    }

    /// Single-hue skins cut to their next colour on every clear, with a rate-limited flash.
    private func hardCut() {
        guard skin.hardCuts else { return }
        skin.advanceStrobe()
        let now = Date()
        guard now.timeIntervalSince(lastHardCut) >= Self.hardCutGap else { return }
        lastHardCut = now
        flashCount += 1
    }

    // MARK: - Input

    func rotate(_ direction: RotationDirection, from source: TurnSource = .touch) {
        if screen == .versus && lobby?.online != nil {
            onlineTouchInput(.rotate(direction))
            return
        }
        guard var game else { return }
        if game.phase == .playing { takeOver() }
        let events = game.rotate(direction)
        self.game = game
        if events.contains(.rotate) { countTurn(from: source) }
        handle(events)
    }

    /// Count a turn for the tips, and retire the tip for a way of turning once it's used.
    private func countTurn(from source: TurnSource) {
        if source != .pad { used(.touch) }
        switch source {
        case .touch:
            runTouchTurns += 1
        case .corner:
            runTouchTurns += 1
            CornerTip().invalidate(reason: .actionPerformed)
        case .twist:
            TwistTip().invalidate(reason: .actionPerformed)
        case .pad:
            runPadTurns += 1
        }
    }

    /// Move the landscape spinner to the other side of the bin.
    func toggleHand() {
        leftHanded.toggle()
        UserDefaults.standard.set(leftHanded, forKey: Self.handKey)
        GameScene.spinnerOnLeft = leftHanded
        scene.spinnerSideChanged()
    }

    /// A finger dragged across the board: the dial follows it, to the nearest dial
    /// under the finger (in lattice units, converted by the scene).
    func drag(to point: LatticePoint) {
        used(.touch)
        if screen == .versus && lobby?.online != nil {
            onlineDrag(to: point)
            return
        }
        guard var game, game.phase == .playing else { return }
        takeOver()
        guard let dial = Grid.nearestDial(to: point), dial != game.cursor.vertex else { return }
        game.moveCursor(to: dial)
        self.game = game
    }

    /// A tap on the board, already converted to lattice units by the scene.
    func tap(at point: LatticePoint) {
        used(.touch)
        if screen == .versus && lobby?.online != nil {
            onlineTap(at: point)
            return
        }
        guard var game else { return }
        if game.phase == .playing { takeOver() }
        let events = game.tap(at: point)
        self.game = game
        if events.contains(.rotate) { countTurn(from: .touch) }
        handle(events)
        refreshHUD()
    }

    /// The player just used `kind`: name its buttons from now on.
    func used(_ kind: InputKind) {
        guard kind != inputKind else { return }
        inputKind = kind
        TipState.inputKind = kind.rawValue
    }

    private func handle(_ action: ControlAction, from source: InputSource) {
        used(controls.kind(of: source))
        // Any button skips the intro, and does nothing else
        if showingIntro {
            finishIntro()
            return
        }
        switch screen {
        case .menu: handleMenu(action, from: source)
        case .playing: handleGame(action)
        case .lobby where lobby?.online != nil, .versus where lobby?.online != nil: handleOnline(action)
        case .lobby: handleLobby(action, from: source)
        case .versus: handleVersus(action, from: source)
        }
    }

    private func handleMenu(_ action: ControlAction, from source: InputSource) {
        // The how-to page only scrolls and listens for a way back
        if showingHowTo {
            switch action {
            case .confirm, .cancel: hideHowTo()
            case .move(.up): howToLine = max(0, howToLine - 1)
            case .move(.down): howToLine = min(howToRules.count, howToLine + 1)
            default: break
            }
            return
        }
        // So does the connect page (a gamepad that can press buttons here is already connected)
        if showingConnect {
            if action == .confirm || action == .cancel { hideConnect() }
            return
        }
        // Up and down step between rows, keeping roughly the same place across;
        // left and right move along a row, wrapping at its ends
        let grid = Self.menuGrid
        let row = grid.firstIndex { $0.contains(menuSelection) } ?? 0
        let column = grid[row].firstIndex(of: menuSelection) ?? 0
        func step(_ rows: Int) {
            let from = grid[row], to = grid[(row + rows + grid.count) % grid.count]
            // Off a full-width button, land on the row's first item
            let across = from.count == 1 ? 0 : (Double(column) + 0.5) / Double(from.count)
            menuSelection = to[min(to.count - 1, Int(across * Double(to.count)))]
        }
        switch action {
        case .move(.up):
            step(-1)
        case .move(.down):
            step(1)
        case .move(.left):
            menuSelection = grid[row][(column - 1 + grid[row].count) % grid[row].count]
        case .move(.right):
            menuSelection = grid[row][(column + 1) % grid[row].count]
        case .confirm:
            if Self.modes.indices.contains(menuSelection) {
                start(Self.modes[menuSelection])
            } else if menuSelection == Self.versusRow {
                openLobby(joining: source)
            } else if menuSelection == Self.onlineRow {
                openOnline(from: source)
            } else if menuSelection == Self.connectRow {
                showConnect()
            } else if menuSelection == Self.howToRow {
                showHowTo()
            } else if menuSelection == Self.speedRow {
                cycleSpeed()
            } else {
                cycleSkin()
            }
        case .quickStart(let mode):
            start(mode)
        case .cycleSkin:
            cycleSkin()
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
            takeOver()
            game.moveCursor(direction)
            self.game = game
        case (.playing, .place(let vertex)):
            takeOver()
            game.moveCursor(to: vertex)
            self.game = game
        case (.playing, .rotate(let direction)):
            rotate(direction, from: .pad)
        case (.playing, .confirm):
            rotate(.clockwise, from: .pad)
        default:
            break
        }
    }

    private func controllerChanged(_ controller: GCController?) {
        haptics.setController(controller)
        if controller == nil && controllerConnected { pauseIfPlaying() }
        controllerConnected = controller != nil
        // Picking up a gamepad on iPhone means playing with it; put it down and it's the
        // screen again. (Apple TV waits for a press: its simulator always has a virtual one.)
        #if os(iOS)
        if controller != nil {
            used(.gamepad)
        } else if inputKind == .gamepad {
            used(InputKind.initial)
        }
        #endif
        if let game { showColor(game.activeColors.last!) }
    }

    // MARK: - Frame

    /// Advance the game; called by the scene once per frame.
    func tick(_ dt: Double) {
        if screen == .menu || screen == .lobby { tickDemo(dt) }
        if screen == .versus { tickVersus(dt) }
        defer {
            syncPhones()
            keepAwake()
        }
        guard var game else { return }
        let events = advance(&game, by: dt)
        self.game = game
        handle(events)
        conduct(events, fallProgress: game.fallProgress, danger: Self.fill(game.board),
                sprintTimeRemaining: game.sprintTimeRemaining)
        watchShifts(game, by: dt)
        watchForHint(game, by: dt)
        refreshHUD()
    }

    /// Hints wait this long, so a player gets a fair go at spotting the hex first.
    private static let hintDelay = 3.0
    /// Seconds between searches: about two fall steps, since only falls and turns change the board.
    private static let hintSearchGap = 0.25

    /// In an assisted game the player is driving, mark a hex one turn away once
    /// it's gone unnoticed for a few seconds. A hint stays put while it still
    /// works, so it doesn't hop about as the dial moves.
    private func watchForHint(_ game: Game, by dt: Double) {
        guard game.assisted, guide == nil, game.phase == .playing else {
            if game.phase == .gameOver { hint = nil }
            return
        }
        hintSearchLeft -= dt
        guard hintSearchLeft <= 0 else { return }
        hintSearchLeft = Self.hintSearchGap

        let board = game.board
        let found = hint.flatMap { Hints.finishesHex(board, at: $0) ? $0 : nil }
            ?? Hints.oneTurnFromHex(on: board, near: game.cursor.vertex)
        guard let found else {
            hint = nil
            hintWait = 0
            return
        }
        hintWait += Self.hintSearchGap
        guard hintWait >= Self.hintDelay else { return }
        if hint == nil { callOut(.hint) }
        hint = found
    }

    /// While the walkthrough's banner is up, it has the stats column to itself.
    private var calloutsQuiet: Bool { guide != nil || yourTurnLeft > 0 }

    /// Call out a shift, unless the walkthrough is talking.
    private func callOut(_ kind: CalloutKind, fill: [String: String] = [:], colors: [Int] = []) {
        guard !calloutsQuiet else { return }
        callouts.post(kind, fill: fill, colors: colors)
    }

    /// The shifts no event names: the dial holding a piece up, the music
    /// tensing over a filling bin, and a sprint's last stretch.
    private func watchShifts(_ game: Game, by dt: Double) {
        guard game.phase == .playing else { return }
        callouts.tick(dt)
        // The callout says what the music is doing, so it follows the music's own thresholds
        let tense = conductor?.isTense ?? false
        if tense && !wasTense { callOut(.danger) }
        wasTense = tense
        if let left = game.sprintTimeRemaining, !runFinaleCalled {
            let finish = conductor?.score.sprintFinish ?? 30
            if left <= finish {
                runFinaleCalled = true
                callOut(.finale, fill: ["seconds": "\(Int(finish))"])
            }
        }
        if callouts.wants(.held) && game.isHoldingPiece { callOut(.held) }
    }

    /// Hand the conductor this frame's events and the game's clock, and play what comes back.
    /// Safe to call more than once a frame: the beat only moves when `fallProgress` wraps.
    func conduct(_ events: [GameEvent], fallProgress: Double, danger: Double, sprintTimeRemaining: Double?) {
        guard var conductor else { return }
        sound.play(conductor.advance(fallProgress: fallProgress, events: events, danger: danger,
                                     sprintTimeRemaining: sprintTimeRemaining))
        self.conductor = conductor
    }

    /// How full a bin is (0…1), for the music's danger.
    static func fill(_ board: Board) -> Double {
        Double(board.count) / Double(Grid.cells.count)
    }

    /// While a game is running the screen mustn't dim or the Apple TV start its
    /// screensaver: someone playing on a phone or a gamepad may not touch the remote
    /// (or the screen) for minutes. Paused, over, or on the menu, it can sleep again.
    private func keepAwake() {
        let playing = (screen == .playing && game?.phase == .playing) || (screen == .versus && matchPhase == .playing)
        guard playing != keepingAwake else { return }
        keepingAwake = playing
        UIApplication.shared.isIdleTimerDisabled = playing
    }

    /// The solo game's rumble: the device and its controller, and any phones playing it.
    private func playHaptic(_ event: HapticEvent) {
        haptics.play(event)
        soloPhoneHaptic(event)
    }

    private func handle(_ events: [GameEvent]) {
        guard let game else { return }
        for event in events {
            switch event {
            case .rotate:
                sound.play(.rotate)
                playHaptic(.rotate)
            case .spawn:
                // The conductor plays the new triangle's note
                // Powers only arrive on new pieces, so this is where a glow first shows
                if !runGlowSeen && game.board.values.contains(where: { $0.power != nil }) {
                    runGlowSeen = true
                    Task { await TipState.glowSeen.donate() }
                    callOut(.glow)
                }
            case .clear(let hexes, _):
                for hex in hexes where colorHexes.indices.contains(hex.color) { colorHexes[hex.color] += 1 }
                // The walkthrough's clears are the bot's, not lessons the player has learned
                if guide == nil {
                    if hexes.count > 1 {
                        CombosTip().invalidate(reason: .actionPerformed)
                    } else {
                        runSingleClears += 1
                    }
                }
                if !runHoldRetired && game.hexesCleared >= TipState.holdLearnedHexes {
                    runHoldRetired = true
                    HoldTip().invalidate(reason: .actionPerformed)
                }
                sound.play(.shimmer) // the conductor plays the arpeggio, on the beat
                playHaptic(.clear(hexes: hexes.count))
                hardCut()
                scene.showClear(hexes)
            case .power(let power):
                // The assist's rescue drains like a glowing piece but isn't one
                let isRescue = power == .drain && game.rescued && !runRescueCalled
                if !isRescue { GlowTip().invalidate(reason: .actionPerformed) }
                switch power {
                case .drain where isRescue:
                    runRescueCalled = true
                    callOut(.rescue)
                case .drain: callOut(.drain)
                case .swap: callOut(.swap, colors: game.lastSwap.map { [$0.from, $0.to] } ?? [])
                }
                playHaptic(.power)
                scene.shake(duration: 0.3, intensity: 4)
            case .levelUp(let color):
                // The new colour's voice strums the next chord on the coming boundary
                sound.play(.shimmer)
                playHaptic(.levelUp)
                showColor(color)
                let points = Double(Progression.score(hexes: 1, level: game.level)) * game.speed.pointsMultiplier
                callOut(.levelUp, fill: ["level": "\(game.level)", "points": "\(Int(points.rounded()))"], colors: [color])
            case .gameOver(let won):
                // A win resolves home in the music instead
                if !won { sound.play(.gameOver) }
                playHaptic(.gameOver)
                isNewHighScore = scores.finish(game.score, mode: game.mode)
                recordGame()
                gameEndedForTips(game)
            }
        }
    }

    func showColor(_ color: Int) {
        controls.setLightColor(skin.piece(color).value)
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
            hexesCleared: game.hexesCleared,
            unlocked: unlockedNow,
            dial: .at(game.cursor.vertex, on: game.board),
            colorHexes: colorHexes,
            guide: guide != nil ? .watching : yourTurnLeft > 0 ? .yourTurn : nil,
            callout: game.phase == .playing ? callouts.current : nil
        )
        if next != hud { hud = next }
    }
}
