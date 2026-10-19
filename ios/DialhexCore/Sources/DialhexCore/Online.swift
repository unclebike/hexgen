// Online.swift — Co-op between two devices over the internet (Game Center)
//
// One device hosts: it runs the only `CoopGame` and sends the other device
// snapshots of what to draw, plus the game's events for sound and haptics.
// The guest sends only its own player's inputs. It applies them to its copy
// straight away so turning feels instant, and reapplies any the host hasn't
// confirmed yet on top of every snapshot (`CoopReplica`).
//
// Nothing from the other device is trusted. Every message is size-capped and
// versioned, and each field is checked before use: a cell must be on the
// board, a dial must be a real dial, a colour must exist. The host also
// rate-limits inputs and leaves impossible moves to the rules. The format is
// compact binary, read from a byte array with bounds checks, so a bad message
// is rejected rather than crashing the game. A full board is about 2 KB.

import Foundation

public enum OnlineCoop {
    /// Bumped whenever a message changes shape.
    public static let version: UInt8 = 1
    /// Game Center only matches requests with the same player group, so builds
    /// that can't understand each other never meet.
    public static var playerGroup: Int { Int(version) }
    /// The host plays as P1 and the guest as P2.
    public static let hostPlayer = CoopGame.players[0]
    public static let guestPlayer = CoopGame.players[1]

    /// The largest message each side accepts. Anything bigger is dropped unread.
    public static let maxHostMessageBytes = 4096
    public static let maxGuestMessageBytes = 64
    /// Snapshots up to this size go unreliable, since a lost one is soon
    /// replaced by the next. Bigger ones go reliable, to avoid fragmenting.
    public static let unreliableLimit = 1000
    /// How often the host sends a snapshot while the game runs.
    public static let snapshotInterval = 1.0 / 20
    /// Most guest messages the host takes per second, and the most in a burst.
    public static let inputRate = 20.0
    public static let inputBurst = 12.0
    /// How many unconfirmed inputs the guest keeps before dropping the oldest.
    static let maxPending = 64

    /// Whether this device hosts, from both hellos. The player who sent the
    /// invite hosts. If that doesn't decide it, the higher nonce does. Returns
    /// nil on a tie, and both sides send a new hello.
    public static func isHost(local: Hello, remote: Hello) -> Bool? {
        if local.inviter != remote.inviter { return local.inviter }
        if local.nonce == remote.nonce { return nil }
        return local.nonce > remote.nonce
    }

    /// Each device's first message, used to settle who hosts.
    public struct Hello: Sendable, Equatable {
        public var nonce: UInt64
        /// This player sent the invitation.
        public var inviter: Bool

        public init(nonce: UInt64, inviter: Bool) {
            self.nonce = nonce
            self.inviter = inviter
        }
    }
}

// MARK: - Snapshot

/// Everything a co-op screen shows, sent from the host to the guest.
public struct CoopSnapshot: Sendable, Equatable {
    public var mode: Mode
    public var speed: Speed
    public var phase: Phase
    public var won: Bool
    public var score: Int
    public var level: Int
    public var hexesCleared: Int
    public var hexesThisLevel: Int
    public var activeColors: [Int]
    public var sprintTimeRemaining: Double?
    public var fallProgress: Double
    public var board: Board
    /// Each seat's dial, or nil once that player has left.
    public var dials: [Cursor?]
    public var dialTurns: [DialTurn?]
}

// MARK: - Messages

public enum OnlineMessage: Sendable, Equatable {
    /// Sent by both devices, before roles are settled.
    case hello(OnlineCoop.Hello)
    /// Guest to host: one input on the guest's dial, numbered from 1 upward.
    case input(seq: UInt32, PlayerInput)
    /// Guest to host: pause (true) or resume (false). Explicit rather than a
    /// toggle, so a guest pausing as their app goes to the background can't
    /// resume a game the host had already paused.
    case pause(Bool)
    /// Guest to host: play again after game over.
    case rematch
    /// Host to guest: the game as it stands. `ack` is the last guest input applied.
    case state(seq: UInt32, ack: UInt32, CoopSnapshot)
    /// Host to guest: what just happened. `by` is the player whose input caused it, nil for the clock.
    case events(by: PlayerID?, [GameEvent])
    /// Either way: leaving the match.
    case bye

