// AppModel+Versus.swift — Local multiplayer: the lobby, the match, and its effects
//
// The lobby seats input devices (gamepads, remotes, the keyboard, phones) as
// players through a Roster, and starts either a versus match or a co-op game.
// Versus is a DialhexCore `Versus`: one ordinary Game per player, and each
// player's effects play on their own board. Co-op is a `CoopGame`: two dials
// on one shared board. Either way, a player's turns rumble their own
// controller (or phone).

import DialhexCore
import Foundation
import GameController

/// What the lobby will start: a versus rule, or co-op in one of the modes.
enum MatchKind: Hashable, CaseIterable {
    case versus(Versus.Rule)
    case coop(Mode)

    /// Versus rules first, then co-op, in the order left and right step through them.
    static let allCases: [MatchKind] = Versus.Rule.allCases.map(versus) + Mode.allCases.map(coop)

    /// How many players it takes.
    var playerRange: ClosedRange<Int> {
        switch self {
        case .versus: Versus.playerRange
        case .coop: CoopGame.players.count...CoopGame.players.count
        }
    }

    var isCoop: Bool {
        if case .coop = self { return true }
        return false
    }
}

/// Who's in for a match, and what they'll play.
struct Lobby: Equatable {
    var roster = Roster<InputSource>()
    /// What each device is called, for the lobby's slots.
    var names: [InputSource: String] = [:]
    var kind = MatchKind.versus(.sprintRace)
    /// Set for online co-op: who's hosting, and who with (see AppModel+Online.swift).
    var online: OnlineLink?

    /// Enough players are seated to start, and not too many.
    var canStart: Bool { kind.playerRange.contains(roster.players.count) }

    func source(of player: PlayerID) -> InputSource? {
        if case .active(let source) = roster.seats[player] { return source }
        return nil
    }

    func name(of player: PlayerID) -> String? {
        source(of: player).flatMap { names[$0] }
    }
}

/// What the versus (or co-op) overlay shows.
struct VersusHUD: Equatable {
    struct Board: Equatable {
        let player: PlayerID
        var name: String?
        var score = 0
        var hexes = 0
        var out = false
        var dropped = false
    }

    var kind = MatchKind.versus(.sprintRace)
    var phase = Phase.playing
    var sprintSeconds: Int?
    /// One per player. In co-op they share the bin, so every one has the team's score.
    var boards: [Board] = []
    var winners: [PlayerID]?
    /// Co-op only: the team cleared MAIN.
    var won = false
    /// Ids of the skins the match just unlocked.
    var unlocked: [String] = []
    /// Online co-op only: the six pieces under the local player's dial, for the spinner.
    var dial: DialPieces?
}

extension AppModel {
    // MARK: - Lobby

    /// Open the versus lobby, with the device that chose it as P1.
    func openLobby(joining source: InputSource) {
        lobby = Lobby()
        controls.tracksCurrentController = false
        screen = .lobby
        join(source)
        startTakingPhones()
    }

    /// Back to the menu from the lobby.
    func closeLobby() {
        if let lobby {
            for player in lobby.roster.players {
                if let source = lobby.source(of: player) { light(source, as: nil) }
            }
        }
        lobby = nil
        // Phones stay connected: back on the menu they steer it and the solo game
        controls.tracksCurrentController = true
        screen = .menu
        if let color = boardGame?.activeColors.last { showColor(color) }
    }

    func handleLobby(_ action: ControlAction, from source: InputSource) {
        guard var lobby else { return }
        let player = lobby.roster.player(for: source)
        switch action {
        case .confirm, .pause:
            if player == nil {
                join(source)
            } else if lobby.canStart {
                startMatch()
            }
        case .cancel:
            if player != nil {
                leave(source)
                if self.lobby?.roster.players.isEmpty == true { closeLobby() }
            } else if lobby.roster.players.isEmpty {
                closeLobby()
            }
        case .move(let direction) where player != nil && (direction == .left || direction == .right):
            let kinds = MatchKind.allCases
            let i = kinds.firstIndex(of: lobby.kind) ?? 0
            lobby.kind = kinds[(i + (direction == .right ? 1 : kinds.count - 1)) % kinds.count]
            self.lobby = lobby
            refreshVersusHUD()
        default:
            break
        }
    }

    /// Seat a device as the next player (or, mid-match, in a dropped player's place).
    @discardableResult
    func join(_ source: InputSource, name: String? = nil) -> PlayerID? {
        guard var lobby, let player = lobby.roster.join(source) else { return nil }
        lobby.names[source] = name ?? deviceName(source)
        self.lobby = lobby
        light(source, as: player)
        playerHaptics[player] = haptics(for: source)
        haptic(.rotate, for: player)
        refreshVersusHUD()
        return player
    }

