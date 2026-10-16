// GridTests.swift — The lattice, checked against grid.js and dropper.js

import XCTest
@testable import DialhexCore

final class GridTests: XCTestCase {
    func testCellAndDialCounts() {
        // JS: CELLS.length, DIALS.length
        XCTAssertEqual(Grid.cells.count, 216)
        XCTAssertEqual(Grid.dials.count, 91)
        XCTAssertEqual(Grid.cells.count, 6 * Grid.size * Grid.size)
    }

    func testCellsAreRowMajorAndMatchJS() {
        // JS: every row r is contiguous from -w to w, with these half-widths
        let halfWidths = [6, 7, 8, 9, 10, 11, 11, 10, 9, 8, 7, 6]
        let expected = (0..<12).flatMap { r in (-halfWidths[r]...halfWidths[r]).map { Cell(r: r, c: $0) } }
        XCTAssertEqual(Grid.cells, expected)
        XCTAssertEqual(Array(Grid.cells.prefix(3)), [cell(0, -6), cell(0, -5), cell(0, -4)])
        XCTAssertEqual(Array(Grid.cells.suffix(3)), [cell(11, 4), cell(11, 5), cell(11, 6)])
        XCTAssertTrue(Grid.isCell(cell(5, -11)))
        XCTAssertFalse(Grid.isCell(cell(0, 7)))
        XCTAssertFalse(Grid.isCell(cell(12, 0)))
        XCTAssertFalse(Grid.isCell(cell(-1, 0)))
    }

    func testDialsMatchJSOrder() {
        // JS: DIALS, in order
        let expected: [(Int, Int)] = [
            (1, -5), (1, -3), (1, -1), (1, 1), (1, 3), (1, 5),
            (2, -6), (2, -4), (2, -2), (2, 0), (2, 2), (2, 4), (2, 6),
            (3, -7), (3, -5), (3, -3), (3, -1), (3, 1), (3, 3), (3, 5), (3, 7),
            (4, -8), (4, -6), (4, -4), (4, -2), (4, 0), (4, 2), (4, 4), (4, 6), (4, 8),
            (5, -9), (5, -7), (5, -5), (5, -3), (5, -1), (5, 1), (5, 3), (5, 5), (5, 7), (5, 9),
            (6, -10), (6, -8), (6, -6), (6, -4), (6, -2), (6, 0), (6, 2), (6, 4), (6, 6), (6, 8), (6, 10),
            (7, -9), (7, -7), (7, -5), (7, -3), (7, -1), (7, 1), (7, 3), (7, 5), (7, 7), (7, 9),
            (8, -8), (8, -6), (8, -4), (8, -2), (8, 0), (8, 2), (8, 4), (8, 6), (8, 8),
            (9, -7), (9, -5), (9, -3), (9, -1), (9, 1), (9, 3), (9, 5), (9, 7),
            (10, -6), (10, -4), (10, -2), (10, 0), (10, 2), (10, 4), (10, 6),
            (11, -5), (11, -3), (11, -1), (11, 1), (11, 3), (11, 5),
        ]
        XCTAssertEqual(Grid.dials, expected.map { Vertex(k: $0.0, j: $0.1) })
        // JS: isDial(6,0), isDial(6,1), isDial(1,-3), isDial(0,0), isDial(11,3)
        XCTAssertTrue(Grid.isDial(vertex(6, 0)))
        XCTAssertFalse(Grid.isDial(vertex(6, 1)))
        XCTAssertTrue(Grid.isDial(vertex(1, -3)))
        XCTAssertFalse(Grid.isDial(vertex(0, 0)))
        XCTAssertTrue(Grid.isDial(vertex(11, 3)))
    }

    func testSpawnCellsMatchJS() {
        // JS: SPAWN_CELLS (dropper.js), the top cell of each column
        let expected = [
            cell(0, -6), cell(1, -7), cell(2, -8), cell(3, -9), cell(4, -10), cell(5, -11),
            cell(6, -11), cell(7, -10), cell(8, -9), cell(9, -8), cell(10, -7), cell(11, -6),
        ]
        XCTAssertEqual(Dropper.spawnCells, expected)
    }

    func testIsUp() {
        // JS: isUp(r, c)
        XCTAssertFalse(Grid.isUp(cell(0, -5)))
        XCTAssertTrue(Grid.isUp(cell(0, -4)))
        XCTAssertFalse(Grid.isUp(cell(5, 0)))
        XCTAssertTrue(Grid.isUp(cell(6, 0)))
        XCTAssertTrue(Grid.isUp(cell(11, 5)))
        XCTAssertFalse(Grid.isUp(cell(3, -2)))
        // Negative sums use a true modulo
        XCTAssertTrue(Grid.isUp(cell(0, -6)))
        XCTAssertFalse(Grid.isUp(cell(0, -7)))
    }

