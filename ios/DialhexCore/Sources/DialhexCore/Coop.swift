// Coop.swift — Two players, one bin
//
// Both players turn their own dial on the same board, by the same rules as a
// solo game, and share its score, level, and fate. The two dials can never
// overlap: a dial stops when the next step would share a triangle with the
// other one. If a player leaves, their dial lifts off and the other plays on.

public struct CoopGame {
    /// Co-op is always exactly two players.
    public static let players = [PlayerID(0), PlayerID(1)]

    /// Where the dials start: low in the middle, P1 on the left of the screen
    /// and P2 on the right, one row apart so they don't touch.
    static let startDials = [Vertex(k: 7, j: 5), Vertex(k: 5, j: 5)]

    private var engine: Engine

    public var board: Board { engine.board }
    public var mode: Mode { engine.mode }
    public var speed: Speed { engine.speed }
    public var phase: Phase { engine.phase }
    public var won: Bool { engine.won }
    public var score: Int { engine.score }
    public var level: Int { engine.level }
    public var hexesCleared: Int { engine.hexesCleared }
    public var activeColors: [Int] { engine.activeColors }
    /// Seconds left in sprint mode; nil in other modes.
    public var sprintTimeRemaining: Double? { engine.sprintTimeRemaining }
    /// How far (0…1) pieces have moved from their `from` cell toward their current one.
    public var fallProgress: Double { engine.fallProgress }

    public init(mode: Mode = .endless, speed: Speed = .normal,
                rng: any RandomNumberGenerator = SystemRandomNumberGenerator()) {
        engine = Engine(mode: mode, speed: speed, rng: rng, dials: Self.startDials)
    }

    /// Players whose dial is still on the board, P1 first.
    public var seatedPlayers: [PlayerID] {
        Self.players.filter { !engine.absent.contains($0.slot) }
    }

    /// A player's dial, or nil once they've left.
    public func cursor(for player: PlayerID) -> Cursor? {
        guard let seat = seat(of: player) else { return nil }
        return engine.cursors[seat]
    }

    /// A player's turn still being animated.
    public func dialTurn(for player: PlayerID) -> DialTurn? {
        seat(of: player).flatMap { engine.dialTurns[$0] }
    }

    /// Every turn still being animated.
    public var dialTurns: [DialTurn] { engine.dialTurns.compactMap { $0 } }

    /// Advance the game by `dt` seconds.
    public mutating func update(by dt: Double) -> [GameEvent] {
        engine.update(by: dt)
    }

    /// One player's move or turn, on their own dial.
    public mutating func apply(_ input: PlayerInput, from player: PlayerID) -> [GameEvent] {
        guard let seat = seat(of: player) else { return [] }
        switch input {
        case .move(let direction):
            engine.moveCursor(seat, direction)
            return []
        case .place(let vertex):
            engine.moveCursor(seat, to: vertex)
            return []
        case .rotate(let direction):
            return engine.rotate(seat, direction)
        }
    }

    /// Either player pauses (and resumes) the game.
    public mutating func togglePause() {
        engine.togglePause()
    }

    /// A player leaves for good: their dial lifts off the board, freeing the
    /// triangles it was holding and the space it took up.
    public mutating func leave(_ player: PlayerID) {
        guard let seat = seat(of: player) else { return }
        engine.removeSeat(seat)
    }

    /// Everything the screen shows, for drawing this game on the other player's device.
    public var snapshot: CoopSnapshot { engine.snapshot }

    /// A copy of a game from a snapshot, to draw on the guest's device. It's
    /// never updated, only replaced by the next snapshot.
    init(restoring snapshot: CoopSnapshot) {
        engine = Engine(mode: snapshot.mode, speed: snapshot.speed, rng: SeededGenerator(seed: 0), dials: Self.startDials)
        engine.restore(snapshot)
    }

    /// A copy's animations between snapshots (see `CoopReplica.animate(by:)`).
    mutating func animate(by dt: Double) {
        engine.animate(by: dt)
    }

    /// Keep a player's turn animating from where it was in `previous`, if it's the same turn.
    mutating func continueTurn(of player: PlayerID, from previous: CoopGame) {
        guard let seat = seat(of: player) else { return }
        engine.continueTurn(seat, from: previous.dialTurn(for: player))
    }

    /// The player's seat on the engine, if they're still playing.
    private func seat(of player: PlayerID) -> Int? {
        let seat = player.slot
        guard Self.players.contains(player), !engine.absent.contains(seat) else { return nil }
        return seat
    }
}

// MARK: - Testing

extension CoopGame {
    /// Test hook: replace the board wholesale, so tests can set up a position.
    mutating func setBoardForTesting(_ board: Board) {
        engine.setBoardForTesting(board)
    }

    /// Test hook: put a player's dial somewhere (still only if it fits).
    mutating func moveCursorForTesting(_ player: PlayerID, to vertex: Vertex) {
        guard let seat = seat(of: player) else { return }
        engine.moveCursor(seat, to: vertex)
    }
}
