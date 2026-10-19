// PhoneHost.swift — Apple TV side of phone controllers: a Bonjour listener for phones
//
// While the versus lobby (or a match) is open, the TV advertises
// `ControllerProtocol.serviceType` and accepts phones that know the join code.
// Each phone is an input source like any gamepad: its presses go through
// ControllerInput (which also runs the auto-repeat), and the TV sends back only
// its screen state and haptics. The TV is the only authority.

import DialhexCore
import Foundation
import Network

#if os(tvOS)
@available(tvOS 26.0, *)
@MainActor
final class PhoneHost {
    typealias Connection = NetworkConnection<Coder<TVMessage, PhoneMessage, NetworkJSONCoder>>

    let joinCode: String
    /// Decides whether a phone that said hello gets a player.
    var admit: ((Hello) -> Result<PlayerID, Rejection>)?
    /// Every later message from an admitted phone.
    var onMessage: ((String, PhoneMessage) -> Void)?
    /// An admitted phone left or went quiet.
    var onLost: ((String) -> Void)?

    private var task: Task<Void, Never>?
    private var connections: [String: Connection] = [:]

    init(joinCode: String) {
        self.joinCode = joinCode
    }

    func start() {
        guard task == nil else { return }
        task = Task { @MainActor [weak self] in
            do {
                // Advertised under the TV's own name, which is what people see on their phones
                let listener = try NetworkListener(for: .bonjour(type: ControllerProtocol.serviceType)) {
                    Coder(sending: TVMessage.self, receiving: PhoneMessage.self, using: .json) {
                        TCP().noDelay(true)
                    }
                }
                try await listener.run { @MainActor connection in
                    await self?.serve(connection)
                }
            } catch {
                // The listener failed or was cancelled; phones just can't join until the lobby reopens
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
        for peer in connections.keys { onLost?(peer) }
        connections = [:]
    }

    func send(_ message: TVMessage, to peer: String) {
        guard let connection = connections[peer] else { return }
        Task { try? await connection.send(message) }
    }

    /// What each phone was last sent, so each is only sent again when it changes.
    private var sentDials: [String: DialPieces] = [:]
    private var sentScreens: [String: RemoteScreen] = [:]
    private var sentSeats: [String: PlayerID] = [:]

    /// Send a phone what's under its player's dial, if that's news.
    func send(_ dial: DialPieces, to peer: String) {
        guard connections[peer] != nil, sentDials[peer] != dial else { return }
        sentDials[peer] = dial
        send(.dial(dial), to: peer)
    }

    /// Send a phone what its screen should show, if that's news.
    func send(_ screen: RemoteScreen, to peer: String) {
        guard connections[peer] != nil, sentScreens[peer] != screen else { return }
        sentScreens[peer] = screen
        send(.screen(screen), to: peer)
    }

    /// Tell a phone which player it is (again, if joining the lobby moved it).
    func send(seat player: PlayerID, to peer: String) {
        guard connections[peer] != nil, sentSeats[peer] != player else { return }
        sentSeats[peer] = player
        send(.welcome(player), to: peer)
    }

    var peers: [String] { Array(connections.keys) }

    /// One phone, from hello to goodbye.
    private func serve(_ connection: Connection) async {
        var peer: String?
        defer {
            if let peer, connections[peer] === connection {
                connections[peer] = nil
                onLost?(peer)
            }
        }
        do {
            // The first message must be a hello that knows the code
            guard case .hello(let hello) = try await connection.receive().content else { return }
            if let rejection = ControllerProtocol.admit(hello, joinCode: joinCode) {
                try await connection.send(.rejected(rejection))
                return
            }
            switch admit?(hello) ?? .failure(.full) {
            case .failure(let rejection):
                try await connection.send(.rejected(rejection))
                return
            case .success(let player):
                // A phone that reconnects replaces its old connection (whose ending then goes unreported)
                connections[hello.peer] = connection
                peer = hello.peer
                // A new connection needs everything again
                sentDials[hello.peer] = nil
                sentScreens[hello.peer] = nil
                sentSeats[hello.peer] = player
                try await connection.send(.welcome(player))
            }
            try await receive(from: connection, peer: hello.peer)
        } catch {
            // Dropped, timed out, or the listener stopped
        }
    }

    /// Pass messages on until the phone says bye, the connection ends, or it goes quiet.
    private func receive(from connection: Connection, peer: String) async throws {
        let lastHeard = LastHeard()
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask { @MainActor in
                while true {
                    let message = try await connection.receive().content
                    lastHeard.time = .now
                    switch message {
                    case .bye: return
                    case .ping(let stamp): try await connection.send(.pong(stamp))
                    case .hello: break
                    default: self.onMessage?(peer, message)
                    }
                }
            }
            group.addTask { @MainActor in
                while true {
                    try await Task.sleep(for: ControllerProtocol.heartbeatInterval)
                    if ContinuousClock.now - lastHeard.time > ControllerProtocol.timeout { throw CancellationError() }
                }
            }
            // Whichever ends first (bye, error, or silence) ends the phone
            _ = try await group.next()
            group.cancelAll()
        }
    }
}
#endif

/// When the other end was last heard from; shared by a connection's receive loop and its watchdog.
@MainActor
final class LastHeard {
    var time = ContinuousClock.now
}

extension AppModel {
    /// Start advertising for phone controllers, with a fresh join code (Apple TV, tvOS 26).
    func startTakingPhones() {
        #if os(tvOS)
        guard #available(tvOS 26.0, *), phoneHost == nil else { return }
        var rng = SystemRandomNumberGenerator()
        let host = PhoneHost(joinCode: ControllerProtocol.makeJoinCode(using: &rng))
        host.admit = { [weak self] hello in self?.admitPhone(hello) ?? .failure(.full) }
        host.onMessage = { [weak self] peer, message in self?.phoneMessage(message, from: peer) }
        host.onLost = { [weak self] peer in self?.controls.phoneLost(peer) }
        phoneHaptic = { [weak host] peer, event in
            // The phone ticks for its own turns as they're pressed, so only the rest come from here
            if case .rotate = event { return }
            host?.send(.haptic(RemoteHaptic(event)), to: peer)
        }
        host.start()
        phoneHost = host
        joinCode = host.joinCode
        #endif
    }

