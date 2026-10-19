// Engine.swift — The rules of one bin, for however many dials are on it
//
// Solo `Game` runs one dial and `CoopGame` runs two on the same board, so
// both play by exactly these rules. Dials are numbered by seat. They may
// never overlap: a dial can't move onto a spot that shares a cell with
// another one, so no triangle is ever under two dials. Gravity is held under
// every dial at once.

struct Engine {
    private(set) var board: Board = [:]
    let mode: Mode
    let speed: Speed
    /// Seconds per row of falling at this game's speed.
    let stepTime: Double
    /// A new player's game: an eased pace, and one rescue from a full bin.
    let assisted: Bool
    /// The assisted game's rescue has drained a full bin.
    private(set) var rescued = false
    private(set) var phase: Phase = .playing
    private(set) var won = false
    private(set) var score = 0
    private(set) var level = 2
    private(set) var hexesCleared = 0
    private(set) var hexesThisLevel = 0
    private(set) var activeColors = Progression.initialColors
    /// Every seat's dial, by seat.
    private(set) var cursors: [Cursor]
    /// Each seat's turn still being animated, by seat.
    private(set) var dialTurns: [DialTurn?]
    /// Seats whose dial has left the board; they hold nothing and block nothing.
    private(set) var absent: Set<Int> = []
    /// Seconds left in sprint mode; nil in other modes.
    private(set) var sprintTimeRemaining: Double?
    /// The colours the latest swap power changed, for saying so on screen.
    private(set) var lastSwap: ColorSwap?

    private var spawnInterval: Double
    private var spawnTimer = 0.0
    private var fallTimer = 0.0
    private var nextPieceID = 0
    private var rng: any RandomNumberGenerator

    /// One seat per dial in `dials`, which mustn't overlap.
    init(mode: Mode, speed: Speed, assisted: Bool = false, rng: any RandomNumberGenerator, dials: [Vertex]) {
        precondition(!dials.isEmpty && dials.allSatisfy(Grid.isDial), "every seat needs a dial")
        self.mode = mode
        self.speed = speed
        self.assisted = assisted
        stepTime = Game.fallStep * speed.pace
        spawnInterval = Progression.spawnInterval(level: 2, assisted: assisted) * speed.pace
        self.rng = rng
        cursors = dials.map { Cursor(vertex: $0, stickyJ: $0.j) }
        dialTurns = Array(repeating: nil, count: dials.count)
        sprintTimeRemaining = mode == .sprint ? Game.sprintLength : nil
        precondition(dials.indices.allSatisfy { fits(dials[$0], for: $0) }, "dials overlap")
    }

    /// How far (0…1) pieces have moved from their `from` cell toward their current one.
    var fallProgress: Double { min(1, fallTimer / stepTime) }

