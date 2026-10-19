// BoardTests.swift — Gravity, spawning, turning, and hex detection,
// checked against dropper.js, rotation.js, and hexdetect.js

import XCTest
@testable import DialhexCore

final class GravityTests: XCTestCase {
    /// Run `steps` gravity steps and return the layout after each one.
    private func simulate(_ pieces: [(Int, Int, Int)], steps: Int) -> (board: Board, history: [[Cell: Int]]) {
        var board = makeBoard(pieces)
        var history: [[Cell: Int]] = []
        for _ in 0..<steps {
            Dropper.stepGravity(&board)
            history.append(colors(board))
        }
        return (board, history)
    }

    private func allResting(_ board: Board) -> Bool {
        board.keys.allSatisfy { Dropper.isResting(board, $0) }
    }

    func testFallsTwoCellsPerStepDownTheMiddleColumn() {
        // JS: a lone piece entering column 6 at its top
        let (board, history) = simulate([(6, -11, 0)], steps: 12)
        let expected = [-9, -7, -5, -3, -1, 1, 3, 5, 7, 9, 11, 11].map { layout([(6, $0, 0)]) }
        XCTAssertEqual(history, expected)
        XCTAssertTrue(allResting(board))
    }

    func testRecordsWhereEachPieceCameFrom() {
        var board = makeBoard([(6, -11, 0), (6, 11, 1)])
        Dropper.stepGravity(&board)
        XCTAssertEqual(board[cell(6, -9)]?.from, cell(6, -11))
        XCTAssertNil(board[cell(6, 11)]?.from) // resting, didn't move
        XCTAssertEqual(board[cell(6, -9)]?.id, testPieceBaseID) // same piece
    }

    func testSlidesAlongTheSlantedWallAtTheFootOfAColumn() {
        // JS: column 3 falls to its foot at (3,9), then steps inward and down
        let (board, history) = simulate([(3, -9, 0)], steps: 14)
        let path: [(Int, Int)] = [
            (3, -7), (3, -5), (3, -3), (3, -1), (3, 1), (3, 3), (3, 5), (3, 7), (3, 9),
            (4, 10), (5, 11), (5, 11), (5, 11), (5, 11),
        ]
        XCTAssertEqual(history, path.map { layout([($0.0, $0.1, 0)]) })
        XCTAssertTrue(allResting(board))
    }

    func testSlidesFromTheShortTopColumn() {
        // JS: column 0
        let (_, history) = simulate([(0, -6, 0)], steps: 14)
        let path: [(Int, Int)] = [
            (0, -4), (0, -2), (0, 0), (0, 2), (0, 4), (0, 6),
            (1, 7), (2, 8), (3, 9), (4, 10), (5, 11), (5, 11), (5, 11), (5, 11),
        ]
        XCTAssertEqual(history, path.map { layout([($0.0, $0.1, 0)]) })
    }

    func testSlidesFromTheShortBottomColumn() {
        // JS: column 11 slides the other way, toward column 6
        let (_, history) = simulate([(11, -6, 0)], steps: 14)
        let path: [(Int, Int)] = [
            (11, -4), (11, -2), (11, 0), (11, 2), (11, 4), (11, 6),
            (10, 7), (9, 8), (8, 9), (7, 10), (6, 11), (6, 11), (6, 11), (6, 11),
        ]
        XCTAssertEqual(history, path.map { layout([($0.0, $0.1, 0)]) })
    }

    func testSlideFromColumn8() {
        // JS
        let (board, history) = simulate([(8, 7, 0)], steps: 5)
        let path: [(Int, Int)] = [(8, 9), (7, 10), (6, 11), (6, 11), (6, 11)]
        XCTAssertEqual(history, path.map { layout([($0.0, $0.1, 0)]) })
        XCTAssertTrue(allResting(board))
    }

