// AppModel+Online.swift — Online co-op with a Game Center friend
//
// It runs on the same lobby and co-op screens as local co-op. The host's lobby
// seats the friend as P2 (`InputSource.online`), and the host runs the game
// exactly as in local co-op, sending it on as it goes (`OnlineSession.hostTick`).
// The guest's lobby seats the host as P1. Its game is a `CoopReplica` redrawn
// from the host's snapshots. Its own inputs show at once and go to the host,
// which has the final say.
//
// Co-op results never reach the leaderboards (they're for solo games), but
// both players bank the hexes toward skin unlocks, as in local co-op.

import DialhexCore
import Foundation
import GameKit

/// Where an online lobby stands.
enum OnlineLink: Equatable {
    /// This device will host, and is yet to invite a friend.
    case inviting
    /// This device hosts, with the friend named.
    case hosting(String)
    /// This device is the guest of the host named.
    case joining(String)
}

/// Why online co-op ended or couldn't start, for the menu to say.
enum OnlineNotice {
    case partnerLeft(String)
    case hostLeft(String)
    case versionMismatch
}

extension AppModel {
    /// Whether the menu can offer online co-op. Reads `scores.isAuthenticated`
    /// so the menu updates when the player signs in or out.
    var onlineAvailability: OnlineAvailability {
        _ = scores.isAuthenticated
        return OnlineSession.availability
    }

    /// This device is an online guest: the host runs the game.
    var isOnlineGuest: Bool {
        if case .joining = lobby?.online { return true }
        return false
    }

    /// The local player in online co-op.
    var onlinePlayer: PlayerID { isOnlineGuest ? OnlineCoop.guestPlayer : OnlineCoop.hostPlayer }

    // MARK: - Lobby

    /// From the menu: an online lobby, ready to invite a friend.
    func openOnline(from source: InputSource) {
        guard onlineAvailability == .available else { return }
        onlineNoticeText = nil
        var lobby = Lobby()
        lobby.kind = .coop(.endless)
        lobby.online = .inviting
        self.lobby = lobby
        screen = .lobby
        scores.setOnMenu(false)
        join(source, name: Brand.copy.online.you)
    }

    /// The local player's input in an online lobby or game, from any of this device's controls.
    func handleOnline(_ action: ControlAction) {
        guard let link = lobby?.online else { return }
        switch screen {
        case .lobby:
            switch action {
            case .confirm, .pause:
                switch link {
                case .inviting: online.invite()
                case .hosting: startMatch()
                case .joining: break // the host starts
                }
            case .cancel:
                leaveOnline()
            case .move(let direction) where !isOnlineGuest && (direction == .left || direction == .right):
                cycleOnlineMode(by: direction == .right ? 1 : -1)
            default:
                break
            }
        case .versus:
            guard let phase = matchPhase else { return }
            switch (phase, action) {
            case (.playing, .move(let direction)): onlineInput(.move(direction))
            case (.playing, .place(let vertex)): onlineInput(.place(vertex))
            case (.playing, .rotate(let direction)): onlineInput(.rotate(direction))
            case (.playing, .confirm): onlineInput(.rotate(.clockwise))
            case (.playing, .pause), (.playing, .cancel), (.paused, .confirm), (.paused, .pause):
                toggleMatchPause()
            case (.paused, .cancel), (.gameOver, .cancel):
                leaveOnline()
            case (.gameOver, .confirm):
                if isOnlineGuest { online.send(.rematch) } else { startMatch() }
            default:
                break
            }
            refreshVersusHUD()
        default:
            break
        }
    }

    /// The host steps through the co-op modes.
    private func cycleOnlineMode(by step: Int) {
        guard var lobby, case .coop(let mode) = lobby.kind else { return }
        let modes = Mode.allCases
        let i = modes.firstIndex(of: mode) ?? 0
        lobby.kind = .coop(modes[(i + step + modes.count) % modes.count])
        self.lobby = lobby
        refreshVersusHUD()
    }

    /// Leave online co-op on purpose, telling the other player, and go back to the menu.
    func leaveOnline() {
        online.leave()
        endOnline(notice: nil)
    }

