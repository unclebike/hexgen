// Hints.swift — Spotting a hex the player could finish with one turn
//
// An assisted game marks a dial where a single turn, either way, completes a
// hex. It plays each turn on a copy of the board by the game's own rules: the
// dial holds its six cells, and every other cell of the new hex must be resting.

public enum Hints {
    /// A dial where one turn completes a hex, the closest to `cursor` if there
    /// are several (the cursor's own, when it qualifies). Nil if there's none.
    public static func oneTurnFromHex(on board: Board, near cursor: Vertex) -> Vertex? {
        let here = Grid.position(of: cursor)
        return Grid.dials
            .filter { finishesHex(board, at: $0) }
            .min { Grid.distanceSquared(Grid.position(of: $0), here) < Grid.distanceSquared(Grid.position(of: $1), here) }
    }

    /// Whether turning the dial at `vertex` one step, either way, completes a
    /// hex that isn't there already.
    public static func finishesHex(_ board: Board, at vertex: Vertex) -> Bool {
        let cells = Grid.dialCells(vertex)
        // A turn only moves what's in its six cells; it takes at least two to make anything new
        guard cells.count(where: { board[$0] != nil }) >= 2 else { return false }
        let held = Set(cells)
        // A new hex has to take in one of the turned cells, so only the dials touching them can make one
        let nearby = touching[vertex] ?? []
        let before = Set(nearby.filter { Dial.hex(board, at: $0, heldCells: held) != nil })
        return [RotationDirection.clockwise, .counterClockwise].contains { direction in
            var trial = board
            guard Dial.rotate(&trial, at: vertex, direction: direction) else { return false }
            return nearby.contains { !before.contains($0) && Dial.hex(trial, at: $0, heldCells: held) != nil }
        }
    }

    /// For every dial, the dials that share a cell with it (itself included).
    private static let touching: [Vertex: [Vertex]] = Dictionary(uniqueKeysWithValues: Grid.dials.map { v in
        let cells = Set(Grid.dialCells(v))
        return (v, Grid.dials.filter { !cells.isDisjoint(with: Grid.dialCells($0)) })
    })
}
