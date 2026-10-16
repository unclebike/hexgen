// Board.swift — Pieces, gravity, spawning, turning, and hex detection
//
// On screen the bin stands on a vertex, so the lattice's rows are vertical
// columns and "down" is +c along a row. A triangle falls straight down its
// column, two cells at a time so it keeps its shape, and lands as soon as the
// cell below it is taken. Only the bin's slanted bottom walls make it slide:
// at the foot of a column it steps into the next column toward the bottom
// point and carries on falling.

public enum Power: Sendable, Equatable {
    case drain // empties the bottom of the bin
    case swap  // turns every triangle of one colour into another
}

public struct Piece: Sendable, Equatable, Identifiable {
    /// Stable for the piece's whole life, so a renderer can track it.
    public let id: Int
    public var color: Int
    public var power: Power?
    /// The cell this piece left on the last fall step, for animating the move.
    public var from: Cell?
    /// Seconds left of the clear flash; zero when not clearing.
    public var clearTime: Double = 0

    public var isClearing: Bool { clearTime > 0 }
}

/// A completed Hex: six same-coloured, resting triangles around one vertex.
public struct Hex: Sendable, Equatable {
    public var center: Vertex
    public var color: Int
    public var cells: [Cell]
}

public enum SpawnResult: Sendable, Equatable {
    case spawned
    case wait // every column top is blocked by a triangle that is still falling
    case full // every column is stacked to its top
}

public typealias Board = [Cell: Piece]

public enum Dropper {
    static let powerChance = 0.04

    /// Column r, top to bottom.
    static let columns: [[Cell]] = (0..<Grid.rows).map { r in
        Grid.cells.filter { $0.r == r }.sorted { $0.c < $1.c }
    }

    /// The top cell of every column: where new triangles enter.
    public static let spawnCells: [Cell] = columns.map { $0[0] }

    /// Bottom of each column first, so a falling stack moves together; ties go
    /// top row first, the order the JS stable sort gives.
    private static let gravityOrder = Grid.cells.sorted { $0.c != $1.c ? $0.c > $1.c : $0.r < $1.r }

    private static func isOpen(_ board: Board, _ cell: Cell) -> Bool {
        Grid.isCell(cell) && board[cell] == nil
    }

    /// Where the piece at `cell` moves next, or nil if it has landed.
    static func nextMove(_ board: Board, from cell: Cell) -> Cell? {
        let (r, c) = (cell.r, cell.c)
        let below = Cell(r: r, c: c + 1)
        if Grid.isCell(below) {
            if board[below] != nil { return nil } // resting on the triangle below
            // Fall a full edge (two cells, same shape), or one cell into the last gap
            let twoBelow = Cell(r: r, c: c + 2)
            return isOpen(board, twoBelow) ? twoBelow : below
        }
        // The foot of the column, against a slanted wall: slide one column
        // inward, into the open cell next to us that is lower down
        let inward = r < Grid.size ? r + 1 : r - 1
        let here = Grid.center(of: cell)
        return (c - 1...c + 2)
            .map { Cell(r: inward, c: $0) }
            .filter { isOpen(board, $0) && Grid.center(of: $0).x > here.x + 1e-9 }
            .min { Grid.distanceSquared(Grid.center(of: $0), here) < Grid.distanceSquared(Grid.center(of: $1), here) }
    }

    /// A piece is resting once it has landed.
    public static func isResting(_ board: Board, _ cell: Cell) -> Bool {
        nextMove(board, from: cell) == nil
    }

    /// Move every loose piece one step. Each piece records where it came from.
    static func stepGravity(_ board: inout Board) {
        for cell in board.keys { board[cell]?.from = nil }
        var moved = Set<Int>()
        for cell in gravityOrder {
            guard let piece = board[cell], !moved.contains(piece.id), !piece.isClearing,
                  let target = nextMove(board, from: cell) else { continue }
            board[cell] = nil
            var fallen = piece
            fallen.from = cell
            board[target] = fallen
            moved.insert(piece.id)
        }
    }

    /// Drop a new triangle into the top of a random open column; a full
    /// column just stops taking new ones.
    static func spawn(
        into board: inout Board, colors: [Int], id: Int, using rng: inout some RandomNumberGenerator
    ) -> SpawnResult {
        let open = spawnCells.filter { board[$0] == nil }
        guard let cell = open.randomElement(using: &rng) else {
            return spawnCells.allSatisfy { isResting(board, $0) } ? .full : .wait
        }
        let hasPower = board.values.contains { $0.power != nil }
        let color = colors.randomElement(using: &rng)!
        var power: Power?
        if !hasPower && Double.random(in: 0..<1, using: &rng) < powerChance {
            power = Bool.random(using: &rng) ? .drain : .swap
        }
        // Enter from just above the bin
        board[cell] = Piece(id: id, color: color, power: power, from: Cell(r: cell.r, c: cell.c - 2))
        return .spawned
    }
}

public enum Dial {
    /// Turn the six cells around a vertex one step. Returns false (and changes
    /// nothing) if one of them is mid-clear. Because dials overlap, turning one
    /// moves triangles into neighbouring hexes.
    static func rotate(_ board: inout Board, at v: Vertex, direction: RotationDirection) -> Bool {
        let cells = Grid.dialCells(v)
        let pieces = cells.map { board[$0] }
        if pieces.contains(where: { $0?.isClearing == true }) { return false }
        let step = direction.rawValue
        for (i, cell) in cells.enumerated() {
            var piece = pieces[(i - step + 6) % 6]
            piece?.from = nil
            board[cell] = piece
        }
        return true
    }

    /// Every dial position holding a completed Hex. Only resting triangles count.
    static func findHexes(_ board: Board) -> [Hex] {
        Grid.dials.compactMap { v in
            let cells = Grid.dialCells(v)
            guard let first = board[cells[0]] else { return nil }
            let complete = cells.allSatisfy { cell in
                guard let p = board[cell] else { return false }
                return p.color == first.color && !p.isClearing && Dropper.isResting(board, cell)
            }
            return complete ? Hex(center: v, color: first.color, cells: cells) : nil
        }
    }
}