    /// Who a message came from, which decides what it may say.
    public enum Sender: Sendable {
        /// Before roles are settled: only a hello or a bye.
        case undecided
        case host
        case guest
    }

    private enum Kind: UInt8 {
        case hello = 0, input, pause, rematch, state, events, bye
    }

    private static let magic: UInt8 = 0xD7

    // MARK: Encoding

    public var encoded: Data {
        var w = WireWriter()
        w.u8(Self.magic)
        w.u8(OnlineCoop.version)
        switch self {
        case .hello(let hello):
            w.u8(Kind.hello.rawValue)
            w.u64(hello.nonce)
            w.bool(hello.inviter)
        case .input(let seq, let input):
            w.u8(Kind.input.rawValue)
            w.u32(seq)
            switch input {
            case .move(let direction):
                w.u8(0)
                w.u8(Wire.code(direction))
            case .place(let vertex):
                w.u8(1)
                w.vertex(vertex)
            case .rotate(let direction):
                w.u8(2)
                w.bool(direction == .clockwise)
            }
        case .pause(let paused):
            w.u8(Kind.pause.rawValue)
            w.bool(paused)
        case .rematch:
            w.u8(Kind.rematch.rawValue)
        case .state(let seq, let ack, let snapshot):
            w.u8(Kind.state.rawValue)
            w.u32(seq)
            w.u32(ack)
            w.snapshot(snapshot)
        case .events(let player, let events):
            w.u8(Kind.events.rawValue)
            w.u8(player.map { UInt8($0.slot) } ?? 0xFF)
            let events = events.prefix(Wire.maxEvents)
            w.u8(UInt8(events.count))
            for event in events { w.event(event) }
        case .bye:
            w.u8(Kind.bye.rawValue)
        }
        return w.data
    }

    // MARK: Decoding

    /// Read a message from the other device. Returns nil for anything
    /// oversized, from another version, malformed, out of range, or not
    /// allowed from this sender.
    public static func decode(_ data: Data, from sender: Sender) -> OnlineMessage? {
        let limit = sender == .host ? OnlineCoop.maxHostMessageBytes : OnlineCoop.maxGuestMessageBytes
        guard data.count >= 3, data.count <= limit else { return nil }
        var r = WireReader(Array(data))
        do {
            guard try r.u8() == magic, try r.u8() == OnlineCoop.version,
                  let kind = Kind(rawValue: try r.u8()) else { return nil }
            let message: OnlineMessage
            switch (kind, sender) {
            case (.hello, .undecided):
                message = .hello(OnlineCoop.Hello(nonce: try r.u64(), inviter: try r.bool()))
            case (.input, .guest):
                let seq = try r.u32()
                let input: PlayerInput
                switch try r.u8() {
                case 0: input = .move(try Wire.direction(r.u8()))
                case 1: input = .place(try r.dial())
                case 2: input = .rotate(try r.bool() ? .clockwise : .counterClockwise)
                default: return nil
                }
                message = .input(seq: seq, input)
            case (.pause, .guest):
                message = .pause(try r.bool())
            case (.rematch, .guest):
                message = .rematch
            case (.state, .host):
                message = .state(seq: try r.u32(), ack: try r.u32(), try r.snapshot())
            case (.events, .host):
                let by = try r.u8()
                guard by == 0xFF || by < CoopGame.players.count else { return nil }
                let count = Int(try r.u8())
                guard count <= Wire.maxEvents else { return nil }
                var events: [GameEvent] = []
                for _ in 0..<count { events.append(try r.event()) }
                message = .events(by: by == 0xFF ? nil : PlayerID(Int(by)), events)
            case (.bye, _):
                message = .bye
            default:
                return nil
            }
            return r.isAtEnd ? message : nil
        } catch {
            return nil
        }
    }
}