    func stopTakingPhones() {
        #if os(tvOS)
        guard #available(tvOS 26.0, *), let host = phoneHost as? PhoneHost else { return }
        host.stop()
        phoneHost = nil
        phoneHaptic = nil
        joinCode = nil
        #endif
    }

    /// Bring every phone up to date: which player it is, what its screen shows, and
    /// its dial. Each only goes out when it changes, so this runs every frame.
    func syncPhones() {
        #if os(tvOS)
        guard #available(tvOS 26.0, *), let host = phoneHost as? PhoneHost else { return }
        for peer in host.peers {
            let player = lobby?.roster.player(for: .phone(peer))
            // Outside the lobby a phone plays the solo game, as P1
            host.send(seat: player ?? PlayerID(0), to: peer)
            host.send(remoteScreen(for: player), to: peer)
            host.send(dialPieces(for: player), to: peer)
        }
        #endif
    }

    /// Something a phone shows just changed; the next frame's `syncPhones` would catch it too.
    func phoneScreensChanged() {
        syncPhones()
    }

    /// A haptic for every phone that isn't seated in a match: they're all playing the solo game.
    func soloPhoneHaptic(_ event: HapticEvent) {
        #if os(tvOS)
        guard #available(tvOS 26.0, *), let host = phoneHost as? PhoneHost, let phoneHaptic else { return }
        for peer in host.peers where lobby?.roster.player(for: .phone(peer)) == nil {
            phoneHaptic(peer, event)
        }
        #endif
    }

    private func dialPieces(for player: PlayerID?) -> DialPieces {
        if let player {
            if let game = versus?.boards[player] { return .at(game.cursor.vertex, on: game.board) }
            if let coop, let cursor = coop.cursor(for: player) { return .at(cursor.vertex, on: coop.board) }
            return .empty
        }
        if screen == .playing, let game { return .at(game.cursor.vertex, on: game.board) }
        return .empty
    }

    private func remoteScreen(for player: PlayerID?) -> RemoteScreen {
        switch screen {
        case .menu: return .menu
        case .lobby: return .lobby
        case .playing:
            switch game?.phase {
            case .paused: return .paused
            case .gameOver: return .over(won: game?.won == true)
            default: return .playing
            }
        case .versus:
            // A phone that isn't in the match just watches
            guard let player, let phase = matchPhase else { return .lobby }
            switch phase {
            case .playing: return .playing
            case .paused: return .paused
            case .gameOver:
                // In co-op the team wins or loses together
                let won = coop.map(\.won) ?? (versus?.winners?.contains(player) == true)
                return .over(won: won)
            }
        }
    }

    /// A phone said hello with the right code: in the lobby, seat it if there's
    /// room; anywhere else it's in, steering the menu and the solo game.
    private func admitPhone(_ hello: Hello) -> Result<PlayerID, Rejection> {
        let source = InputSource.phone(hello.peer)
        guard lobby != nil else { return .success(PlayerID(0)) }
        if let seated = lobby?.roster.player(for: source) { return .success(seated) }
        let locked = lobby?.roster.isLocked == true
        guard let player = join(source, name: hello.name) else { return .failure(locked ? .matchRunning : .full) }
        return .success(player)
    }

    private func phoneMessage(_ message: PhoneMessage, from peer: String) {
        switch message {
        case .direction(let direction, let pressed): controls.phone(peer, direction: direction, pressed: pressed)
        case .place(let vertex): controls.phone(peer, .place(vertex))
        case .rotate(let direction): controls.phone(peer, .rotate(direction))
        case .confirm: controls.phone(peer, .confirm)
        case .cancel: controls.phone(peer, .cancel)
        case .pause: controls.phone(peer, .pause)
        case .hello, .ping, .bye: break
        }
    }
}

extension RemoteHaptic {
    init(_ event: HapticEvent) {
        switch event {
        case .rotate: self = .rotate
        case .clear(let hexes): self = .clear(hexes: hexes)
        case .power: self = .power
        case .levelUp: self = .levelUp
        case .gameOver: self = .gameOver
        }
    }
}

extension HapticEvent {
    init(_ haptic: RemoteHaptic) {
        switch haptic {
        case .rotate: self = .rotate
        case .clear(let hexes): self = .clear(hexes: hexes)
        case .power: self = .power
        case .levelUp: self = .levelUp
        case .gameOver: self = .gameOver
        }
    }
}