    func testSlideBlockedByAPieceBelow() {
        // JS: (5,11) is taken, so the piece stops at the foot of column 4
        let (board, history) = simulate([(3, 7, 0), (5, 11, 1)], steps: 4)
        XCTAssertEqual(history, [
            layout([(3, 9, 0), (5, 11, 1)]),
            layout([(4, 10, 0), (5, 11, 1)]),
            layout([(4, 10, 0), (5, 11, 1)]),
            layout([(4, 10, 0), (5, 11, 1)]),
        ])
        XCTAssertTrue(allResting(board))
    }

    func testLandsOnARestingPiece() {
        // JS: falls the length of column 6 and stops on top of (6,11),
        // taking the last one-cell gap on the final step
        let (board, history) = simulate([(6, -11, 0), (6, 11, 1)], steps: 11)
        XCTAssertEqual(history[9], layout([(6, 9, 0), (6, 11, 1)]))
        XCTAssertEqual(history[10], layout([(6, 10, 0), (6, 11, 1)]))
        XCTAssertTrue(allResting(board))
    }

    func testLandsOnContactWithAStack() {
        // JS: a stack fills (6,4)...(6,11); the falling piece lands at (6,3)
        let stack = (4...11).map { (6, $0, 1) }
        let (board, history) = simulate([(6, -11, 0)] + stack, steps: 8)
        XCTAssertEqual(history[6], layout([(6, 3, 0)] + stack))
        XCTAssertEqual(history[7], layout([(6, 3, 0)] + stack))
        XCTAssertTrue(allResting(board))
    }

    func testOneCellIntoTheLastGap() {
        // JS
        let (board, history) = simulate([(6, 7, 0), (6, 11, 1)], steps: 3)
        XCTAssertEqual(history, [
            layout([(6, 9, 0), (6, 11, 1)]),
            layout([(6, 10, 0), (6, 11, 1)]),
            layout([(6, 10, 0), (6, 11, 1)]),
        ])
        XCTAssertTrue(allResting(board))
    }

    func testAFallingStackMovesTogether() {
        // JS: bottom of each column first, so adjacent pieces keep together
        let (board, history) = simulate([(6, -11, 0), (6, -10, 1), (6, -9, 2)], steps: 12)
        XCTAssertEqual(history[0], layout([(6, -9, 0), (6, -8, 1), (6, -7, 2)]))
        XCTAssertEqual(history[4], layout([(6, -1, 0), (6, 0, 1), (6, 1, 2)]))
        XCTAssertEqual(history[9], layout([(6, 9, 0), (6, 10, 1), (6, 11, 2)]))
        XCTAssertEqual(history[11], layout([(6, 9, 0), (6, 10, 1), (6, 11, 2)]))
        XCTAssertTrue(allResting(board))

        // JS: two pieces, one on the other
        let (_, pair) = simulate([(6, -11, 0), (6, -10, 1)], steps: 12)
        XCTAssertEqual(pair[0], layout([(6, -9, 0), (6, -8, 1)]))
        XCTAssertEqual(pair[9], layout([(6, 9, 0), (6, 10, 1)]))
        XCTAssertEqual(pair[10], layout([(6, 10, 0), (6, 11, 1)]))
        XCTAssertEqual(pair[11], layout([(6, 10, 0), (6, 11, 1)]))
    }

    func testFloatingPiecesKeepFalling() {
        // JS: neither piece rests; they fall in step
        let (board, history) = simulate([(6, -3, 0), (6, -1, 1)], steps: 2)
        XCTAssertEqual(history, [layout([(6, -1, 0), (6, 1, 1)]), layout([(6, 1, 0), (6, 3, 1)])])
        XCTAssertFalse(allResting(board))
    }

    func testTiesInGravityOrderGoTopRowFirst() {
        // JS sorts cells by c (descending) with a stable sort, so among cells
        // with the same c the lower row number moves first. Here (2,8) slides
        // into (3,9) before (3,8) can drop into it.
        let (_, history) = simulate([(1, -4, 0), (2, 8, 1), (3, 8, 2)], steps: 1)
        XCTAssertEqual(history[0], layout([(1, -2, 0), (3, 8, 2), (3, 9, 1)]))
    }