// MARK: - Host side

/// The host's view of its guest: which inputs it has applied, and how fast
/// the guest may send.
public struct CoopHostLink: Sendable {
    /// The last guest input taken, confirmed back in every snapshot.
    public private(set) var ack: UInt32 = 0
    private var stateSeq: UInt32 = 0
    private var limiter = InputLimiter(rate: OnlineCoop.inputRate, burst: OnlineCoop.inputBurst)

    public init() {}

    /// Whether to apply a guest input that arrived at `time` (seconds). It must
    /// be newer than the last one and within the rate limit. A dropped input
    /// still counts as seen, so the guest's prediction lets go of it.
    public mutating func accept(seq: UInt32, at time: Double) -> Bool {
        guard seq > ack else { return false }
        ack = seq
        return limiter.allow(at: time)
    }

    /// Whether to act on a guest's pause or rematch, within the same rate limit.
    public mutating func allow(at time: Double) -> Bool {
        limiter.allow(at: time)
    }

    /// The next snapshot's number.
    public mutating func nextStateSeq() -> UInt32 {
        stateSeq &+= 1
        return stateSeq
    }
}

/// A token bucket: up to `burst` at once, refilling at `rate` per second.
public struct InputLimiter: Sendable {
    let rate: Double
    let burst: Double
    private var tokens: Double
    private var last: Double?

    public init(rate: Double, burst: Double) {
        self.rate = rate
        self.burst = burst
        tokens = burst
    }

    public mutating func allow(at time: Double) -> Bool {
        if let last { tokens = min(burst, tokens + max(0, time - last) * rate) }
        last = time
        guard tokens >= 1 else { return false }
        tokens -= 1
        return true
    }
}

// MARK: - Guest side

/// The guest's copy of the host's game. It's drawn but never run. The guest's
/// own inputs show at once, and are reapplied on top of each snapshot until
/// the host confirms them.
public struct CoopReplica {
    public let player = OnlineCoop.guestPlayer
    /// What to draw: the latest snapshot, plus the guest's unconfirmed inputs.
    public private(set) var game: CoopGame
    /// The latest snapshot's number; older ones that arrive late are ignored.
    public private(set) var stateSeq: UInt32
    private var confirmed: CoopGame
    private var pending: [(seq: UInt32, input: PlayerInput)] = []
    private var nextSeq: UInt32 = 1

    /// Start from the host's first snapshot.
    public init(seq: UInt32, ack: UInt32, snapshot: CoopSnapshot) {
        confirmed = CoopGame(restoring: snapshot)
        game = confirmed
        stateSeq = seq
        nextSeq = ack &+ 1
    }

    /// Apply the guest's own input now. Returns the number to send it under,
    /// and its events (a turn), so the guest hears it at once.
    public mutating func predict(_ input: PlayerInput) -> (seq: UInt32, events: [GameEvent]) {
        let seq = nextSeq
        nextSeq &+= 1
        pending.append((seq, input))
        if pending.count > OnlineCoop.maxPending { pending.removeFirst(pending.count - OnlineCoop.maxPending) }
        return (seq, game.apply(input, from: player))
    }

    /// Take a snapshot from the host. Returns false if it's older than the last one.
    @discardableResult
    public mutating func receive(seq: UInt32, ack: UInt32, snapshot: CoopSnapshot) -> Bool {
        guard seq > stateSeq else { return false }
        stateSeq = seq
        confirmed = CoopGame(restoring: snapshot)
        pending.removeAll { $0.seq <= ack }
        let previous = game
        game = confirmed
        for (_, input) in pending { _ = game.apply(input, from: player) }
        // The guest's own turn carries on from where it had got to, rather
        // than starting over each time it's redone or the host catches up
        game.continueTurn(of: player, from: previous)
        return true
    }

    /// Run the fall and turn animations on between snapshots, so the board
    /// moves smoothly. Nothing changes place until the next snapshot.
    public mutating func animate(by dt: Double) {
        game.animate(by: dt)
    }

