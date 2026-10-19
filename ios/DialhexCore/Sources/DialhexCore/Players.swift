// Players.swift — Who's playing: player slots, per-player input, and the roster
// that ties input devices to players
//
// Shared by every multiplayer mode. The app maps its own input sources
// (gamepads, phones, the keyboard) onto players through a `Roster`, so the
// rules never see a device.

/// One of up to four players, numbered from zero (shown as P1–P4).
public struct PlayerID: Hashable, Comparable, Sendable, Codable, CustomStringConvertible {
    public static let maxPlayers = 4
    /// Every player slot, P1 first.
    public static let all = (0..<maxPlayers).map(PlayerID.init)

    public let slot: Int

    public init(_ slot: Int) {
        precondition((0..<Self.maxPlayers).contains(slot), "player slot \(slot) out of range")
        self.slot = slot
    }

    public static func < (a: PlayerID, b: PlayerID) -> Bool { a.slot < b.slot }

    public var description: String { "P\(slot + 1)" }
}

/// What a player can do to their dial during play.
public enum PlayerInput: Sendable, Equatable {
    case move(Direction)
    /// Put the dial straight on a vertex (a phone's mini bin); ignored where it can't go.
    case place(Vertex)
    case rotate(RotationDirection)
}

/// SplitMix64: a small seeded generator, so every board in a match can be
/// dealt the same pieces.
public struct SeededGenerator: RandomNumberGenerator, Sendable {
    private var state: UInt64

    public init(seed: UInt64) {
        state = seed
    }

    public mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

/// Which input source plays as which player.
///
/// In the lobby, sources join and leave freely and the players stay numbered
/// without gaps. Once a match starts the roster is locked: a source that
/// disconnects leaves its player "dropped" until another source reclaims the
/// slot, or the match goes on without them (`forfeit`).
public struct Roster<Source: Hashable>: Equatable {
    public enum Seat: Equatable {
        case active(Source)
        case dropped
    }

    public let capacity: Int
    public private(set) var seats: [PlayerID: Seat] = [:]
    /// True while a match is running.
    public private(set) var isLocked = false

    public init(capacity: Int = PlayerID.maxPlayers) {
        precondition((1...PlayerID.maxPlayers).contains(capacity))
        self.capacity = capacity
    }

    /// Every seated player (active or dropped), P1 first.
    public var players: [PlayerID] { seats.keys.sorted() }

    /// Players whose source has gone, P1 first.
    public var dropped: [PlayerID] { players.filter { seats[$0] == .dropped } }

    public func player(for source: Source) -> PlayerID? {
        seats.first { $0.value == .active(source) }?.key
    }

    /// Seat a source: the lowest free slot in the lobby, or the lowest dropped
    /// slot during a match. A source that's already seated keeps its player.
    /// Returns nil if there's no room.
    @discardableResult
    public mutating func join(_ source: Source) -> PlayerID? {
        if let seated = player(for: source) { return seated }
        let slot = isLocked
            ? dropped.first
            : PlayerID.all.prefix(capacity).first { seats[$0] == nil }
        guard let slot else { return nil }
        seats[slot] = .active(source)
        return slot
    }

    /// A source left on purpose (or disconnected). In the lobby its seat goes and
    /// the players after it move up; during a match its player is dropped.
    /// Returns the player it was.
    @discardableResult
    public mutating func leave(_ source: Source) -> PlayerID? {
        guard let player = player(for: source) else { return nil }
        if isLocked {
            seats[player] = .dropped
        } else {
            seats[player] = nil
            compact()
        }
        return player
    }

    /// Go on without a dropped player for the rest of the match.
    public mutating func forfeit(_ player: PlayerID) {
        guard seats[player] == .dropped else { return }
        seats[player] = nil
    }

    /// The match is starting: from now on, players keep their numbers.
    public mutating func lock() {
        isLocked = true
    }

    /// Back to the lobby. Dropped players are gone; the rest move up.
    public mutating func unlock() {
        isLocked = false
        for player in dropped { seats[player] = nil }
        compact()
    }

    private mutating func compact() {
        let sources = players.compactMap { player -> Source? in
            if case .active(let source) = seats[player] { return source }
            return nil
        }
        seats = Dictionary(uniqueKeysWithValues: zip(PlayerID.all, sources.map(Seat.active)))
    }
}
