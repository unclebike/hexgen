// DemoPlayer.swift — A simple auto-player for the game running behind the menu
//
// Every so often it tries every dial and turn on a copy of the game, takes the
// one that clears the most hexes (or, failing that, gathers the most same-
// coloured triangles around a vertex), glides the dial there, and turns it.
// It's greedy and a little noisy on purpose, so it plays like a person.

import DialhexCore

struct DemoPlayer {
    /// Seconds between decisions, and between a move and its turn, so the dial is seen travelling.
    private static let thinkTime = 0.42
    private static let moveTime = 0.14

    /// Only dials wholly below this lattice x (down the screen) are played, so the
    /// demo keeps clear of the menu's logo.
    var floor: Double
    /// Stretches the pauses between moves; the first-game walkthrough plays slower,
    /// so a new player can follow each turn.
    var pace: Double

    init(floor: Double = -.infinity, pace: Double = 1) {
        self.floor = floor
        self.pace = pace
    }

    /// Turns still to play at the chosen dial.
    private var pending: [RotationDirection] = []
    private var timer = 0.0

    /// Advance the demo by `dt`, playing a move when one is due. Returns the game's events.
    mutating func update(_ game: inout Game, by dt: Double) -> [GameEvent] {
        var events = game.update(by: dt)
        guard game.phase == .playing else { return events }
        timer -= dt
        guard timer <= 0 else { return events }

        if let turn = pending.first {
            pending.removeFirst()
            events += game.rotate(turn)
            timer = pending.isEmpty ? Self.thinkTime * pace : Game.rotateTime + 0.04 * pace
        } else if let (dial, turns) = Self.bestMove(in: game, floor: floor) {
            game.moveCursor(to: dial)
            pending = turns
            timer = Self.moveTime * pace
        } else {
            timer = Self.thinkTime * pace
        }
        return events
    }

    /// The best dial and the turns to play there, or nil on an empty board.
    private static func bestMove(in game: Game, floor: Double) -> (Vertex, [RotationDirection])? {
        let options: [[RotationDirection]] = [[.clockwise], [.counterClockwise], [.clockwise, .clockwise]]
        var best: (score: Double, dial: Vertex, turns: [RotationDirection])?
        // A dial reaches one side above its vertex
        for dial in Grid.dials where Grid.position(of: dial).x - 1 >= floor {
            // Only dials holding enough triangles to be worth turning
            let filled = Grid.dialCells(dial).filter { game.board[$0] != nil }.count
            guard filled >= 3 else { continue }
            for turns in options {
                var trial = game
                trial.moveCursor(to: dial)
                for turn in turns { _ = trial.rotate(turn) }
                // A zero-length step runs clear detection without moving anything
                let cleared = trial.update(by: 0).reduce(0) { total, event in
                    if case .clear(let hexes, _) = event { return total + hexes.count }
                    return total
                }
                let score = Double(cleared) * 1000 + clustering(trial.board) + .random(in: 0..<6)
                if score > (best?.score ?? -.infinity) { best = (score, dial, turns) }
            }
        }
        return best.map { ($0.dial, $0.turns) }
    }

    /// How close the board is to hexes: for every dial, the square of its
    /// largest group of one colour.
    private static func clustering(_ board: Board) -> Double {
        var total = 0.0
        var counts = [Int](repeating: 0, count: Progression.colorCount)
        for dial in Grid.dials {
            for i in counts.indices { counts[i] = 0 }
            for cell in Grid.dialCells(dial) {
                if let piece = board[cell], !piece.isClearing, counts.indices.contains(piece.color) {
                    counts[piece.color] += 1
                }
            }
            let most = Double(counts.max() ?? 0)
            total += most * most
        }
        return total
    }
}