    /// Inputs sent but not yet confirmed by the host.
    public var unconfirmedCount: Int { pending.count }
}

// MARK: - Wire format

enum Wire {
    static let maxEvents = 64
    static let cellIndex: [Cell: UInt8] = Dictionary(uniqueKeysWithValues: Grid.cells.enumerated().map { ($1, UInt8($0)) })
    /// Milliseconds, the resolution for the timers in a snapshot.
    static let ms = 1000.0

    static func code(_ direction: Direction) -> UInt8 {
        switch direction {
        case .up: 0
        case .down: 1
        case .left: 2
        case .right: 3
        }
    }

    static func direction(_ code: UInt8) throws -> Direction {
        switch code {
        case 0: .up
        case 1: .down
        case 2: .left
        case 3: .right
        default: throw WireError.invalid
        }
    }

    static func phaseCode(_ phase: Phase) -> UInt8 {
        switch phase {
        case .playing: 0
        case .paused: 1
        case .gameOver: 2
        }
    }
}

enum WireError: Error {
    case short, invalid
}

struct WireWriter {
    private(set) var data = Data()

    mutating func u8(_ v: UInt8) { data.append(v) }
    mutating func bool(_ v: Bool) { u8(v ? 1 : 0) }
    mutating func u16(_ v: UInt16) { withUnsafeBytes(of: v.bigEndian) { data.append(contentsOf: $0) } }
    mutating func u32(_ v: UInt32) { withUnsafeBytes(of: v.bigEndian) { data.append(contentsOf: $0) } }
    mutating func u64(_ v: UInt64) { withUnsafeBytes(of: v.bigEndian) { data.append(contentsOf: $0) } }
    mutating func i8(_ v: Int) { u8(UInt8(bitPattern: Int8(clamping: v))) }
    mutating func millis(_ seconds: Double) { u32(UInt32(clamping: Int((max(0, seconds) * Wire.ms).rounded()))) }

    mutating func vertex(_ v: Vertex) {
        i8(v.k)
        i8(v.j)
    }

    mutating func snapshot(_ s: CoopSnapshot) {
        u8(UInt8(Mode.allCases.firstIndex(of: s.mode) ?? 0))
        u8(UInt8(Speed.allCases.firstIndex(of: s.speed) ?? 0))
        u8(Wire.phaseCode(s.phase))
        bool(s.won)
        u32(UInt32(clamping: s.score))
        u8(UInt8(clamping: s.level))
        u16(UInt16(clamping: s.hexesCleared))
        u8(UInt8(clamping: s.hexesThisLevel))
        u8(UInt8(clamping: s.activeColors.count))
        for color in s.activeColors { u8(UInt8(clamping: color)) }
        if let sprint = s.sprintTimeRemaining {
            bool(true)
            millis(sprint)
        } else {
            bool(false)
        }
        u16(UInt16((min(1, max(0, s.fallProgress)) * Double(UInt16.max)).rounded()))

        u8(UInt8(clamping: s.dials.count))
        for dial in s.dials {
            guard let dial else {
                bool(false)
                continue
            }
            bool(true)
            vertex(dial.vertex)
            i8(dial.stickyJ)
        }
        for turn in s.dialTurns {
            guard let turn else {
                bool(false)
                continue
            }
            bool(true)
            vertex(turn.vertex)
            bool(turn.direction == .clockwise)
            millis(turn.elapsed)
            let ids = turn.pieceIDs.sorted().prefix(6)
            u8(UInt8(ids.count))
            for id in ids { u32(UInt32(truncatingIfNeeded: id)) }
        }

        // Pieces in board order, so the same board always encodes the same way
        let pieces = Grid.cells.compactMap { cell in s.board[cell].map { (cell, $0) } }
        u8(UInt8(pieces.count))
        for (cell, piece) in pieces {
            u8(Wire.cellIndex[cell] ?? 0)
            u32(UInt32(truncatingIfNeeded: piece.id))
            u8(UInt8(clamping: piece.color))
            // Low two bits: the power. Next two: where it came from (none, a cell, or above the bin).
            var flags: UInt8 = switch piece.power {
            case nil: 0
            case .drain: 1
            case .swap: 2
            }
            let fromIndex = piece.from.flatMap { Wire.cellIndex[$0] }
            if fromIndex != nil {
                flags |= 1 << 2
            } else if piece.from == Cell(r: cell.r, c: cell.c - 2) {
                flags |= 2 << 2
            }
            u8(flags)
            if let fromIndex { u8(fromIndex) }
            millis(piece.clearTime)
        }
    }