    /// Advance the game by `dt` seconds.
    mutating func update(by dt: Double) -> [GameEvent] {
        var events: [GameEvent] = []
        guard phase == .playing else { return events }

        if let remaining = sprintTimeRemaining {
            sprintTimeRemaining = max(0, remaining - dt)
            if remaining - dt <= 0 {
                endGame(&events)
                return events
            }
        }

        for seat in dialTurns.indices {
            guard var turn = dialTurns[seat] else { continue }
            turn.elapsed += dt
            dialTurns[seat] = turn.elapsed >= Game.rotateTime ? nil : turn
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
        while fallTimer >= stepTime {
            if steps == 3 { // fell far behind (app was suspended); don't fast-forward
                fallTimer = 0
                break
            }
            steps += 1
            fallTimer -= stepTime
            Dropper.stepGravity(&board, heldCells: heldCells)

            spawnTimer -= stepTime
            if spawnTimer <= 0 {
                spawnTimer += spawnInterval
                let result = Dropper.spawn(into: &board, colors: activeColors, id: nextPieceID,
                                           gentle: assisted, using: &rng)
                switch result {
                case .full where assisted && !rescued:
                    // Once a game, a new player's full bin drains instead of ending
                    rescued = true
                    apply(.drain, &events)
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
        let hexes = Dial.findHexes(board, heldCells: heldCells)
        guard !hexes.isEmpty else { return }

        var powers: [Power] = []
        for hex in hexes {
            for cell in hex.cells where board[cell]?.isClearing == false {
                board[cell]?.clearTime = Game.clearTime
                if let power = board[cell]?.power { powers.append(power) }
            }
        }

        let points = Int((Double(Progression.score(hexes: hexes.count, level: level)) * speed.pointsMultiplier).rounded())
        score += points
        hexesCleared += hexes.count
        hexesThisLevel += hexes.count
        events.append(.clear(hexes: hexes, points: points))

        for power in powers { apply(power, &events) }

        if hexesThisLevel >= Progression.hexesPerLevel && activeColors.count < Progression.colorCount {
            activeColors.append(activeColors.count)
            hexesThisLevel -= Progression.hexesPerLevel
            level = activeColors.count
            spawnInterval = Progression.spawnInterval(level: level, assisted: assisted) * speed.pace
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
            lastSwap = ColorSwap(from: from, to: to)
        case .swap:
            break
        }
        events.append(.power(power))
    }

    private mutating func endGame(_ events: inout [GameEvent]) {
        phase = .gameOver
        events.append(.gameOver(won: won))
    }

    // MARK: - Dials

    /// Turn a seat's dial.
    mutating func rotate(_ seat: Int, _ direction: RotationDirection) -> [GameEvent] {
        guard !absent.contains(seat) else { return [] }
        let vertex = cursors[seat].vertex
        let pieceIDs = Set(Grid.dialCells(vertex).compactMap { board[$0]?.id })
        guard phase == .playing, Dial.rotate(&board, at: vertex, direction: direction) else { return [] }
        dialTurns[seat] = DialTurn(vertex: vertex, direction: direction, pieceIDs: pieceIDs, elapsed: 0)
        return [.rotate]
    }

    /// Gravity is suspended in the six cells under every dial on the board.
    private var heldCells: Set<Cell> {
        var held = Set<Cell>()
        for seat in cursors.indices where !absent.contains(seat) {
            held.formUnion(Grid.dialCells(cursors[seat].vertex))
        }
        return held
    }

    /// Whether a seat's dial is holding up a piece that would fall without it.
    func isHolding(_ seat: Int) -> Bool {
        guard !absent.contains(seat) else { return false }
        return Grid.dialCells(cursors[seat].vertex).contains { cell in
            guard let piece = board[cell], !piece.isClearing else { return false }
            return Dropper.nextMove(board, from: cell) != nil
        }
    }

    /// Whether a seat's dial could sit on `vertex` without sharing a cell with another dial.
    func fits(_ vertex: Vertex, for seat: Int) -> Bool {
        let cells = Set(Grid.dialCells(vertex))
        return cursors.indices.allSatisfy { other in
            other == seat || absent.contains(other) || cells.isDisjoint(with: Grid.dialCells(cursors[other].vertex))
        }
    }

    /// Put a seat's dial on a vertex, if it's free.
    mutating func moveCursor(_ seat: Int, to vertex: Vertex) {
        guard phase == .playing, !absent.contains(seat), Grid.isDial(vertex), fits(vertex, for: seat) else { return }
        cursors[seat] = Cursor(vertex: vertex, stickyJ: vertex.j)
    }

    /// Nudge a seat's dial one step. On screen the lattice is turned 90°:
    /// up/down move along a lattice row (j ∓ 2), and left/right step to the
    /// neighbouring row, drifting back toward the height you were last at.
    /// Another dial in the way blocks the move.
    mutating func moveCursor(_ seat: Int, _ direction: Direction) {
        guard phase == .playing, !absent.contains(seat) else { return }
        let cursor = cursors[seat]
        let (k, j, sticky) = (cursor.vertex.k, cursor.vertex.j, cursor.stickyJ)
        switch direction {
        case .up, .down:
            let target = Vertex(k: k, j: j + (direction == .up ? -2 : 2))
            if Grid.isDial(target) && fits(target, for: seat) {
                cursors[seat] = Cursor(vertex: target, stickyJ: target.j)
            }
        case .left, .right:
            let nk = k + (direction == .left ? 1 : -1)
            let best = [j - 1, j + 1]
                .map { Vertex(k: nk, j: $0) }
                .filter { Grid.isDial($0) && fits($0, for: seat) }
                .min { abs($0.j - sticky) < abs($1.j - sticky) }
            if let best { cursors[seat] = Cursor(vertex: best, stickyJ: sticky) }
        }
    }

    /// Lift a seat's dial off the board for good: it stops holding triangles
    /// up and stops blocking the other dials.
    mutating func removeSeat(_ seat: Int) {
        absent.insert(seat)
        dialTurns[seat] = nil
    }

    mutating func togglePause() {
        switch phase {
        case .playing: phase = .paused
        case .paused: phase = .playing
        case .gameOver: break
        }
    }

    /// Test hook: replace the board wholesale, so tests can set up a position.
    mutating func setBoardForTesting(_ board: Board) {
        self.board = board
    }

    // MARK: - Snapshots (online co-op)

    /// Everything the screen shows, for drawing this game on another device.
    var snapshot: CoopSnapshot {
        CoopSnapshot(
            mode: mode, speed: speed, phase: phase, won: won, score: score, level: level,
            hexesCleared: hexesCleared, hexesThisLevel: hexesThisLevel, activeColors: activeColors,
            sprintTimeRemaining: sprintTimeRemaining, fallProgress: fallProgress, board: board,
            dials: cursors.indices.map { absent.contains($0) ? nil : cursors[$0] },
            dialTurns: dialTurns)
    }

    /// Take on a snapshot's state, for a copy that's only drawn and never
    /// updated. Its spawn clock and generator are left alone, since a copy
    /// never spawns. Ignored if the snapshot has a different number of seats.
    mutating func restore(_ snapshot: CoopSnapshot) {
        guard snapshot.dials.count == cursors.count, snapshot.dialTurns.count == cursors.count else { return }
        board = snapshot.board
        phase = snapshot.phase
        won = snapshot.won
        score = snapshot.score
        level = snapshot.level
        hexesCleared = snapshot.hexesCleared
        hexesThisLevel = snapshot.hexesThisLevel
        activeColors = snapshot.activeColors
        sprintTimeRemaining = snapshot.sprintTimeRemaining
        fallTimer = snapshot.fallProgress * stepTime
        absent = []
        for (seat, cursor) in snapshot.dials.enumerated() {
            if let cursor { cursors[seat] = cursor } else { absent.insert(seat) }
        }
        dialTurns = snapshot.dialTurns
    }

    /// For a copy between snapshots: the fall and turn animations run on, but
    /// nothing moves, clears, or spawns.
    mutating func animate(by dt: Double) {
        guard phase == .playing else { return }
        fallTimer = min(stepTime, fallTimer + dt)
        for seat in dialTurns.indices {
            guard var turn = dialTurns[seat] else { continue }
            turn.elapsed += dt
            dialTurns[seat] = turn.elapsed >= Game.rotateTime ? nil : turn
        }
    }

    /// Keep a seat's turn as far along as `previous` had got, if it's the same turn.
    mutating func continueTurn(_ seat: Int, from previous: DialTurn?) {
        guard let previous, var turn = dialTurns[seat],
              turn.vertex == previous.vertex, turn.direction == previous.direction else { return }
        turn.elapsed = max(turn.elapsed, previous.elapsed)
        dialTurns[seat] = turn
    }
}