    /// A device leaves the lobby; later players move up.
    func leave(_ source: InputSource) {
        guard var lobby, lobby.roster.player(for: source) != nil else { return }
        light(source, as: nil)
        lobby.roster.leave(source)
        lobby.names[source] = nil
        self.lobby = lobby
        relightPlayers()
    }

    /// A device went away (unplugged, out of range, phone dropped).
    func sourceLost(_ source: InputSource) {
        guard var lobby, let player = lobby.roster.player(for: source) else { return }
        switch screen {
        case .lobby:
            leave(source)
        case .versus:
            lobby.roster.leave(source) // the slot waits for someone to take over
            self.lobby = lobby
            playerHaptics[player] = nil
            if matchPhase == .playing { toggleMatchPause() }
            refreshVersusHUD()
            phoneScreensChanged()
        default:
            break
        }
    }

    // MARK: - Match

    /// Start a match (or a rematch) with everyone seated; a seat whose controller dropped is let go.
    func startMatch() {
        guard var lobby else { return }
        for player in lobby.roster.dropped { lobby.roster.forfeit(player) }
        guard lobby.canStart else {
            self.lobby = lobby
            if screen == .versus { backToLobby() }
            return
        }
        lobby.roster.lock()
        self.lobby = lobby
        let players = lobby.roster.players
        scene.reset()
        switch lobby.kind {
        case .versus(let rule):
            versus = Versus(players: players, rule: rule, seed: .random(in: 0...UInt64.max))
            coop = nil
            scene.showCoop(nil)
            scene.showVersus(players)
        case .coop(let mode):
            // The roster numbers players without gaps, so two players are P1 and P2
            coop = CoopGame(mode: mode, speed: speed)
            versus = nil
            scene.showVersus(nil)
            scene.showCoop(Dictionary(uniqueKeysWithValues: players.map { ($0, playerColor($0)) }),
                           spinner: lobby.online != nil)
        }
        unlockedNow = []
        screen = .versus
        if lobby.online != nil { online.hostRestarted() }
        sound.start()
        // One conductor for the match: versus bins share a clock (all at normal speed), co-op has one bin
        let stepTime = versus?.boards.values.first?.stepTime ?? Game.fallStep * speed.pace
        conductor = Conductor(score: .forSkin(skin.id), stepTime: stepTime, colors: Progression.initialColors)
        sound.lofi = conductor?.score.groove != nil
        refreshVersusHUD()
        phoneScreensChanged()
    }

    /// From a finished or abandoned match back to the lobby, everyone still seated.
    private func backToLobby() {
        versus = nil
        coop = nil
        lobby?.roster.unlock()
        playerHaptics = playerHaptics.filter { lobby?.source(of: $0.key) != nil }
        relightPlayers()
        conductor = nil
        scene.showVersus(nil)
        scene.showCoop(nil)
        startDemo()
        scene.setLayout(.menu, animated: false)
        screen = .lobby
        phoneScreensChanged()
    }

    func handleVersus(_ action: ControlAction, from source: InputSource) {
        guard let lobby, let phase = matchPhase else { return }
        let player = lobby.roster.player(for: source)
        switch phase {
        case .playing:
            guard let player else { return }
            switch action {
            case .move(let direction): matchInput(.move(direction), from: player)
            case .place(let vertex): matchInput(.place(vertex), from: player)
            case .rotate(let direction): matchInput(.rotate(direction), from: player)
            case .confirm: matchInput(.rotate(.clockwise), from: player)
            case .pause, .cancel: toggleMatchPause()
            default: break
            }
        case .paused where !lobby.roster.dropped.isEmpty:
            // Someone's controller dropped: a free device takes over, or a player plays on without them
            if action == .confirm && player == nil {
                join(source)
            } else if action == .confirm {
                for dropped in lobby.roster.dropped {
                    forfeitMatch(dropped)
                    self.lobby?.roster.forfeit(dropped)
                }
                if matchPhase == .paused { toggleMatchPause() }
            } else if action == .cancel && player != nil {
                backToLobby()
                return
            }
        case .paused:
            guard player != nil else { return }
            switch action {
            case .confirm, .pause: toggleMatchPause()
            case .cancel:
                backToLobby()
                return
            default: break
            }
        case .gameOver:
            guard player != nil else { return }
            switch action {
            case .confirm:
                startMatch() // a rematch with whoever's still here
                return
            case .cancel:
                backToLobby()
                return
            default: break
            }
        }
        refreshVersusHUD()
        if action == .pause || action == .cancel || action == .confirm { phoneScreensChanged() }
    }