    mutating func event(_ event: GameEvent) {
        switch event {
        case .spawn(let color):
            u8(0)
            u8(UInt8(clamping: color))
        case .rotate:
            u8(1)
        case .clear(let hexes, let points):
            u8(2)
            let hexes = hexes.prefix(Grid.dials.count)
            u8(UInt8(hexes.count))
            for hex in hexes {
                vertex(hex.center)
                u8(UInt8(clamping: hex.color))
            }
            u32(UInt32(clamping: points))
        case .power(let power):
            u8(3)
            bool(power == .swap)
        case .levelUp(let color):
            u8(4)
            u8(UInt8(clamping: color))
        case .gameOver(let won):
            u8(5)
            bool(won)
        }
    }
}

/// Reads untrusted bytes. Every read is bounds-checked, and every value that
/// names something on the board is checked against the board.
struct WireReader {
    private let bytes: [UInt8]
    private var at = 0

    init(_ bytes: [UInt8]) { self.bytes = bytes }

    var isAtEnd: Bool { at == bytes.count }

    mutating func u8() throws -> UInt8 {
        guard at < bytes.count else { throw WireError.short }
        defer { at += 1 }
        return bytes[at]
    }

    mutating func bool() throws -> Bool {
        switch try u8() {
        case 0: return false
        case 1: return true
        default: throw WireError.invalid
        }
    }

    private mutating func bigEndian(_ count: Int) throws -> UInt64 {
        guard bytes.count - at >= count else { throw WireError.short }
        var v: UInt64 = 0
        for i in 0..<count { v = v << 8 | UInt64(bytes[at + i]) }
        at += count
        return v
    }

    mutating func u16() throws -> UInt16 { UInt16(try bigEndian(2)) }
    mutating func u32() throws -> UInt32 { UInt32(try bigEndian(4)) }
    mutating func u64() throws -> UInt64 { try bigEndian(8) }
    mutating func i8() throws -> Int { Int(Int8(bitPattern: try u8())) }

    /// Seconds from milliseconds, rejected if over `limit`.
    mutating func millis(upTo limit: Double) throws -> Double {
        let seconds = Double(try u32()) / Wire.ms
        guard seconds <= limit + 0.001 else { throw WireError.invalid }
        return seconds
    }

    mutating func color() throws -> Int {
        let color = Int(try u8())
        guard color < Progression.colorCount else { throw WireError.invalid }
        return color
    }

    /// A vertex that's a real dial on the board.
    mutating func dial() throws -> Vertex {
        let v = Vertex(k: try i8(), j: try i8())
        guard Grid.isDial(v) else { throw WireError.invalid }
        return v
    }

    mutating func cell() throws -> Cell {
        let index = Int(try u8())
        guard index < Grid.cells.count else { throw WireError.invalid }
        return Grid.cells[index]
    }