    /// Back to the menu from anywhere online, with a line saying why if there is one.
    private func endOnline(notice: OnlineNotice?) {
        versus = nil
        coop = nil
        replica = nil
        conductor = nil
        scene.showVersus(nil)
        scene.showCoop(nil)
        startDemo()
        scene.setLayout(.menu, animated: false)
        closeLobby()
        scores.setOnMenu(true)
        onlineNotice(notice)
    }

    /// Put a line on the menu about online co-op (nil clears it).
    func onlineNotice(_ notice: OnlineNotice?) {
        let copy = Brand.copy.online
        onlineNoticeText = notice.map { notice in
            switch notice {
            case .partnerLeft(let name): copy.left.replacingOccurrences(of: "%@", with: name)
            case .hostLeft(let name): copy.hostLeft.replacingOccurrences(of: "%@", with: name)
            case .versionMismatch: copy.versionMismatch
            }
        }
    }

    // MARK: - From the session

    /// The player accepted an invitation: put down whatever they were playing.
    func onlineInviteAccepted() {
        onlineNoticeText = nil
        switch screen {
        case .playing:
            toMenu()
        case .lobby, .versus:
            if lobby?.online != nil {
                leaveOnline()
            } else {
                versus = nil
                coop = nil
                conductor = nil
                scene.showVersus(nil)
                scene.showCoop(nil)
                startDemo()
                scene.setLayout(.menu, animated: false)
                closeLobby()
            }
        case .menu:
            hideHowTo()
        }
    }

    /// The invite sheet closed without a match. A host-to-be stays in their lobby.
    func onlineInviteCancelled() {}

    /// Both devices are connected and know who hosts.
    func onlineConnected(as role: OnlineSession.Role, partner: String) {
        onlineNoticeText = nil
        switch role {
        case .host:
            // The player who accepted can end up hosting too; give them a lobby
            if lobby?.online == nil {
                if screen == .playing { toMenu() }
                openOnline(from: .keyboard)
            }
            lobby?.online = .hosting(partner)
            join(.online, name: partner)
        case .guest:
            // The host is P1 and this device is P2, whatever lobby was open before
            var lobby = Lobby()
            lobby.kind = .coop(.endless)
            lobby.online = .joining(partner)
            self.lobby = lobby
            screen = .lobby
            scores.setOnMenu(false)
            join(.online, name: partner)
            join(.keyboard, name: Brand.copy.online.you)
        }
        refreshVersusHUD()
    }

    /// The other player left or the connection dropped.
    func onlinePartnerLeft() {
        guard var lobby, let link = lobby.online else { return }
        if case .joining(let host) = link {
            endOnline(notice: .hostLeft(host))
            return
        }
        // The host plays on alone; their friend's dial lifts off the board
        let name = lobby.name(of: OnlineCoop.guestPlayer) ?? ""
        lobby.roster.leave(.online)
        lobby.roster.forfeit(OnlineCoop.guestPlayer)
        lobby.names[.online] = nil
        lobby.online = .inviting
        self.lobby = lobby
        coop?.leave(OnlineCoop.guestPlayer)
        onlineNotice(.partnerLeft(name))
        refreshVersusHUD()
    }

    /// A message from the other device, already checked by `OnlineMessage.decode`.
    func onlineReceived(_ message: OnlineMessage) {
        if isOnlineGuest {
            guestReceived(message)
        } else if case .hosting = lobby?.online {
            hostReceived(message)
        }
    }

    private func hostReceived(_ message: OnlineMessage) {
        switch message {
        case .input(let seq, let input):
            // Always counted, so the guest's prediction lets go of it; only applied in play
            guard online.acceptInput(seq: seq), screen == .versus, coop?.phase == .playing else { return }
            matchInput(input, from: OnlineCoop.guestPlayer)
        case .pause(let paused):
            guard online.allowRequest(), screen == .versus, let phase = coop?.phase else { return }
            if (paused && phase == .playing) || (!paused && phase == .paused) {
                toggleMatchPause()
                refreshVersusHUD()
            }
        case .rematch:
            guard online.allowRequest(), screen == .versus, coop?.phase == .gameOver else { return }
            startMatch()
        default:
            break
        }
    }