    func tickVersus(_ dt: Double) {
        if isOnlineGuest {
            // The host runs the game; the guest's copy only animates between snapshots
            tickOnlineGuest(dt)
        } else if var match = versus {
            let events = match.update(by: dt)
            versus = match
            handle(events)
        } else if var game = coop {
            let events = game.update(by: dt)
            coop = game
            handleCoop(events, from: nil)
            if lobby?.online != nil { online.hostTick(game, events: events, by: nil) }
        }
        refreshVersusHUD()
    }

    /// The app went to the background: stop the match clock.
    func pauseVersusIfPlaying() {
        guard screen == .versus, matchPhase == .playing else { return }
        toggleMatchPause()
        refreshVersusHUD()
        phoneScreensChanged()
    }

    // MARK: - Either kind of match

    /// The running match's phase: versus or co-op.
    var matchPhase: Phase? { versus?.phase ?? coop?.phase }

    func matchInput(_ input: PlayerInput, from player: PlayerID) {
        if var match = versus {
            let events = match.apply(input, from: player)
            versus = match
            handle(events)
        } else if var game = coop {
            let events = game.apply(input, from: player)
            coop = game
            handleCoop(events, from: player)
            if lobby?.online != nil { online.hostTick(game, events: events, by: player) }
        }
    }

    /// Any player pauses (and resumes) everyone. An online guest asks the host,
    /// and the next snapshot shows it.
    func toggleMatchPause() {
        if isOnlineGuest {
            online.send(.pause(coop?.phase == .playing))
            return
        }
        versus?.togglePause()
        coop?.togglePause()
    }

    /// Play on without a player whose controller dropped.
    private func forfeitMatch(_ player: PlayerID) {
        if var match = versus {
            let events = match.forfeit(player)
            versus = match
            handle(events)
        } else {
            // Their dial lifts off the shared board; the other player carries on
            coop?.leave(player)
        }
    }

    private func handle(_ events: [Versus.Event]) {
        // The music follows the match as a whole. Every bin's clears play, but
        // only the leader's spawns (four bins of spawns at once is just noise),
        // a colour joins the first time anyone reaches it, and the fullest bin
        // sets the danger.
        let leader = versus.flatMap { match in
            match.activePlayers.max { (match.boards[$0]?.hexesCleared ?? 0) < (match.boards[$1]?.hexesCleared ?? 0) }
        }
        var music: [GameEvent] = []
        for event in events {
            switch event {
            case .board(let player, let event):
                switch event {
                case .rotate:
                    sound.play(.rotate)
                    haptic(.rotate, for: player)
                case .spawn:
                    if player == leader { music.append(event) }
                case .clear(let hexes, _):
                    sound.play(.shimmer)
                    music.append(event)
                    haptic(.clear(hexes: hexes.count), for: player)
                    scene.showClear(hexes, for: player)
                case .power:
                    haptic(.power, for: player)
                    scene.shake(duration: 0.3, intensity: 4, for: player)
                case .levelUp:
                    sound.play(.shimmer)
                    music.append(event)
                    haptic(.levelUp, for: player)
                case .gameOver:
                    break // knocked out or not, the match says
                }
            case .eliminated(let player):
                sound.play(.gameOver)
                haptic(.gameOver, for: player)
            case .matchOver(let winners):
                music.append(.gameOver(won: true)) // the music resolves home for the winner
                for player in winners { haptic(.levelUp, for: player) }
                recordMatch()
                phoneScreensChanged()
            }
        }
        guard let match = versus, let clock = match.boards[match.activePlayers.first ?? match.players[0]] else { return }
        let danger = match.activePlayers.compactMap { match.boards[$0].map { Self.fill($0.board) } }.max() ?? 0
        conduct(music, fallProgress: clock.fallProgress, danger: danger, sprintTimeRemaining: clock.sprintTimeRemaining)
    }