    mutating func snapshot() throws -> CoopSnapshot {
        let modeIndex = Int(try u8()), speedIndex = Int(try u8())
        guard modeIndex < Mode.allCases.count, speedIndex < Speed.allCases.count else { throw WireError.invalid }
        let phase: Phase = switch try u8() {
        case 0: .playing
        case 1: .paused
        case 2: .gameOver
        default: throw WireError.invalid
        }
        let won = try bool()
        let score = Int(try u32())
        let level = Int(try u8())
        let hexesCleared = Int(try u16())
        let hexesThisLevel = Int(try u8())
        let colorCount = Int(try u8())
        guard (1...Progression.colorCount).contains(colorCount), level <= Progression.colorCount,
              hexesThisLevel <= Progression.hexesPerLevel * Progression.colorCount else { throw WireError.invalid }
        var activeColors: [Int] = []
        for _ in 0..<colorCount { activeColors.append(try color()) }
        let sprint = try bool() ? try millis(upTo: Game.sprintLength) : nil
        let fallProgress = Double(try u16()) / Double(UInt16.max)

        // Exactly co-op's two seats, on real dials that don't overlap
        let seats = CoopGame.players.count
        guard Int(try u8()) == seats else { throw WireError.invalid }
        var dials: [Cursor?] = []
        for _ in 0..<seats {
            dials.append(try bool() ? Cursor(vertex: try dial(), stickyJ: try i8()) : nil)
        }
        let present = dials.compactMap { $0 }
        for (i, a) in present.enumerated() {
            for b in present[(i + 1)...] where !Set(Grid.dialCells(a.vertex)).isDisjoint(with: Grid.dialCells(b.vertex)) {
                throw WireError.invalid
            }
        }
        var turns: [DialTurn?] = []
        for _ in 0..<seats {
            guard try bool() else {
                turns.append(nil)
                continue
            }
            let vertex = try dial()
            let direction: RotationDirection = try bool() ? .clockwise : .counterClockwise
            let elapsed = try millis(upTo: Game.rotateTime)
            let idCount = Int(try u8())
            guard idCount <= 6 else { throw WireError.invalid }
            var ids = Set<Int>()
            for _ in 0..<idCount { ids.insert(Int(try u32())) }
            turns.append(DialTurn(vertex: vertex, direction: direction, pieceIDs: ids, elapsed: elapsed))
        }

        let pieceCount = Int(try u8())
        guard pieceCount <= Grid.cells.count else { throw WireError.invalid }
        var board: Board = [:]
        var ids = Set<Int>()
        for _ in 0..<pieceCount {
            let cell = try cell()
            let id = Int(try u32())
            let color = try color()
            let flags = try u8()
            guard flags & 0xF0 == 0, board[cell] == nil, ids.insert(id).inserted else { throw WireError.invalid }
            let power: Power? = switch flags & 0b11 {
            case 0: nil
            case 1: .drain
            case 2: .swap
            default: throw WireError.invalid
            }
            let from: Cell? = switch (flags >> 2) & 0b11 {
            case 0: nil
            case 1: try self.cell()
            case 2: Cell(r: cell.r, c: cell.c - 2)
            default: throw WireError.invalid
            }
            let clearTime = try millis(upTo: Game.clearTime)
            board[cell] = Piece(id: id, color: color, power: power, from: from, clearTime: clearTime)
        }

        return CoopSnapshot(
            mode: Mode.allCases[modeIndex], speed: Speed.allCases[speedIndex], phase: phase, won: won,
            score: score, level: level, hexesCleared: hexesCleared, hexesThisLevel: hexesThisLevel,
            activeColors: activeColors, sprintTimeRemaining: sprint, fallProgress: fallProgress,
            board: board, dials: dials, dialTurns: turns)
    }

    mutating func event() throws -> GameEvent {
        switch try u8() {
        case 0:
            return .spawn(color: try color())
        case 1:
            return .rotate
        case 2:
            let count = Int(try u8())
            guard count <= Grid.dials.count else { throw WireError.invalid }
            var hexes: [Hex] = []
            for _ in 0..<count {
                let center = try dial()
                hexes.append(Hex(center: center, color: try color(), cells: Grid.dialCells(center)))
            }
            return .clear(hexes: hexes, points: Int(try u32()))
        case 3:
            return .power(try bool() ? .swap : .drain)
        case 4:
            return .levelUp(color: try color())
        case 5:
            return .gameOver(won: try bool())
        default:
            throw WireError.invalid
        }
    }
}
