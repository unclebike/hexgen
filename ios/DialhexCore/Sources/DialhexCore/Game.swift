// Game.swift — A solo game: one player, one dial
//
// `update(by:)` and the input methods mutate the game and return the events
// (clears, level-ups, game over) that drive sound, haptics, and effects. The
// rules themselves live in `Engine`, shared with co-op.

public enum Mode: String, CaseIterable, Sendable, Codable {
    case main, endless, sprint
}

public enum Phase: Sendable, Equatable {
    case playing, paused, gameOver
}

public enum RotationDirection: Int, Sendable {
    case counterClockwise = -1
    case clockwise = 1
}

/// Screen directions for moving the dial.
public enum Direction: Sendable {
    case up, down, left, right
}

public enum GameEvent: Sendable, Equatable {
    case spawn(color: Int)
    case rotate
    case clear(hexes: [Hex], points: Int)
    case power(Power)
    case levelUp(color: Int)
    case gameOver(won: Bool)
}

/// The colours a swap power changed: every `from` piece became `to`.
public struct ColorSwap: Sendable, Equatable {
    public let from: Int
    public let to: Int
}

/// The dial the player is holding.
public struct Cursor: Sendable, Equatable {
    public var vertex: Vertex
    /// The column (lattice j) the player last chose, so sideways moves drift back to it.
    var stickyJ: Int
}

/// A dial turn still being animated. The board already holds the result.
public struct DialTurn: Sendable, Equatable {
    public var vertex: Vertex
    public var direction: RotationDirection
    /// Stable identities of the pieces that actually participated in this turn.
    public var pieceIDs: Set<Int>
    public var elapsed: Double
}

public struct Game {
    /// Seconds per row of falling, at normal speed.
    public static let fallStep = 0.14
    /// Seconds a completed hex flashes before vanishing.
    public static let clearTime = 0.45
    public static let rotateTime = 0.12
    public static let sprintLength = 180.0

    /// The solo player's seat on the engine.
    private static let seat = 0
    private var engine: Engine

    public var board: Board { engine.board }
    public var mode: Mode { engine.mode }
    public var speed: Speed { engine.speed }
    /// Seconds per row of falling at this game's speed.
    public var stepTime: Double { engine.stepTime }
    public var phase: Phase { engine.phase }
    public var won: Bool { engine.won }
    public var score: Int { engine.score }
    public var level: Int { engine.level }
    public var hexesCleared: Int { engine.hexesCleared }
    public var hexesThisLevel: Int { engine.hexesThisLevel }
    public var activeColors: [Int] { engine.activeColors }
    public var cursor: Cursor { engine.cursors[Self.seat] }
    public var dialTurn: DialTurn? { engine.dialTurns[Self.seat] }
    /// Seconds left in sprint mode; nil in other modes.
    public var sprintTimeRemaining: Double? { engine.sprintTimeRemaining }
    /// The colours the latest swap changed; read it on a `.power(.swap)` event.
    public var lastSwap: ColorSwap? { engine.lastSwap }
    /// Whether the dial is holding up a piece that would fall without it.
    public var isHoldingPiece: Bool { engine.isHolding(Self.seat) }
    /// A new player's game: see `Progression.spawnInterval(level:assisted:)`.
    public var assisted: Bool { engine.assisted }
    /// The assisted game's one rescue has drained a full bin. It fires as a `.power(.drain)`.
    public var rescued: Bool { engine.rescued }

    public init(mode: Mode = .main, speed: Speed = .normal, assisted: Bool = false,
                rng: any RandomNumberGenerator = SystemRandomNumberGenerator()) {
        // Start the dial low in the middle, where the first triangles land
        let start = Grid.nearestDial(to: LatticePoint(Double(Grid.size) * 0.5, 0))!
        engine = Engine(mode: mode, speed: speed, assisted: assisted, rng: rng, dials: [start])
    }

    /// How far (0…1) pieces have moved from their `from` cell toward their current one.
    public var fallProgress: Double { engine.fallProgress }

    /// Advance the game by `dt` seconds.
    public mutating func update(by dt: Double) -> [GameEvent] {
        engine.update(by: dt)
    }

    // MARK: - Input

    /// Turn the dial.
    public mutating func rotate(_ direction: RotationDirection) -> [GameEvent] {
        engine.rotate(Self.seat, direction)
    }

    /// Put the dial on a vertex.
    public mutating func moveCursor(to vertex: Vertex) {
        engine.moveCursor(Self.seat, to: vertex)
    }

    /// Nudge the dial one step. On screen the lattice is turned 90°: up/down
    /// move along a lattice row (j ∓ 2), and left/right step to the
    /// neighbouring row, drifting back toward the height you were last at.
    public mutating func moveCursor(_ direction: Direction) {
        engine.moveCursor(Self.seat, direction)
    }

    /// A tap on the board, in lattice units. Tapping the dial you're on turns
    /// it; tapping near another dial moves there. Tapping while paused resumes.
    public mutating func tap(at point: LatticePoint) -> [GameEvent] {
        if phase == .paused {
            togglePause()
            return []
        }
        guard let dial = Grid.nearestDial(to: point, within: 1.2) else { return [] }
        if dial == cursor.vertex { return rotate(.clockwise) }
        moveCursor(to: dial)
        return []
    }

    public mutating func togglePause() {
        engine.togglePause()
    }
}

// MARK: - Testing

extension Game {
    /// Test hook: replace the board wholesale, so tests can set up a position.
    mutating func setBoardForTesting(_ board: Board) {
        engine.setBoardForTesting(board)
    }
}
