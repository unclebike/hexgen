// Game.swift — Game state and rules
//
// `update(by:)` and the input methods mutate the game and return the events
// (clears, level-ups, game over) that drive sound, haptics, and effects.

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
    public var elapsed: Double
}

public struct Game {
    /// Seconds per row of falling.
    public static let fallStep = 0.14
    /// Seconds a completed hex flashes before vanishing.
    public static let clearTime = 0.45
    public static let rotateTime = 0.12
    public static let sprintLength = 180.0

    public private(set) var board: Board = [:]
    public let mode: Mode
    public private(set) var phase: Phase = .playing
    public private(set) var won = false
    public private(set) var score = 0
    public private(set) var level = 2
    public private(set) var hexesCleared = 0
    public private(set) var hexesThisLevel = 0
    public private(set) var activeColors = Progression.initialColors
    public private(set) var cursor: Cursor
    public private(set) var dialTurn: DialTurn?
    /// Seconds left in sprint mode; nil in other modes.
    public private(set) var sprintTimeRemaining: Double?

    private var spawnInterval = Progression.spawnInterval(level: 2)
    private var spawnTimer = 0.0
    private var fallTimer = 0.0
    private var nextPieceID = 0
    private var rng: any RandomNumberGenerator

    public init(mode: Mode = .main, rng: any RandomNumberGenerator = SystemRandomNumberGenerator()) {
        self.mode = mode
        self.rng = rng
        // Start the dial low in the middle, where the first triangles land
        let start = Grid.nearestDial(to: LatticePoint(Double(Grid.size) * 0.5, 0))!
        cursor = Cursor(vertex: start, stickyJ: start.j)
        sprintTimeRemaining = mode == .sprint ? Self.sprintLength : nil
    }

    /// How far (0…1) pieces have moved from their `from` cell toward their current one.
    public var fallProgress: Double { min(1, fallTimer / Self.fallStep) }

    /// Advance the game by `dt` seconds.
    public mutating func update(by dt: Double) -> [GameEvent] {
        var events: [GameEvent] = []
        guard phase == .playing else { return events }

        if let remaining = sprintTimeRemaining {
            sprintTimeRemaining = max(0, remaining - dt)
            if remaining - dt <= 0 {
                endGame(&events)
                return events
            }
        }

        if var turn = dialTurn {
            turn.elapsed += dt
            dialTurn = turn.elapsed >= Self.rotateTime ? nil : turn
        }

        // Finished clears leave holes for the triangles above to fall into
        for (cell, piece) in board where piece.isClearing {
            let left = piece.clearTime - dt
            if left <= 0 { board[cell] = nil } else { board[cell]?.clearTime = left }
        }

        // Falling and spawning both run on the same step clock, so new
        // triangles enter in sync with the ones already falling.
        fallTimer += dt
        var steps = 0
        while fallTimer >= Self.fallStep {
            if steps == 3 { // fell far behind (app was suspended); don't fast-forward
                fallTimer = 0
                break
            }
            steps += 1
            fallTimer -= Self.fallStep
            Dropper.stepGravity(&board)

            spawnTimer -= Self.fallStep
            if spawnTimer <= 0 {
                spawnTimer += spawnInterval
                let result = Dropper.spawn(into: &board, colors: activeColors, id: nextPieceID, using: &rng)
                switch result {
                case .full:
                    endGame(&events)
                    return events
                case .spawned:
                    events.append(.spawn(color: board.values.first { $0.id == nextPieceID }!.color))
                    nextPieceID += 1
                case .wait:
                    break
                }
            }
        }

        detectClears(&events)
        return events
    }

    private mutating func detectClears(_ events: inout [GameEvent]) {
        let hexes = Dial.findHexes(board)
        guard !hexes.isEmpty else { return }

        var powers: [Power] = []
        for hex in hexes {
            for cell in hex.cells where board[cell]?.isClearing == false {
                board[cell]?.clearTime = Self.clearTime
                if let power = board[cell]?.power { powers.append(power) }
            }
        }

        let points = Progression.score(hexes: hexes.count, level: level)
        score += points
        hexesCleared += hexes.count
        hexesThisLevel += hexes.count
        events.append(.clear(hexes: hexes, points: points))

        for power in powers { apply(power, &events) }

        if hexesThisLevel >= Progression.hexesPerLevel && activeColors.count < Palette.colors.count {
            activeColors.append(activeColors.count)
            hexesThisLevel -= Progression.hexesPerLevel
            level = activeColors.count
            spawnInterval = Progression.spawnInterval(level: level)
            events.append(.levelUp(color: activeColors.last!))
        }
        if mode == .main && hexesCleared >= Progression.winHexes {
            won = true
            endGame(&events)
        }
    }

    /// Glowing triangles fire when they're cleared.
    private mutating func apply(_ power: Power, _ events: inout [GameEvent]) {
        switch power {
        case .drain:
            // Empty the bottom two triangle-heights of the bin (lattice x is down)
            for cell in Grid.cells where Grid.center(of: cell).x > Double(Grid.size - 2) {
                if board[cell]?.isClearing == false { board[cell] = nil }
            }
        case .swap where activeColors.count > 1:
            let from = activeColors.randomElement(using: &rng)!
            let to = activeColors.filter { $0 != from }.randomElement(using: &rng)!
            for (cell, piece) in board where piece.color == from && !piece.isClearing {
                board[cell]?.color = to
            }
        case .swap:
            break
        }
        events.append(.power(power))
    }

    private mutating func endGame(_ events: inout [GameEvent]) {
        phase = .gameOver
        events.append(.gameOver(won: won))
    }

    // MARK: - Input

    /// Turn the dial.
    public mutating func rotate(_ direction: RotationDirection) -> [GameEvent] {
        guard phase == .playing, Dial.rotate(&board, at: cursor.vertex, direction: direction) else { return [] }
        dialTurn = DialTurn(vertex: cursor.vertex, direction: direction, elapsed: 0)
        return [.rotate]
    }

    /// Put the dial on a vertex.
    public mutating func moveCursor(to vertex: Vertex) {
        guard phase == .playing, Grid.isDial(vertex) else { return }
        cursor = Cursor(vertex: vertex, stickyJ: vertex.j)
    }

    /// Nudge the dial one step. On screen the lattice is turned 90°: up/down
    /// move along a lattice row (j ∓ 2), and left/right step to the
    /// neighbouring row, drifting back toward the height you were last at.
    public mutating func moveCursor(_ direction: Direction) {
        guard phase == .playing else { return }
        let (k, j, sticky) = (cursor.vertex.k, cursor.vertex.j, cursor.stickyJ)
        switch direction {
        case .up, .down:
            let target = Vertex(k: k, j: j + (direction == .up ? -2 : 2))
            if Grid.isDial(target) { cursor = Cursor(vertex: target, stickyJ: target.j) }
        case .left, .right:
            let nk = k + (direction == .left ? 1 : -1)
            let best = [j - 1, j + 1]
                .filter { Grid.isDial(Vertex(k: nk, j: $0)) }
                .min { abs($0 - sticky) < abs($1 - sticky) }
            if let best { cursor = Cursor(vertex: Vertex(k: nk, j: best), stickyJ: sticky) }
        }
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
        switch phase {
        case .playing: phase = .paused
        case .paused: phase = .playing
        case .gameOver: break
        }
    }
}