    /// Co-op's events. Turns rumble the player who turned (`player`); everything
    /// else happens to the shared bin, so both players feel it.
    func handleCoop(_ events: [GameEvent], from player: PlayerID?) {
        let everyone = coop?.seatedPlayers ?? []
        for event in events {
            switch event {
            case .rotate:
                sound.play(.rotate)
                if let player { haptic(.rotate, for: player) }
            case .spawn:
                break // the conductor plays the new triangle's note
            case .clear(let hexes, _):
                sound.play(.shimmer) // the conductor plays the arpeggio, on the beat
                for player in everyone { haptic(.clear(hexes: hexes.count), for: player) }
                scene.showClear(hexes)
            case .power:
                for player in everyone { haptic(.power, for: player) }
                scene.shake(duration: 0.3, intensity: 4)
            case .levelUp:
                sound.play(.shimmer)
                for player in everyone { haptic(.levelUp, for: player) }
            case .gameOver(let won):
                if !won { sound.play(.gameOver) } // a win resolves home in the music instead
                for player in everyone { haptic(won ? .levelUp : .gameOver, for: player) }
                // An online guest banks from the snapshot that ends the game instead
                // (`guestReceived`): the host sends this event first, so `coop` is
                // still the snapshot before the last clears
                if !isOnlineGuest { recordMatch() }
                phoneScreensChanged()
            }
        }
        guard let game = coop else { return }
        conduct(events, fallProgress: game.fallProgress, danger: Self.fill(game.board),
                sprintTimeRemaining: game.sprintTimeRemaining)
    }

    /// Bank the match toward skin unlocks: the best board's hexes (the shared
    /// one in co-op), and a MAIN win if a winner had one.
    func recordMatch() {
        if let game = coop {
            bankProgress(hexes: game.hexesCleared, mainWin: game.won)
            return
        }
        guard let match = versus else { return }
        let best = match.boards.values.map(\.hexesCleared).max() ?? 0
        let mainWin = (match.winners ?? []).contains { match.boards[$0]?.won == true }
        bankProgress(hexes: best, mainWin: mainWin)
    }

    func refreshVersusHUD() {
        guard let lobby else { return }
        var next = VersusHUD(kind: lobby.kind)
        if let game = coop {
            next.phase = game.phase
            next.won = game.won
            next.sprintSeconds = game.sprintTimeRemaining.map { Int($0.rounded(.up)) }
            next.boards = lobby.roster.players.map { player in
                VersusHUD.Board(player: player, name: lobby.name(of: player),
                                score: game.score, hexes: game.hexesCleared,
                                out: !game.seatedPlayers.contains(player),
                                dropped: lobby.roster.seats[player] == .dropped)
            }
            next.unlocked = game.phase == .gameOver ? unlockedNow : []
            if lobby.online != nil, let mine = game.cursor(for: onlinePlayer) {
                next.dial = .at(mine.vertex, on: game.board)
            }
        } else if let match = versus {
            next.phase = match.phase
            next.kind = .versus(match.rule)
            next.winners = match.winners
            next.sprintSeconds = match.boards[match.players[0]]?.sprintTimeRemaining.map { Int($0.rounded(.up)) }
            next.boards = match.players.map { player in
                let game = match.boards[player]
                return VersusHUD.Board(player: player, name: lobby.name(of: player),
                                       score: game?.score ?? 0, hexes: game?.hexesCleared ?? 0,
                                       out: match.eliminated.contains(player),
                                       dropped: lobby.roster.seats[player] == .dropped)
            }
            next.unlocked = match.phase == .gameOver ? unlockedNow : []
        }
        if next != versusHUD { versusHUD = next }
    }

    // MARK: - Players' devices

    /// A player's colour: the skin's piece colour in their slot.
    func playerColor(_ player: PlayerID) -> RGB {
        skin.piece(player.slot)
    }

    /// Number a device's player LEDs and tint its light in the player's colour (nil hands both back).
    private func light(_ source: InputSource, as player: PlayerID?) {
        controls.setPlayerIndex(player?.slot, for: source)
        controls.setLightColor(player.map { playerColor($0).value }, for: source)
    }

    /// Players move up when someone leaves the lobby: renumber every device.
    private func relightPlayers() {
        guard let lobby else { return }
        var haptics: [PlayerID: Haptics] = [:]
        for player in lobby.roster.players {
            guard let source = lobby.source(of: player) else { continue }
            light(source, as: player)
            haptics[player] = self.haptics(for: source)
        }
        playerHaptics = haptics
        refreshVersusHUD()
    }

    private func haptics(for source: InputSource) -> Haptics {
        let haptics = Haptics()
        haptics.setController(controls.controller(for: source))
        return haptics
    }

    /// Rumble a player's controller, or buzz their phone.
    private func haptic(_ event: HapticEvent, for player: PlayerID) {
        // An online partner feels their own game's haptics on their own device
        if lobby?.source(of: player) == .online { return }
        if case .phone(let peer) = lobby?.source(of: player) {
            phoneHaptic?(peer, event)
        } else {
            playerHaptics[player]?.play(event)
        }
    }

    private func deviceName(_ source: InputSource) -> String {
        switch source {
        case .controller: return controls.controller(for: source)?.vendorName?.lowercased() ?? "controller"
        case .keyboard: return "keyboard"
        case .remote: return "remote"
        case .phone: return "phone"
        case .online: return "online"
        }
    }
}
