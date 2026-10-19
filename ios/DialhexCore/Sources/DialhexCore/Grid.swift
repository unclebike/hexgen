// Grid.swift — Triangular lattice inside a hexagonal bin
//
// The bin is a hexagon of side `Grid.size` (in triangle edges) tiled by
// 6·size² equilateral triangles laid out in rows. Units: triangle side = 1,
// origin at the centre of the bin, y pointing down.
//
//   Cell (r, c)   — row r (0 = top), centred at x = c/2. It points up when
//                   r + c + size is even, and down otherwise.
//   Vertex (k, j) — on the line between rows k-1 and k, at x = j/2.
//
// The six cells around an interior vertex form a small hexagon. That is the
// dial the player turns, and six same-coloured cells around one vertex make a
// Hex. Every interior vertex can host one, so hexes overlap.
//
// On screen the lattice is turned 90° so the bin stands on a vertex: lattice
// x runs down the screen and lattice y runs right to left.

public typealias LatticePoint = SIMD2<Double>

public struct Cell: Hashable, Sendable {
    public var r: Int
    public var c: Int
    public init(r: Int, c: Int) { self.r = r; self.c = c }
}

public struct Vertex: Hashable, Sendable, Codable {
    public var k: Int
    public var j: Int
    public init(k: Int, j: Int) { self.k = k; self.j = j }
}

public enum Grid {
    public static let size = 6
    public static let rows = size * 2
    public static let rowHeight = 3.0.squareRoot() / 2

    private static let epsilon = 1e-9
    private static func parity(_ n: Int) -> Int { ((n % 2) + 2) % 2 }

    public static func isUp(_ cell: Cell) -> Bool { parity(cell.r + cell.c + size) == 0 }

    public static func position(of v: Vertex) -> LatticePoint {
        LatticePoint(Double(v.j) / 2, Double(v.k - size) * rowHeight)
    }

    /// The three corners of a cell.
    public static func vertices(of cell: Cell) -> [LatticePoint] {
        let (r, c) = (cell.r, cell.c)
        return isUp(cell)
            ? [Vertex(k: r, j: c), Vertex(k: r + 1, j: c + 1), Vertex(k: r + 1, j: c - 1)].map(position)
            : [Vertex(k: r, j: c - 1), Vertex(k: r, j: c + 1), Vertex(k: r + 1, j: c)].map(position)
    }

    /// Centroid of a cell. Also defined off the board, for the spawn animation.
    public static func center(of cell: Cell) -> LatticePoint {
        LatticePoint(Double(cell.c) / 2, (Double(cell.r - size) + (isUp(cell) ? 2.0 / 3 : 1.0 / 3)) * rowHeight)
    }

    private static func insideBin(_ p: LatticePoint) -> Bool {
        abs(p.y) <= Double(size) * rowHeight + epsilon
            && abs(p.x) + abs(p.y) / 3.0.squareRoot() <= Double(size) + epsilon
    }

    /// Every cell in the bin, top row first.
    public static let cells: [Cell] = (0..<rows).flatMap { r in
        (-2 * size...2 * size).map { Cell(r: r, c: $0) }.filter { vertices(of: $0).allSatisfy(insideBin) }
    }
    private static let cellSet = Set(cells)
    public static func isCell(_ cell: Cell) -> Bool { cellSet.contains(cell) }

    /// The six cells around a vertex, clockwise from top-left.
    public static func dialCells(_ v: Vertex) -> [Cell] {
        let (k, j) = (v.k, v.j)
        return [
            Cell(r: k - 1, c: j - 1), Cell(r: k - 1, c: j), Cell(r: k - 1, c: j + 1),
            Cell(r: k, c: j + 1), Cell(r: k, c: j), Cell(r: k, c: j - 1),
        ]
    }

    /// Every vertex whose six surrounding cells are all inside the bin.
    public static let dials: [Vertex] = (1..<rows).flatMap { k in
        (-2 * size...2 * size)
            .filter { parity(k + $0 + size) == 0 }
            .map { Vertex(k: k, j: $0) }
            .filter { dialCells($0).allSatisfy(isCell) }
    }
    private static let dialSet = Set(dials)
    public static func isDial(_ v: Vertex) -> Bool { dialSet.contains(v) }

    /// Outer corners of the dial around a vertex, clockwise from the right.
    public static func dialOutline(_ v: Vertex) -> [LatticePoint] {
        let (k, j) = (v.k, v.j)
        return [
            Vertex(k: k, j: j + 2), Vertex(k: k + 1, j: j + 1), Vertex(k: k + 1, j: j - 1),
            Vertex(k: k, j: j - 2), Vertex(k: k - 1, j: j - 1), Vertex(k: k - 1, j: j + 1),
        ].map(position)
    }

    /// The six corners of the bin itself.
    public static let binOutline: [LatticePoint] = {
        let s = Double(size)
        let h = s * rowHeight
        return [LatticePoint(s, 0), LatticePoint(s / 2, h), LatticePoint(-s / 2, h),
                LatticePoint(-s, 0), LatticePoint(-s / 2, -h), LatticePoint(s / 2, -h)]
    }()

    /// Nearest dial to a point, or nil if none is within `maxDistance`.
    public static func nearestDial(to p: LatticePoint, within maxDistance: Double = .infinity) -> Vertex? {
        let best = dials.min { distanceSquared(position(of: $0), p) < distanceSquared(position(of: $1), p) }
        guard let best, distanceSquared(position(of: best), p) < maxDistance * maxDistance else { return nil }
        return best
    }

    static func distanceSquared(_ a: LatticePoint, _ b: LatticePoint) -> Double {
        let d = a - b
        return (d * d).sum()
    }
}
