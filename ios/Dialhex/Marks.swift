// Marks.swift — Piece shapes and the marks inset in them (port of renderer.js drawMark)
//
// Every mark has three-fold symmetry and is built from the triangle's own
// corners, so it survives the dial's 60° turn without jumping. Marks come back
// as one filled path (strokes already outlined), so SpriteKit and SwiftUI can
// both just fill it.

import CoreGraphics
import DialhexCore

enum Marks {
    /// A closed polygon through `points`.
    static func polygon(_ points: [CGPoint]) -> CGPath {
        let path = CGMutablePath()
        path.addLines(between: points)
        path.closeSubpath()
        return path
    }

    static func centroid(_ points: [CGPoint]) -> CGPoint {
        CGPoint(x: points.map(\.x).reduce(0, +) / CGFloat(points.count),
                y: points.map(\.y).reduce(0, +) / CGFloat(points.count))
    }

    /// `points` pulled toward (factor < 1) or pushed away from their centroid.
    static func scaled(_ points: [CGPoint], by factor: CGFloat) -> [CGPoint] {
        let mid = centroid(points)
        return points.map { lerp(mid, $0, factor) }
    }

    /// The mark for one piece.
    /// - Parameters:
    ///   - corners: the triangle's three corners
    ///   - lineWidth: the brand's line weight at the current board scale
    ///   - scale: the skin's mark scale (1 normally)
    static func path(_ mark: Mark, corners: [CGPoint], lineWidth: CGFloat, scale s: CGFloat = 1) -> CGPath {
        let mid = centroid(corners)
        // Inradius: distance from the centre to an edge (half the distance to a corner)
        let r = hypot(corners[0].x - mid.x, corners[0].y - mid.y) / 2
        let width = min(lineWidth, r * 0.32)
        let toward = { (f: CGFloat) in corners.map { lerp(mid, $0, f * s) } }

        let fill = CGMutablePath()
        let stroke = CGMutablePath()
        func dot(_ p: CGPoint, _ radius: CGFloat) {
            fill.addEllipse(in: CGRect(x: p.x - radius, y: p.y - radius, width: radius * 2, height: radius * 2))
        }
        func ring(_ radius: CGFloat) {
            stroke.addEllipse(in: CGRect(x: mid.x - radius, y: mid.y - radius, width: radius * 2, height: radius * 2))
        }

        switch mark {
        case .dot:
            dot(mid, r * 0.34 * s)
        case .ring:
            ring(r * 0.46 * s)
        case .target:
            ring(r * 0.56 * s)
            dot(mid, r * 0.16 * s)
        case .spokes:
            for p in toward(0.42) {
                stroke.move(to: mid)
                stroke.addLine(to: p)
            }
        case .frame:
            stroke.addPath(polygon(toward(0.4)))
        case .trio:
            for p in toward(0.42) { dot(p, r * 0.17 * s) }
        case .corners:
            // A small solid triangle tucked into each corner, pointing out. Placed
            // without the mark scale, and capped, so they never reach the piece's edge.
            let k = min(0.22 * s, 0.28)
            for p in corners.map({ lerp(mid, $0, 0.52) }) {
                fill.addPath(polygon(corners.map { CGPoint(x: p.x + ($0.x - mid.x) * k, y: p.y + ($0.y - mid.y) * k) }))
            }
        case .tri:
            // Solid triangle pointing the other way
            fill.addPath(polygon(toward(-0.32)))
        }

        if !stroke.isEmpty {
            fill.addPath(stroke.copy(strokingWithWidth: width, lineCap: .square, lineJoin: .miter, miterLimit: 10))
        }
        return fill
    }

    /// One triangle of the logo.
    struct LogoCell {
        /// Which letter it belongs to, counting across every line (H E X G E N = 0…5).
        let letter: Int
        /// Its three corners, before the gap between triangles is taken out.
        let corners: [CGPoint]
    }