    func testHeldPiecesDoNotFallAndReleaseAtTheOldDialPosition() {
        let held = Set(Grid.dialCells(vertex(6, 0)))
        var board = makeBoard(held.map { ($0.r, $0.c, 0) })
        let before = board

        Dropper.stepGravity(&board, heldCells: held)
        XCTAssertEqual(board, before)

        Dropper.stepGravity(&board)
        XCTAssertNotEqual(board, before)
    }

    func testPiecesOutsideTheDialCanFallIntoAnEmptyHeldCell() {
        let held = Set(Grid.dialCells(vertex(6, 0)))
        let source = Grid.cells.first { cell in
            !held.contains(cell)
                && Dropper.nextMove(makeBoard([(cell.r, cell.c, 0)]), from: cell).map(held.contains) == true
        }!
        var board = makeBoard([(source.r, source.c, 0)])
        let id = board[source]!.id
        let target = Dropper.nextMove(board, from: source)!

        Dropper.stepGravity(&board, heldCells: held)

        XCTAssertEqual(board[target]?.id, id)
    }

    func testClearingPiecesDoNotFall() {
        var board = makeBoard([(6, -11, 0)])
        board[cell(6, -11)]?.clearTime = 0.3
        Dropper.stepGravity(&board)
        XCTAssertEqual(colors(board), layout([(6, -11, 0)]))
    }

    func testNextMove() {
        // JS: nextMove (dropper.js)
        let empty: Board = [:]
        XCTAssertEqual(Dropper.nextMove(empty, from: cell(6, -11)), cell(6, -9))
        XCTAssertEqual(Dropper.nextMove(empty, from: cell(6, 10)), cell(6, 11)) // one cell into the last gap
        XCTAssertEqual(Dropper.nextMove(empty, from: cell(3, 9)), cell(4, 10))
        XCTAssertEqual(Dropper.nextMove(empty, from: cell(0, 6)), cell(1, 7))
        XCTAssertEqual(Dropper.nextMove(empty, from: cell(11, 6)), cell(10, 7))
        XCTAssertNil(Dropper.nextMove(empty, from: cell(5, 11)))
        XCTAssertNil(Dropper.nextMove(empty, from: cell(6, 11)))
        XCTAssertTrue(Dropper.isResting(empty, cell(5, 11)))
        XCTAssertFalse(Dropper.isResting(empty, cell(5, 10)))

        let board = makeBoard([(5, 11, 1)])
        XCTAssertNil(Dropper.nextMove(board, from: cell(4, 10)))
        XCTAssertNil(Dropper.nextMove(board, from: cell(5, 10)))
        XCTAssertEqual(Dropper.nextMove(board, from: cell(5, 8)), cell(5, 10)) // two cells, stopping on (5,11)
        XCTAssertEqual(Dropper.nextMove(empty, from: cell(5, 10)), cell(5, 11))
    }
}

final class SpawnTests: XCTestCase {
    func testSpawnsAtTheTopOfAnOpenColumn() {
        var rng = SplitMix64(seed: 1)
        var board: Board = [:]
        for id in 0..<12 {
            XCTAssertEqual(Dropper.spawn(into: &board, colors: [0, 1], id: id, using: &rng), .spawned)
            let (spawnedCell, piece) = board.first { $0.value.id == id }!
            XCTAssertTrue(Dropper.spawnCells.contains(spawnedCell))
            XCTAssertTrue([0, 1].contains(piece.color))
            // Enters from just above the bin
            XCTAssertEqual(piece.from, Cell(r: spawnedCell.r, c: spawnedCell.c - 2))
            XCTAssertFalse(piece.isClearing)
        }
        // Every column top taken, but nothing has landed yet
        XCTAssertEqual(Set(board.keys), Set(Dropper.spawnCells))
        XCTAssertEqual(Dropper.spawn(into: &board, colors: [0, 1], id: 12, using: &rng), .wait)
        XCTAssertEqual(board.count, 12)
    }

