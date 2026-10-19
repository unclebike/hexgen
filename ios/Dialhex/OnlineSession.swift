// OnlineSession.swift — Online co-op with a Game Center friend, over GameKit
//
// Matches are invite-only: no automatch, so players only ever meet people
// they chose. Nothing is ever said between players beyond the game itself:
// no chat, and no text a player wrote. Players are shown only by their Game
// Center display name. A player whose account isn't allowed multiplayer
// never sees the feature.
//
// Once both devices are connected they swap hellos to settle who hosts (see
// `OnlineCoop.isHost`). The host's `AppModel` runs the game and calls
// `hostTick` every frame. The guest's applies the snapshots. Everything from
// the other device goes through `OnlineMessage.decode`, which turns away
// anything malformed. A device that keeps sending bad messages is
// disconnected.

import DialhexCore
import Foundation
import GameKit
import UIKit

/// Whether online co-op can be offered, and if not, why not.
enum OnlineAvailability: Equatable {
    case available
    case signedOut
    /// Screen Time (or a child account) doesn't allow multiplayer games.
    case restricted
}

@MainActor
final class OnlineSession: NSObject {
    enum Role { case host, guest }

    /// How many bad messages the other device may send before it's cut off.
    private static let badMessageLimit = 20

    weak var model: AppModel?
    private(set) var role: Role?
    /// The other player's Game Center display name, once connected.
    private(set) var partnerName: String?
    private var match: GKMatch?
    private var hello: OnlineCoop.Hello?
    /// This device sent the invitation (rather than accepting one).
    private var invited = false
    private var listening = false
    private var badMessages = 0
    private var matchmaker: GKMatchmakerViewController?

    // The host's side of the link
    private(set) var link = CoopHostLink()
    private var lastSnapshot: CoopSnapshot?
    private var lastSentAt = -Double.infinity

    /// Seconds on a steady clock, for the snapshot cadence and the rate limit.
    var now: Double { ProcessInfo.processInfo.systemUptime }

    var isConnected: Bool { match != nil && role != nil }

    static var availability: OnlineAvailability {
        let player = GKLocalPlayer.local
        guard player.isAuthenticated else { return .signedOut }
        return player.isMultiplayerGamingRestricted ? .restricted : .available
    }