    /// The logo's cells in its own grid: column j (left to right) and row k (half a
    /// side apart, top down), on the board's sideways lattice. A cell points right
    /// when j + k is even.
    private static let logoGrid: (cells: [(j: Int, k: Int, letter: Int)], columns: Int, rows: Int) = {
        let logo = Brand.tokens.logo
        let words = logo.lines ?? [logo.word]
        let height = words.flatMap { $0.map { logo.glyphs[String($0)]?.count ?? 0 } }.max() ?? 0
        var lineStep = height + logo.lineGap
        lineStep += lineStep % 2 // an even step keeps the next line's triangles pointing the same ways
        var lines: [[(j: Int, k: Int, letter: Int)]] = []
        var widths: [Int] = []
        var letterIndex = 0
        for (lineIndex, word) in words.enumerated() {
            var cells: [(j: Int, k: Int, letter: Int)] = []
            var offset = 0
            var width = 0
            for letter in word {
                let rows = logo.glyphs[String(letter)] ?? []
                for (k, row) in rows.enumerated() {
                    for (j, mark) in row.enumerated() where mark == "#" {
                        cells.append((j + offset, k + lineIndex * lineStep, letterIndex))
                    }
                }
                width = offset + (rows.map(\.count).max() ?? 0)
                offset = width + logo.gap
                offset += offset % 2 // every glyph on an even column, so its triangles keep their directions
                letterIndex += 1
            }
            lines.append(cells)
            widths.append(width)
        }
        let columns = widths.max() ?? 0
        // Centre each line, by an even shift so its triangles keep their directions
        let cells = zip(lines, widths).flatMap { line, width in
            let shift = (columns - width) / 2 / 2 * 2
            return line.map { (j: $0.j + shift, k: $0.k, letter: $0.letter) }
        }
        return (cells, columns, (words.count - 1) * lineStep + height)
    }()

    /// The logo with its grid's top-left corner at `origin`, at triangle side `side`.
    private static func logoCells(side: CGFloat, origin: CGPoint) -> [LogoCell] {
        let width = side * CGFloat(Grid.rowHeight) // one column
        return logoGrid.cells.map { j, k, letter in
            let left = origin.x + CGFloat(j) * width
            let right = left + width
            let top = origin.y + CGFloat(k) * side / 2
            let corners = (j + k) % 2 == 0 // points right
                ? [CGPoint(x: left, y: top), CGPoint(x: left, y: top + side), CGPoint(x: right, y: top + side / 2)]
                : [CGPoint(x: right, y: top), CGPoint(x: right, y: top + side), CGPoint(x: left, y: top + side / 2)]
            return LogoCell(letter: letter, corners: corners)
        }
    }

    /// The logo's size at triangle side `side`.
    static func logoSize(side: CGFloat) -> CGSize {
        CGSize(width: CGFloat(logoGrid.columns) * side * CGFloat(Grid.rowHeight),
               height: CGFloat(logoGrid.rows + 1) * side / 2)
    }

    /// How many half-side rows the logo sits above the middle of the bin, leaving the
    /// bin's lower bowl for play. Even, so the logo stays on the lattice.
    static let logoLiftInBin = 2

    /// The logo laid into a bin centred on `center` with board triangles of side
    /// `boardSide` (y down): half-size cells on the board's own lattice, centred
    /// across it and lifted toward the top, inside its full-width middle band.
    static func logoInBin(center: CGPoint, boardSide: CGFloat) -> (cells: [LogoCell], side: CGFloat) {
        let side = boardSide / 2
        let (j0, k0) = logoBinOrigin
        let width = side * CGFloat(Grid.rowHeight)
        // The bin is 4·size half-size columns across, centred on `center`
        let origin = CGPoint(x: center.x - CGFloat(2 * Grid.size - j0) * width, y: center.y + CGFloat(k0) * side / 2)
        return (logoCells(side: side, origin: origin), side)
    }

    /// Where the bottom of the logo sits in a bin, in board triangle sides below its
    /// middle (lattice x): play shown on the menu stays below this.
    static let logoBottomInBin: Double = {
        // Rows are a quarter of a board side apart (half a logo side); the last row reaches one row lower
        Double(logoBinOrigin.k0 + logoGrid.rows + 1) / 4
    }()

    /// Where the logo's grid starts on a bin's half-size lattice: column j0 counted from
    /// the bin's left edge, row k0 from its middle. Centred across, lifted toward the top,
    /// and on a cell that points right when column + row is even (the logo's own rule).
    private static let logoBinOrigin: (j0: Int, k0: Int) = {
        let j0 = (4 * Grid.size - logoGrid.columns) / 2
        var k0 = -(logoGrid.rows + 1) / 2 - logoLiftInBin
        if (j0 + k0) % 2 != 0 { k0 -= 1 }
        return (j0, k0)
    }()

    /// The logo fitted inside `width` (cells at most `maxSide`) and centred on `center`.
    static func logoFitted(width maxWidth: CGFloat, center: CGPoint, maxSide: CGFloat = 26) -> (cells: [LogoCell], side: CGFloat) {
        let side = min(maxWidth / (CGFloat(logoGrid.columns) * CGFloat(Grid.rowHeight)), maxSide)
        let size = logoSize(side: side)
        return (logoCells(side: side, origin: CGPoint(x: center.x - size.width / 2, y: center.y - size.height / 2)), side)
    }
}

private func lerp(_ a: CGPoint, _ b: CGPoint, _ t: CGFloat) -> CGPoint {
    CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
}
