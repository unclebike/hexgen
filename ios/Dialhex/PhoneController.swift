// PhoneController.swift — iPhone side of phone controllers: find an Apple TV and play on it
//
// Browses Bonjour for TVs running the versus lobby, connects with the code the
// TV shows, then sends presses and receives only its own screen state and
// haptics. Messages go out in order through one stream; a heartbeat both ways
// notices a TV that's gone away.

#if os(iOS)
import DialhexCore
import Foundation
import Network
import Observation
import UIKit

@available(iOS 26.0, *)
@Observable @MainActor
final class PhoneController {
    enum Status: Equatable {
        case searching
        case connecting
        case joined(PlayerID)
        case rejected(Rejection)
        case lost
    }

    /// TVs taking phones right now.
    private(set) var tvs: [Bonjour.Endpoint] = []
    private(set) var status = Status.searching
    /// What the TV says this phone's screen should show.
    private(set) var screen = RemoteScreen.lobby
    /// The pieces under this player's dial on the TV, for the spinner to show.
    private(set) var dial = DialPieces.empty

    /// Random per launch: lets the TV tell a reconnecting phone from a new one, without tracking anyone.
    @ObservationIgnored private let peer = UUID().uuidString
    @ObservationIgnored private var browsing: Task<Void, Never>?
    @ObservationIgnored private var session: Task<Void, Never>?
    @ObservationIgnored private var outgoing: AsyncStream<PhoneMessage>.Continuation?
    @ObservationIgnored private var leaving = false
    /// The vertex last sent from the mini bin.
    @ObservationIgnored private var placed: Vertex?
    @ObservationIgnored private let haptics = Haptics()

    func startBrowsing() {
        guard browsing == nil else { return }
        browsing = Task { @MainActor [weak self] in
            let browser = NetworkBrowser(for: .bonjour(ControllerProtocol.serviceType))
            try? await browser.run { @MainActor endpoints in
                self?.tvs = endpoints
            }
        }
    }

    /// Stop browsing and leave any TV.
    func stop() {
        leave()
        browsing?.cancel()
        browsing = nil
    }

    func connect(to tv: Bonjour.Endpoint, code: String) {
        leave()
        leaving = false
        status = .connecting
        screen = .lobby
        dial = .empty
        let (messages, outgoing) = AsyncStream.makeStream(of: PhoneMessage.self)
        self.outgoing = outgoing
        let hello = Hello(peer: peer, name: UIDevice.current.name, joinCode: code)
        session = Task { @MainActor [weak self] in
            do {
                try await withNetworkConnection(to: tv.nwEndpoint, using: {
                    Coder(sending: PhoneMessage.self, receiving: TVMessage.self, using: .json) {
                        TCP().noDelay(true)
                    }
                }) { connection in
                    try await connection.send(.hello(hello))
                    let lastHeard = LastHeard()
                    try await withThrowingTaskGroup(of: Void.self) { group in
                        // Everything the player presses, in order; ends with a bye when leaving
                        group.addTask {
                            for await message in messages { try await connection.send(message) }
                        }
                        group.addTask { @MainActor in
                            while true {
                                let message = try await connection.receive().content
                                lastHeard.time = .now
                                guard self?.received(message) == true else { return }
                            }
                        }
                        group.addTask { @MainActor in
                            var stamp: UInt64 = 0
                            while true {
                                try await Task.sleep(for: ControllerProtocol.heartbeatInterval)
                                stamp += 1
                                outgoing.yield(.ping(stamp))
                                if ContinuousClock.now - lastHeard.time > ControllerProtocol.timeout { throw CancellationError() }
                            }
                        }
                        _ = try await group.next()
                        group.cancelAll()
                    }
                }
            } catch {
                // Couldn't connect, dropped, or went quiet
            }
            self?.ended()
        }
    }

    /// Say goodbye to the TV and stop.
    func leave() {
        guard session != nil else { return }
        leaving = true
        outgoing?.yield(.bye)
        outgoing?.finish()
        outgoing = nil
        session = nil
        status = .searching
        UIApplication.shared.isIdleTimerDisabled = false
    }

    // MARK: - Presses

    func direction(_ direction: Direction, pressed: Bool) {
        send(.direction(direction, pressed: pressed))
    }

    /// A direction pressed and let go at once (the lobby's rule arrows).
    func nudge(_ direction: Direction) {
        send(.direction(direction, pressed: true))
        send(.direction(direction, pressed: false))
    }

    /// Put the dial on a vertex, from the mini bin. Only sent when it changes.
    func place(_ vertex: Vertex) {
        guard vertex != placed else { return }
        placed = vertex
        send(.place(vertex))
    }

    func rotate(_ direction: RotationDirection) {
        // Tick and turn the spinner now rather than wait for the round trip; the
        // TV's next dial message settles it (it won't turn while pieces clear)
        haptics.play(.rotate)
        dial = dial.turned(direction)
        send(.rotate(direction))
    }

    func send(_ message: PhoneMessage) {
        outgoing?.yield(message)
    }

    // MARK: - From the TV

    /// Handle one message; false once the TV has turned this phone away.
    private func received(_ message: TVMessage) -> Bool {
        switch message {
        case .welcome(let player):
            status = .joined(player)
            UIApplication.shared.isIdleTimerDisabled = true
        case .rejected(let rejection):
            status = .rejected(rejection)
            return false
        case .screen(let screen):
            self.screen = screen
        case .haptic(let haptic):
            haptics.play(HapticEvent(haptic))
        case .dial(let dial):
            self.dial = dial
            // The TV has the last word: if it kept the dial elsewhere, the next drag can try again
            placed = dial.vertex
        case .pong:
            break
        }
        return true
    }

    private func ended() {
        UIApplication.shared.isIdleTimerDisabled = false
        outgoing = nil
        session = nil
        if leaving { return }
        if case .rejected = status { return }
        status = .lost
    }
}
#endif