    func testCenters() {
        // JS: cellCenter(r, c)
        assertPoint(Grid.center(of: cell(0, -5)), -2.5, -4.907477288111819)
        assertPoint(Grid.center(of: cell(0, -4)), -2, -4.618802153517006)
        assertPoint(Grid.center(of: cell(5, 0)), 0, -0.5773502691896258)
        assertPoint(Grid.center(of: cell(6, 0)), 0, 0.5773502691896257)
        assertPoint(Grid.center(of: cell(11, 5)), 2.5, 4.907477288111819)
        assertPoint(Grid.center(of: cell(3, -2)), -1, -2.309401076758503)
    }

    func testVertices() {
        // JS: cellVertices(r, c), in order
        func check(_ c: Cell, _ expected: [(Double, Double)], line: UInt = #line) {
            let actual = Grid.vertices(of: c)
            XCTAssertEqual(actual.count, 3, line: line)
            for (a, e) in zip(actual, expected) { assertPoint(a, e.0, e.1, line: line) }
        }
        check(cell(0, -5), [(-3, -5.196152422706632), (-2, -5.196152422706632), (-2.5, -4.330127018922193)])
        check(cell(0, -4), [(-2, -5.196152422706632), (-1.5, -4.330127018922193), (-2.5, -4.330127018922193)])
        check(cell(5, 0), [(-0.5, -0.8660254037844386), (0.5, -0.8660254037844386), (0, 0)])
        check(cell(6, 0), [(0, 0), (0.5, 0.8660254037844386), (-0.5, 0.8660254037844386)])
        check(cell(11, 5), [(2.5, 4.330127018922193), (3, 5.196152422706632), (2, 5.196152422706632)])
        check(cell(3, -2), [(-1.5, -2.598076211353316), (-0.5, -2.598076211353316), (-1, -1.7320508075688772)])
    }

    func testVertexPositions() {
        // JS: vertexXY(k, j)
        assertPoint(Grid.position(of: vertex(6, 4)), 2, 0)
        assertPoint(Grid.position(of: vertex(3, -3)), -1.5, -2.598076211353316)
        assertPoint(Grid.position(of: vertex(6, 6)), 3, 0)
    }

    func testDialCellsOrder() {
        // JS: dialCells(6, 0), clockwise from top-left
        XCTAssertEqual(Grid.dialCells(vertex(6, 0)), [
            cell(5, -1), cell(5, 0), cell(5, 1), cell(6, 1), cell(6, 0), cell(6, -1),
        ])
        XCTAssertEqual(Grid.dialCells(vertex(6, 10)), [
            cell(5, 9), cell(5, 10), cell(5, 11), cell(6, 11), cell(6, 10), cell(6, 9),
        ])
    }

    func testNearestDial() {
        // JS: nearestDial(x, y, maxDist)
        XCTAssertEqual(Grid.nearestDial(to: LatticePoint(0, 0)), vertex(6, 0))
        XCTAssertEqual(Grid.nearestDial(to: LatticePoint(3, 0)), vertex(6, 6)) // the game's start dial
        XCTAssertEqual(Grid.nearestDial(to: LatticePoint(0.3, 0.2), within: 1.2), vertex(6, 0))
        XCTAssertEqual(Grid.nearestDial(to: LatticePoint(100, 100)), vertex(11, 5))
        XCTAssertNil(Grid.nearestDial(to: LatticePoint(100, 100), within: 1.2))
        XCTAssertEqual(Grid.nearestDial(to: LatticePoint(6, 0), within: 1.2), vertex(6, 10))
        XCTAssertNil(Grid.nearestDial(to: LatticePoint(6, 0), within: 0.5))
        XCTAssertEqual(Grid.nearestDial(to: LatticePoint(-5.5, 0), within: 1.2), vertex(6, -10))
        XCTAssertNil(Grid.nearestDial(to: LatticePoint(2.25, 0.4), within: 0.3))
        XCTAssertEqual(Grid.nearestDial(to: LatticePoint(2, 0), within: 0.01), vertex(6, 4))
        XCTAssertEqual(Grid.nearestDial(to: LatticePoint(1, 0), within: 1.2), vertex(6, 2))
        // The cutoff: 1.19 from dial (6,10) at (5,0) is in, 1.21 is out
        XCTAssertEqual(Grid.nearestDial(to: LatticePoint(6.19, 0), within: 1.2), vertex(6, 10))
        XCTAssertNil(Grid.nearestDial(to: LatticePoint(6.21, 0), within: 1.2))
    }

    func testNearestDialTiesGoToTheFirstDial() {
        // Halfway between (6,0) and (6,2): JS keeps the earlier dial
        XCTAssertEqual(Grid.nearestDial(to: LatticePoint(0.5, 0), within: 1.2), vertex(6, 0))
        // A cell centre is equidistant from its three corners
        XCTAssertEqual(Grid.nearestDial(to: Grid.center(of: cell(6, 0)), within: 1.2), vertex(6, 0))
        XCTAssertEqual(Grid.nearestDial(to: Grid.center(of: cell(5, 3)), within: 1.2), vertex(5, 3))
    }
}