    func testFullBin() {
        // JS: a full bin with no hexes returns 'full'
        var rng = SplitMix64(seed: 2)
        var board = makeBoard(Grid.cells.map { ($0.r, $0.c, $0.r % 2 == 0 ? 5 : 6) })
        XCTAssertEqual(Dropper.spawn(into: &board, colors: [0, 1], id: 0, using: &rng), .full)
        XCTAssertEqual(board.count, 216)
    }

    func testClearingPiecesAtTheTopMeanWait() {
        // JS: spawn cells held by clearing pieces with room below aren't resting
        var rng = SplitMix64(seed: 3)
        var board = makeBoard(Dropper.spawnCells.map { ($0.r, $0.c, 5) })
        for key in board.keys { board[key]?.clearTime = 0.45 }
        XCTAssertFalse(Dropper.spawnCells.contains { Dropper.isResting(board, $0) })
        XCTAssertEqual(Dropper.spawn(into: &board, colors: [0, 1], id: 0, using: &rng), .wait)
    }
}

final class DialTests: XCTestCase {
    private let ring: [(Int, Int, Int)] = [(5, -1, 0), (5, 0, 1), (5, 1, 2), (6, 1, 3), (6, 0, 4), (6, -1, 5), (4, 0, 9)]

    func testRotateClockwise() {
        // JS: rotateDial(board, 6, 0, 1)
        var board = makeBoard(ring)
        XCTAssertTrue(Dial.rotate(&board, at: vertex(6, 0), direction: .clockwise))
        XCTAssertEqual(colors(board), layout([(5, 0, 0), (5, 1, 1), (6, 1, 2), (6, 0, 3), (6, -1, 4), (5, -1, 5), (4, 0, 9)]))
    }

    func testRotateCounterClockwise() {
        // JS: rotateDial(board, 6, 0, -1)
        var board = makeBoard(ring)
        XCTAssertTrue(Dial.rotate(&board, at: vertex(6, 0), direction: .counterClockwise))
        XCTAssertEqual(colors(board), layout([(6, -1, 0), (5, -1, 1), (5, 0, 2), (5, 1, 3), (6, 1, 4), (6, 0, 5), (4, 0, 9)]))
    }

    func testRotateWithGaps() {
        // JS: empty cells turn too
        var cw = makeBoard([(5, -1, 0), (5, 1, 2), (6, 0, 4)])
        XCTAssertTrue(Dial.rotate(&cw, at: vertex(6, 0), direction: .clockwise))
        XCTAssertEqual(colors(cw), layout([(5, 0, 0), (6, 1, 2), (6, -1, 4)]))

        var ccw = makeBoard([(5, -1, 0), (5, 1, 2), (6, 0, 4)])
        XCTAssertTrue(Dial.rotate(&ccw, at: vertex(6, 0), direction: .counterClockwise))
        XCTAssertEqual(colors(ccw), layout([(6, -1, 0), (5, 0, 2), (6, 1, 4)]))
    }

    func testRotateKeepsPiecesAndClearsFrom() {
        var board = makeBoard(ring)
        board[cell(5, -1)]?.from = cell(5, -3)
        let before = board
        XCTAssertTrue(Dial.rotate(&board, at: vertex(6, 0), direction: .clockwise))
        XCTAssertEqual(board[cell(5, 0)]?.id, before[cell(5, -1)]?.id)
        XCTAssertNil(board[cell(5, 0)]?.from)
        XCTAssertTrue(Dial.rotate(&board, at: vertex(6, 0), direction: .counterClockwise))
        XCTAssertEqual(colors(board), colors(before))
        XCTAssertEqual(Set(board.values.map(\.id)), Set(before.values.map(\.id)))
    }

    func testSixTurnsComeBackAround() {
        var board = makeBoard(ring)
        let before = colors(board)
        for _ in 0..<6 { XCTAssertTrue(Dial.rotate(&board, at: vertex(6, 0), direction: .clockwise)) }
        XCTAssertEqual(colors(board), before)
    }