    private func guestReceived(_ message: OnlineMessage) {
        switch message {
        case .state(let seq, let ack, let snapshot):
            // A new game: the first one, or a rematch after the last ended
            if var replica, !(replica.game.phase == .gameOver && snapshot.phase == .playing) {
                let wasOver = replica.game.phase == .gameOver
                replica.receive(seq: seq, ack: ack, snapshot: snapshot)
                self.replica = replica
                coop = replica.game
                // Bank the game once, from the host's final board and result
                if !wasOver && replica.game.phase == .gameOver {
                    recordMatch()
                    phoneScreensChanged()
                }
            } else if seq > (replica?.stateSeq ?? 0) {
                beginGuestGame(CoopReplica(seq: seq, ack: ack, snapshot: snapshot))
            }
        case .events(let player, let events):
            guard replica != nil else { return }
            // The guest heard its own turns as it made them
            let fresh = player == onlinePlayer ? events.filter { $0 != .rotate } : events
            handleCoop(fresh, from: player)
        default:
            break
        }
    }

    /// The guest's side of `startMatch`: the shared board, and music on the host's clock.
    private func beginGuestGame(_ replica: CoopReplica) {
        guard var lobby else { return }
        let game = replica.game
        if !lobby.roster.isLocked { lobby.roster.lock() }
        lobby.kind = .coop(game.mode)
        self.lobby = lobby
        self.replica = replica
        coop = game
        versus = nil
        scene.reset()
        scene.showVersus(nil)
        scene.showCoop(Dictionary(uniqueKeysWithValues: CoopGame.players.map { ($0, playerColor($0)) }),
                       spinner: true)
        unlockedNow = []
        screen = .versus
        sound.start()
        conductor = Conductor(score: .forSkin(skin.id), stepTime: Game.fallStep * game.speed.pace,
                              colors: Progression.initialColors)
        sound.lofi = conductor?.score.groove != nil
        refreshVersusHUD()
    }

    /// The guest's frame: the copy animates on, and the music follows it.
    func tickOnlineGuest(_ dt: Double) {
        guard var replica else { return }
        replica.animate(by: dt)
        self.replica = replica
        coop = replica.game
        handleCoop([], from: nil)
    }

    // MARK: - The local player's moves

    /// The local player's move or turn: applied now on the host, or predicted and sent on a guest.
    func onlineInput(_ input: PlayerInput) {
        guard isOnlineGuest else {
            matchInput(input, from: onlinePlayer)
            return
        }
        guard var replica, replica.game.phase == .playing else { return }
        let (seq, events) = replica.predict(input)
        self.replica = replica
        coop = replica.game
        online.send(.input(seq: seq, input))
        handleCoop(events, from: onlinePlayer)
    }

    /// A tap on the shared board: on your own dial turns it, elsewhere moves it there.
    /// Tapping while paused resumes, as in a solo game.
    func onlineTap(at point: LatticePoint) {
        guard let coop else { return }
        if coop.phase == .paused {
            toggleMatchPause()
            refreshVersusHUD()
            return
        }
        guard coop.phase == .playing, let dial = Grid.nearestDial(to: point, within: 1.2),
              let mine = coop.cursor(for: onlinePlayer) else { return }
        onlineInput(dial == mine.vertex ? .rotate(.clockwise) : .place(dial))
    }

    /// A finger dragged across the shared board carries your dial with it.
    func onlineDrag(to point: LatticePoint) {
        guard let coop, coop.phase == .playing, let dial = Grid.nearestDial(to: point),
              dial != coop.cursor(for: onlinePlayer)?.vertex else { return }
        onlineInput(.place(dial))
    }

    /// A twist on the board, or the spinner: turns your dial.
    func onlineTouchInput(_ input: PlayerInput) {
        guard coop?.phase == .playing else { return }
        onlineInput(input)
    }
}