    override init() {
        super.init()
        // Listen for invitations once the player is signed in. Scores owns
        // sign-in, so this just follows along.
        NotificationCenter.default.addObserver(forName: .GKPlayerAuthenticationDidChangeNotificationName,
                                               object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.authenticationChanged() }
        }
    }

    private func authenticationChanged() {
        let player = GKLocalPlayer.local
        if player.isAuthenticated && !listening {
            player.register(self)
            listening = true
        } else if !player.isAuthenticated {
            if listening { player.unregisterListener(self) }
            listening = false
            end(notify: true)
        }
    }

    // MARK: - Finding a partner

    /// Show Game Center's invite sheet, so the player can pick a friend.
    func invite() {
        guard Self.availability == .available, match == nil, matchmaker == nil else { return }
        let request = GKMatchRequest()
        request.minPlayers = 2
        request.maxPlayers = 2
        request.playerGroup = OnlineCoop.playerGroup
        guard let viewController = GKMatchmakerViewController(matchRequest: request) else { return }
        // Friends only: never matched with strangers
        viewController.matchmakingMode = .inviteOnly
        invited = true
        present(viewController)
    }

    private func accept(_ invite: GKInvite) {
        guard Self.availability == .available, match == nil, matchmaker == nil else { return }
        // A build that speaks a different version can't play this one
        guard invite.playerGroup == OnlineCoop.playerGroup else {
            model?.onlineNotice(.versionMismatch)
            return
        }
        guard let viewController = GKMatchmakerViewController(invite: invite) else { return }
        invited = false
        model?.onlineInviteAccepted()
        present(viewController)
    }

    private func present(_ viewController: GKMatchmakerViewController) {
        viewController.matchmakerDelegate = self
        matchmaker = viewController
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive } ?? UIApplication.shared.connectedScenes.first as? UIWindowScene
        var top = scene?.keyWindow?.rootViewController
        while let presented = top?.presentedViewController { top = presented }
        top?.present(viewController, animated: true)
    }

    private func dismissMatchmaker() {
        matchmaker?.dismiss(animated: true)
        matchmaker = nil
    }

    private func begin(_ match: GKMatch) {
        end(notify: false)
        self.match = match
        match.delegate = self
        badMessages = 0
        link = CoopHostLink()
        lastSnapshot = nil
        lastSentAt = -.infinity
        sayHello()
    }

    private func sayHello() {
        let hello = OnlineCoop.Hello(nonce: .random(in: 0...UInt64.max), inviter: invited)
        self.hello = hello
        send(.hello(hello))
    }

    // MARK: - Sending

    func send(_ message: OnlineMessage, reliable: Bool = true) {
        guard let match else { return }
        try? match.sendData(toAllPlayers: message.encoded, with: reliable ? .reliable : .unreliable)
    }

    /// The host, once a frame: the game's events now, and a snapshot every
    /// `snapshotInterval`. While nothing changes (paused or over), only a
    /// heartbeat once a second.
    func hostTick(_ game: CoopGame, events: [GameEvent], by player: PlayerID?) {
        guard role == .host else { return }
        if !events.isEmpty { send(.events(by: player, events)) }
        let time = now
        guard time - lastSentAt >= OnlineCoop.snapshotInterval else { return }
        let snapshot = game.snapshot
        guard snapshot != lastSnapshot || time - lastSentAt >= 1 else { return }
        let data = OnlineMessage.state(seq: link.nextStateSeq(), ack: link.ack, snapshot).encoded
        guard data.count <= OnlineCoop.maxHostMessageBytes else { return }
        // A change of phase must arrive; the rest can be replaced by the next one
        let phaseChanged = snapshot.phase != lastSnapshot?.phase
        try? match?.sendData(toAllPlayers: data, with: phaseChanged || data.count > OnlineCoop.unreliableLimit ? .reliable : .unreliable)
        lastSnapshot = snapshot
        lastSentAt = time
    }

    /// The host is starting a new game: send it straight away.
    func hostRestarted() {
        lastSnapshot = nil
        lastSentAt = -.infinity
    }

    /// Whether the host should apply a guest input now (new, and within the rate limit).
    func acceptInput(seq: UInt32) -> Bool {
        link.accept(seq: seq, at: now)
    }

    /// Whether the host should act on a guest's pause or rematch, within the rate limit.
    func allowRequest() -> Bool {
        link.allow(at: now)
    }

    // MARK: - Leaving

    /// Leave the match on purpose, telling the other player.
    func leave() {
        send(.bye)
        // Give the goodbye a moment to go out before hanging up
        let match = match
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { match?.disconnect() }
        self.match = nil
        end(notify: false)
    }

    /// Drop the match. With `notify`, the model hears the partner has gone.
    private func end(notify: Bool) {
        let wasConnected = match != nil
        match?.delegate = nil
        match?.disconnect()
        match = nil
        role = nil
        hello = nil
        partnerName = nil
        if notify && wasConnected { model?.onlinePartnerLeft() }
    }

    // MARK: - Receiving

    private func received(_ data: Data, from player: GKPlayer, in match: GKMatch) {
        guard match === self.match, match.players.contains(player) else { return }
        let sender: OnlineMessage.Sender = switch role {
        case nil: .undecided
        case .host: .guest
        case .guest: .host
        }
        guard let message = OnlineMessage.decode(data, from: sender) else {
            badMessages += 1
            if badMessages > Self.badMessageLimit { end(notify: true) }
            return
        }
        switch message {
        case .hello(let theirs):
            guard role == nil else { return }
            if hello == nil { sayHello() }
            guard let mine = hello else { return }
            guard let hosts = OnlineCoop.isHost(local: mine, remote: theirs) else {
                sayHello() // a tie: both try again
                return
            }
            role = hosts ? .host : .guest
            partnerName = player.displayName
            model?.onlineConnected(as: hosts ? .host : .guest, partner: player.displayName)
        case .bye:
            end(notify: true)
        default:
            model?.onlineReceived(message)
        }
    }

    private func playerChanged(_ player: GKPlayer, to state: GKPlayerConnectionState, in match: GKMatch) {
        guard match === self.match else { return }
        switch state {
        case .connected where hello == nil:
            sayHello()
        case .disconnected:
            end(notify: true)
        default:
            break
        }
    }
}

// MARK: - GameKit callbacks

/// GameKit calls these on the main thread; each hops onto the main actor in arrival order.
private func onMain(_ body: @escaping @MainActor () -> Void) {
    DispatchQueue.main.async { MainActor.assumeIsolated(body) }
}

extension OnlineSession: GKMatchmakerViewControllerDelegate {
    nonisolated func matchmakerViewController(_ viewController: GKMatchmakerViewController, didFind match: GKMatch) {
        onMain {
            self.dismissMatchmaker()
            self.begin(match)
        }
    }

    nonisolated func matchmakerViewControllerWasCancelled(_ viewController: GKMatchmakerViewController) {
        onMain {
            self.dismissMatchmaker()
            self.model?.onlineInviteCancelled()
        }
    }

    nonisolated func matchmakerViewController(_ viewController: GKMatchmakerViewController, didFailWithError error: any Error) {
        onMain {
            self.dismissMatchmaker()
            self.model?.onlineInviteCancelled()
        }
    }
}

extension OnlineSession: GKMatchDelegate {
    nonisolated func match(_ match: GKMatch, didReceive data: Data, fromRemotePlayer player: GKPlayer) {
        onMain { self.received(data, from: player, in: match) }
    }

    nonisolated func match(_ match: GKMatch, player: GKPlayer, didChange state: GKPlayerConnectionState) {
        onMain { self.playerChanged(player, to: state, in: match) }
    }

    nonisolated func match(_ match: GKMatch, didFailWithError error: (any Error)?) {
        onMain {
            guard match === self.match else { return }
            self.end(notify: true)
        }
    }
}

extension OnlineSession: GKLocalPlayerListener {
    nonisolated func player(_ player: GKPlayer, didAccept invite: GKInvite) {
        onMain { self.accept(invite) }
    }
}