    func testRefusesToTurnWhileAPieceIsClearing() {
        // JS: returns false and leaves the board alone
        var board = makeBoard([(5, -1, 0), (5, 0, 1)])
        board[cell(5, 0)]?.clearTime = 0.1
        let before = board
        XCTAssertFalse(Dial.rotate(&board, at: vertex(6, 0), direction: .clockwise))
        XCTAssertFalse(Dial.rotate(&board, at: vertex(6, 0), direction: .counterClockwise))
        XCTAssertEqual(board, before)
        // A dial that doesn't touch the clearing piece still turns
        XCTAssertTrue(Dial.rotate(&board, at: vertex(8, 0), direction: .clockwise))
    }
}

final class HexDetectionTests: XCTestCase {
    private let bottomHex = Grid.dialCells(Vertex(k: 6, j: 10)).map { ($0.r, $0.c, 0) }

    func testFindsSixRestingSameColouredCells() {
        // JS: findHexes → [(6,10,0)]
        let board = makeBoard(bottomHex)
        XCTAssertTrue(Grid.dialCells(vertex(6, 10)).allSatisfy { Dropper.isResting(board, $0) })
        XCTAssertEqual(Dial.findHexes(board), [Hex(center: vertex(6, 10), color: 0, cells: Grid.dialCells(vertex(6, 10)))])
    }

    func testIgnoresMixedColours() {
        var board = makeBoard(bottomHex)
        board[cell(6, 9)]?.color = 1
        XCTAssertEqual(Dial.findHexes(board), [])
    }

    func testIgnoresPiecesThatAreStillFalling() {
        // JS: the same shape at (6,8) is floating
        let board = makeBoard(Grid.dialCells(vertex(6, 8)).map { ($0.r, $0.c, 0) })
        XCTAssertEqual(Dial.findHexes(board), [])
    }

    func testFindsMatchingFloatingHexWhenItsCellsAreHeld() {
        let center = vertex(6, 8)
        let held = Set(Grid.dialCells(center))
        let board = makeBoard(held.map { ($0.r, $0.c, 0) })

        XCTAssertEqual(
            Dial.findHexes(board, heldCells: held),
            [Hex(center: center, color: 0, cells: Grid.dialCells(center))]
        )
    }

    func testIgnoresClearingPieces() {
        var board = makeBoard(bottomHex)
        board[cell(6, 9)]?.clearTime = 0.01
        XCTAssertEqual(Dial.findHexes(board), [])
    }

    func testIgnoresAnIncompleteRing() {
        var board = makeBoard(bottomHex)
        board[cell(5, 9)] = nil
        XCTAssertEqual(Dial.findHexes(board), [])
    }

    func testFindsSeveralHexesInDialOrder() {
        // JS: six colour-0 hexes in a striped bottom region, found in DIALS order
        let board = GameFixtures.sixHexBoard()
        let centers = [vertex(2, 6), vertex(4, 8), vertex(6, 6), vertex(6, 10), vertex(8, 8), vertex(10, 6)]
        XCTAssertEqual(Dial.findHexes(board), centers.map { Hex(center: $0, color: 0, cells: Grid.dialCells($0)) })
    }
}

enum GameFixtures {
    /// Every cell with c ≥ 5 (lattice x ≥ 2.5): the bottom of the bin, all resting.
    static let bottomCells = Grid.cells.filter { $0.c >= 5 }

    /// The bottom region striped by row in colours 5 and 6 (so no hexes), with
    /// six disjoint dials painted colour 0. JS: findHexes finds exactly these six.
    static let sixHexCenters = [vertex(2, 6), vertex(4, 8), vertex(6, 10), vertex(8, 8), vertex(10, 6), vertex(6, 6)]

    static func sixHexBoard() -> Board {
        var board = makeBoard(bottomCells.map { ($0.r, $0.c, $0.r % 2 == 0 ? 5 : 6) })
        for center in sixHexCenters {
            for cell in Grid.dialCells(center) { board[cell]?.color = 0 }
        }
        return board
    }
}
