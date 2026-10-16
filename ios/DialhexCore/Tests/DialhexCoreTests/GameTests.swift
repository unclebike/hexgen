// GameTests.swift — Game rules end to end, checked against gamestate.js
//
// JS times are in ms (FALL_STEP 140, CLEAR_TIME 450, sprint 180000); the
// Swift port uses seconds.

import XCTest
@testable import DialhexCore

final class CursorTests: XCTestCase {
    private func check(_ moves: [Direction], _ expected: [(Int, Int, Int)], file: StaticString = #filePath, line: UInt = #line) {
        var game = Game(mode: .main, rng: SplitMix64(seed: 1))
        XCTAssertEqual(moves.count, expected.count, "fixture", file: file, line: line)
        for (i, (move, want)) in zip(moves, expected).enumerated() {
            game.moveCursor(move)
            XCTAssertEqual(game.cursor.vertex, Vertex(k: want.0, j: want.1), "after move \(i + 1)", file: file, line: line)
            XCTAssertEqual(game.cursor.stickyJ, want.2, "stickyJ after move \(i + 1)", file: file, line: line)
        }
    }

    func testStartsOnTheJSStartDial() {
        // JS: createGame → nearestDial(SIZE * 0.5, 0) = (6, 6)
        let game = Game(mode: .main, rng: SplitMix64(seed: 1))
        XCTAssertEqual(game.cursor.vertex, vertex(6, 6))
        XCTAssertEqual(game.cursor.stickyJ, 6)
    }

    func testMovesAlongTheEdges() {
        // JS: moveCursorDir from the start, recording (k, j, stickyJ)
        let moves: [Direction] = [
            .down, .down, .down, .down, .down, .down,
            .left, .left, .left, .left, .left, .left, .left,
            .right, .right, .right, .right, .right, .right, .right, .right, .right, .right, .right, .right, .right, .right,
            .up, .up, .up, .up, .up, .up, .up, .up, .up, .up, .up, .up,
        ]
        let expected: [(Int, Int, Int)] = [
            (6, 8, 8), (6, 10, 10), (6, 10, 10), (6, 10, 10), (6, 10, 10), (6, 10, 10),
            (7, 9, 10), (8, 8, 10), (9, 7, 10), (10, 6, 10), (11, 5, 10), (11, 5, 10), (11, 5, 10),
            (10, 6, 10), (9, 7, 10), (8, 8, 10), (7, 9, 10), (6, 10, 10), (5, 9, 10), (4, 8, 10), (3, 7, 10),
            (2, 6, 10), (1, 5, 10), (1, 5, 10), (1, 5, 10), (1, 5, 10), (1, 5, 10),
            (1, 3, 3), (1, 1, 1), (1, -1, -1), (1, -3, -3), (1, -5, -5), (1, -5, -5), (1, -5, -5), (1, -5, -5),
            (1, -5, -5), (1, -5, -5), (1, -5, -5), (1, -5, -5),
        ]
        check(moves, expected)
    }

    func testZigzagDriftsBackToTheStickyColumn() {
        // JS
        let moves: [Direction] = [
            .left, .left, .left, .up, .left, .right, .right, .right, .right, .down, .down, .right, .right,
            .left, .left, .left, .left, .left, .left, .left, .left, .up, .up, .up,
            .right, .right, .right, .right, .right, .right, .right, .right, .right, .right, .right, .right,
            .down, .down, .left, .left,
        ]
        let expected: [(Int, Int, Int)] = [
            (7, 5, 6), (8, 6, 6), (9, 5, 6), (9, 3, 3), (10, 2, 3), (9, 3, 3), (8, 2, 3), (7, 3, 3), (6, 2, 3),
            (6, 4, 4), (6, 6, 6), (5, 5, 6), (4, 6, 6),
            (5, 5, 6), (6, 6, 6), (7, 5, 6), (8, 6, 6), (9, 5, 6), (10, 6, 6), (11, 5, 6), (11, 5, 6),
            (11, 3, 3), (11, 1, 1), (11, -1, -1),
            (10, -2, -1), (9, -1, -1), (8, -2, -1), (7, -1, -1), (6, -2, -1), (5, -1, -1), (4, -2, -1),
            (3, -1, -1), (2, -2, -1), (1, -1, -1), (1, -1, -1), (1, -1, -1),
            (1, 1, 1), (1, 3, 3), (2, 2, 3), (3, 3, 3),
        ]
        check(moves, expected)
    }

    func testRandomWalk() {
        // JS: 60 pseudo-random moves
        let moves: [Direction] = [
            .left, .down, .left, .right, .left, .left, .up, .right, .left, .right,
            .left, .down, .right, .up, .left, .up, .up, .right, .right, .right,
            .up, .down, .left, .down, .down, .down, .right, .right, .down, .down,
            .right, .up, .up, .down, .down, .left, .right, .down, .right, .up,
            .down, .right, .right, .down, .left, .right, .left, .up, .left, .up,
            .left, .down, .left, .down, .down, .down, .down, .right, .down, .up,
        ]
        let expected: [(Int, Int, Int)] = [
            (7, 5, 6), (7, 7, 7), (8, 6, 7), (7, 7, 7), (8, 6, 7), (9, 7, 7), (9, 5, 5), (8, 4, 5), (9, 5, 5), (8, 4, 5),
            (9, 5, 5), (9, 7, 7), (8, 6, 7), (8, 4, 4), (9, 3, 4), (9, 1, 1), (9, -1, -1), (8, -2, -1), (7, -1, -1), (6, -2, -1),
            (6, -4, -4), (6, -2, -2), (7, -3, -2), (7, -1, -1), (7, 1, 1), (7, 3, 3), (6, 2, 3), (5, 3, 3), (5, 5, 5), (5, 7, 7),
            (4, 6, 7), (4, 4, 4), (4, 2, 2), (4, 4, 4), (4, 6, 6), (5, 5, 6), (4, 6, 6), (4, 8, 8), (3, 7, 8), (3, 5, 5),
            (3, 7, 7), (2, 6, 7), (1, 5, 7), (1, 5, 7), (2, 6, 7), (1, 5, 7), (2, 6, 7), (2, 4, 4), (3, 3, 4), (3, 1, 1),
            (4, 0, 1), (4, 2, 2), (5, 1, 2), (5, 3, 3), (5, 5, 5), (5, 7, 7), (5, 9, 9), (4, 8, 9), (4, 8, 9), (4, 6, 6),
        ]
        check(moves, expected)
    }

    func testMoveCursorToOnlyAcceptsDials() {
        var game = Game(mode: .main, rng: SplitMix64(seed: 1))
        game.moveCursor(to: vertex(3, 3))
        XCTAssertEqual(game.cursor.vertex, vertex(3, 3))
        XCTAssertEqual(game.cursor.stickyJ, 3)
        game.moveCursor(to: vertex(6, 1)) // wrong parity
        game.moveCursor(to: vertex(0, 0)) // on the rim
        XCTAssertEqual(game.cursor.vertex, vertex(3, 3))
    }
}

final class TapTests: XCTestCase {
    func testTappingTheCurrentDialTurnsIt() {
        var game = Game(mode: .main, rng: SplitMix64(seed: 1))
        // A piece at the top-left of the start dial (6,6); clockwise moves it to (5,6)
        game.setBoardForTesting(makeBoard([(5, 5, 3)]))
        let events = game.tap(at: Grid.position(of: vertex(6, 6)))
        XCTAssertEqual(events, [.rotate])
        XCTAssertEqual(colors(game.board), layout([(5, 6, 3)]))
        XCTAssertEqual(game.cursor.vertex, vertex(6, 6))
        XCTAssertEqual(game.dialTurn, DialTurn(vertex: vertex(6, 6), direction: .clockwise, elapsed: 0))
    }

    func testTappingNearTheCurrentDialTurnsIt() {
        var game = Game(mode: .main, rng: SplitMix64(seed: 1))
        XCTAssertEqual(game.tap(at: LatticePoint(3.2, 0.3)), [.rotate])
    }

    func testTappingAnotherDialMovesThere() {
        var game = Game(mode: .main, rng: SplitMix64(seed: 1))
        game.setBoardForTesting(makeBoard([(5, -1, 3)]))
        XCTAssertEqual(game.tap(at: LatticePoint(0.3, 0.2)), [])
        XCTAssertEqual(game.cursor.vertex, vertex(6, 0))
        XCTAssertEqual(game.cursor.stickyJ, 0)
        XCTAssertEqual(colors(game.board), layout([(5, -1, 3)])) // moving doesn't turn
        XCTAssertNil(game.dialTurn)
        // Now it's the current dial, so a second tap turns it
        XCTAssertEqual(game.tap(at: LatticePoint(0, 0)), [.rotate])
        XCTAssertEqual(colors(game.board), layout([(5, 0, 3)]))
    }

    func testTapTiesAndCutoff() {
        var game = Game(mode: .main, rng: SplitMix64(seed: 1))
        // JS nearestDial(0.5, 0, 1.2) = (6,0): a tie goes to the earlier dial
        _ = game.tap(at: LatticePoint(0.5, 0))
        XCTAssertEqual(game.cursor.vertex, vertex(6, 0))
        _ = game.tap(at: LatticePoint(6.19, 0))
        XCTAssertEqual(game.cursor.vertex, vertex(6, 10))
        // Too far from any dial: nothing happens
        game.moveCursor(to: vertex(6, 6))
        XCTAssertEqual(game.tap(at: LatticePoint(6.21, 0)), [])
        XCTAssertEqual(game.tap(at: LatticePoint(100, 100)), [])
        XCTAssertEqual(game.cursor.vertex, vertex(6, 6))
        XCTAssertNil(game.dialTurn)
    }

    func testTapWhilePausedResumes() {
        var game = Game(mode: .main, rng: SplitMix64(seed: 1))
        game.setBoardForTesting(makeBoard([(5, 5, 3)]))
        game.togglePause()
        XCTAssertEqual(game.phase, .paused)
        // Even a tap on the current dial only resumes
        XCTAssertEqual(game.tap(at: Grid.position(of: vertex(6, 6))), [])
        XCTAssertEqual(game.phase, .playing)
        XCTAssertEqual(colors(game.board), layout([(5, 5, 3)]))
        XCTAssertEqual(game.cursor.vertex, vertex(6, 6))
        // And a tap elsewhere only resumes too
        game.togglePause()
        XCTAssertEqual(game.tap(at: LatticePoint(0, 0)), [])
        XCTAssertEqual(game.phase, .playing)
        XCTAssertEqual(game.cursor.vertex, vertex(6, 6))
    }

    func testDialTurnAnimationExpires() {
        // JS: rotAnim.t += dt; cleared once t >= ROTATE_TIME (120 ms)
        var game = Game(mode: .main, rng: SplitMix64(seed: 1))
        XCTAssertEqual(game.rotate(.counterClockwise), [.rotate])
        XCTAssertEqual(game.dialTurn?.direction, .counterClockwise)
        _ = game.update(by: 0.06)
        XCTAssertEqual(game.dialTurn?.elapsed ?? -1, 0.06, accuracy: 1e-12)
        _ = game.update(by: 0.06)
        XCTAssertNil(game.dialTurn)
    }

    func testRotateRefusesWhileClearing() {
        var game = Game(mode: .main, rng: SplitMix64(seed: 1))
        var board = makeBoard([(5, 5, 3)])
        board[cell(5, 5)]?.clearTime = 0.2
        game.setBoardForTesting(board)
        XCTAssertEqual(game.rotate(.clockwise), [])
        XCTAssertNil(game.dialTurn)
        XCTAssertEqual(game.board, board)
    }
}

final class GameRuleTests: XCTestCase {
    func testInitialState() {
        let game = Game(mode: .main, rng: SplitMix64(seed: 1))
        XCTAssertEqual(game.phase, .playing)
        XCTAssertEqual(game.level, 2)
        XCTAssertEqual(game.activeColors, [0, 1])
        XCTAssertEqual(game.score, 0)
        XCTAssertTrue(game.board.isEmpty)
        XCTAssertNil(game.sprintTimeRemaining)
        XCTAssertEqual(Game(mode: .sprint, rng: SplitMix64(seed: 1)).sprintTimeRemaining, 180)
        XCTAssertNil(Game(mode: .endless, rng: SplitMix64(seed: 1)).sprintTimeRemaining)
    }

    func testTimingConstantsMatchJS() {
        // JS: FALL_STEP 140, CLEAR_TIME 450, ROTATE_TIME 120 (ms); spawnIntervalFor(level)
        XCTAssertEqual(Game.fallStep, 0.14)
        XCTAssertEqual(Game.clearTime, 0.45)
        XCTAssertEqual(Game.rotateTime, 0.12)
        XCTAssertEqual(Game.sprintLength, 180)
        let jsIntervals: [Int: Double] = [2: 1800, 3: 1650, 4: 1500, 5: 1350, 6: 1200, 7: 1050, 8: 900, 20: 700]
        for (level, ms) in jsIntervals {
            XCTAssertEqual(Progression.spawnInterval(level: level), ms / 1000, accuracy: 1e-9, "level \(level)")
        }
        XCTAssertEqual(Progression.score(hexes: 6, level: 2), 1200)
        XCTAssertEqual(Progression.winHexes, 48)
    }

    func testFirstUpdateSpawnsAPiece() {
        var game = Game(mode: .main, rng: SplitMix64(seed: 5))
        let events = game.update(by: Game.fallStep)
        XCTAssertEqual(events.count, 1)
        XCTAssertTrue(events.first?.isSpawn ?? false)
        XCTAssertEqual(game.board.count, 1)
        let (spawned, piece) = game.board.first!
        XCTAssertTrue(Dropper.spawnCells.contains(spawned))
        XCTAssertEqual(events.first, .spawn(color: piece.color))
    }

    func testSpawnTimingMatchesJS() {
        // JS: from an empty board, spawns land on steps 1, 13, 26 (1.8 s apart,
        // measured in 140 ms steps)
        var game = Game(mode: .endless, rng: SplitMix64(seed: 9))
        var spawnSteps: [Int] = []
        for step in 1...26 {
            let events = game.update(by: Game.fallStep)
            if events.contains(where: \.isSpawn) { spawnSteps.append(step) }
        }
        XCTAssertEqual(spawnSteps, [1, 13, 26])
    }

    func testLevelUpAfterSixHexes() {
        // JS: the six-hex board scores 6 × 100 × 2, adds colour 2, and the
        // faster spawn interval (1650 ms) moves the third spawn from step 26 to 25
        var game = Game(mode: .endless, rng: SplitMix64(seed: 7))
        game.setBoardForTesting(GameFixtures.sixHexBoard())
        let events = game.update(by: Game.fallStep)

        let hexes = GameFixtures.sixHexCenters
            .sorted { ($0.k, $0.j) < ($1.k, $1.j) }
            .map { Hex(center: $0, color: 0, cells: Grid.dialCells($0)) }
        guard events.count == 3 else { return XCTFail("events: \(events)") }
        XCTAssertTrue(events[0].isSpawn)
        XCTAssertEqual(events[1], .clear(hexes: hexes, points: 1200))
        XCTAssertEqual(events[2], .levelUp(color: 2))

        XCTAssertEqual(game.score, 1200)
        XCTAssertEqual(game.level, 3)
        XCTAssertEqual(game.activeColors, [0, 1, 2])
        XCTAssertEqual(game.hexesCleared, 6)
        XCTAssertEqual(game.hexesThisLevel, 0)
        XCTAssertEqual(game.phase, .playing)

        // JS: the 36 hex triangles flash for 450 ms, then vanish on step 5
        func placed() -> [Piece] { game.board.values.filter { $0.id >= testPieceBaseID } }
        XCTAssertEqual(placed().count, 54)
        XCTAssertEqual(placed().filter(\.isClearing).count, 36)
        XCTAssertTrue(placed().filter(\.isClearing).allSatisfy { $0.clearTime == Game.clearTime })

        var spawnSteps = [1]
        for step in 2...26 {
            let stepEvents = game.update(by: Game.fallStep)
            if stepEvents.contains(where: \.isSpawn) { spawnSteps.append(step) }
            XCTAssertFalse(stepEvents.contains(where: \.isClear), "step \(step)")
            switch step {
            case 2:
                XCTAssertEqual(placed().count, 54)
                XCTAssertTrue(placed().filter(\.isClearing).allSatisfy { abs($0.clearTime - 0.31) < 1e-9 })
            case 3, 4:
                XCTAssertEqual(placed().count, 54, "step \(step)")
                XCTAssertEqual(placed().filter(\.isClearing).count, 36, "step \(step)")
            case 5:
                XCTAssertEqual(placed().count, 18)
                XCTAssertEqual(placed().filter(\.isClearing).count, 0)
            default:
                break
            }
        }
        XCTAssertEqual(spawnSteps, [1, 13, 25])
        XCTAssertEqual(game.score, 1200)
        XCTAssertEqual(game.level, 3)
    }

    func testWinningMainModeAfterFortyEightHexes() {
        // JS: every cell but the column tops holds colour 7 (never spawned):
        // 80 hexes at once → clear(80, 16000), levelup(2), gameover(won)
        let spawnCells = Set(Dropper.spawnCells)
        let board = makeBoard(Grid.cells.filter { !spawnCells.contains($0) }.map { ($0.r, $0.c, 7) })

        var game = Game(mode: .main, rng: SplitMix64(seed: 11))
        game.setBoardForTesting(board)
        let events = game.update(by: Game.fallStep)
        guard events.count == 4 else { return XCTFail("events: \(events)") }
        XCTAssertTrue(events[0].isSpawn)
        guard case let .clear(hexes, points) = events[1] else { return XCTFail("events: \(events)") }
        XCTAssertEqual(hexes.count, 80)
        XCTAssertEqual(points, 16000)
        XCTAssertEqual(events[2], .levelUp(color: 2))
        XCTAssertEqual(events[3], .gameOver(won: true))
        XCTAssertTrue(game.won)
        XCTAssertEqual(game.phase, .gameOver)
        XCTAssertEqual(game.score, 16000)
        XCTAssertEqual(game.level, 3)
        XCTAssertEqual(game.hexesCleared, 80)
        // Only one level per clear, as in JS
        XCTAssertEqual(game.hexesThisLevel, 74)

        // Endless mode can't be won
        var endless = Game(mode: .endless, rng: SplitMix64(seed: 11))
        endless.setBoardForTesting(board)
        let endlessEvents = endless.update(by: Game.fallStep)
        XCTAssertEqual(endlessEvents.count, 3)
        XCTAssertEqual(endlessEvents.last, .levelUp(color: 2))
        XCTAssertEqual(endless.phase, .playing)
        XCTAssertFalse(endless.won)
        XCTAssertEqual(endless.hexesThisLevel, 74)
    }

    func testDrainPowerEmptiesTheBottom() {
        // JS: clearing a hex holding a drain piece removes every other
        // non-clearing triangle whose centre has x > SIZE - 2
        let hex: [(Int, Int, Int)] = Grid.dialCells(vertex(6, 10)).map { ($0.r, $0.c, 0) }
        let others: [(Int, Int, Int)] = [
            (6, 8, 5), (6, 7, 5), (5, 8, 5), (5, 7, 5), (6, 6, 5), (7, 10, 5),
            (7, 9, 5), (7, 8, 5), (4, 10, 5), (4, 9, 5), (4, 8, 5), (6, 5, 5),
        ]
        var board = makeBoard(hex + others)
        board[cell(6, 11)]?.power = .drain
        var game = Game(mode: .endless, rng: SplitMix64(seed: 13))
        game.setBoardForTesting(board)
        let events = game.update(by: Game.fallStep)
        guard events.count == 3 else { return XCTFail("events: \(events)") }
        XCTAssertTrue(events[0].isSpawn)
        XCTAssertEqual(events[1], .clear(hexes: [Hex(center: vertex(6, 10), color: 0, cells: Grid.dialCells(vertex(6, 10)))], points: 200))
        XCTAssertEqual(events[2], .power(.drain))
        XCTAssertEqual(placedColors(game.board), layout([
            (4, 8, 5), (5, 7, 5), (5, 8, 5), (5, 9, 0), (5, 10, 0), (5, 11, 0), (6, 5, 5),
            (6, 6, 5), (6, 7, 5), (6, 8, 5), (6, 9, 0), (6, 10, 0), (6, 11, 0), (7, 8, 5),
        ]))
    }

    func testFullBinEndsTheGame() {
        // JS: a full bin with no hexes → gameover(won: false) on the next spawn
        var game = Game(mode: .main, rng: SplitMix64(seed: 3))
        game.setBoardForTesting(makeBoard(Grid.cells.map { ($0.r, $0.c, $0.r % 2 == 0 ? 5 : 6) }))
        XCTAssertEqual(game.update(by: Game.fallStep), [.gameOver(won: false)])
        XCTAssertEqual(game.phase, .gameOver)
        XCTAssertFalse(game.won)

        // Nothing moves after the game is over
        let board = game.board
        XCTAssertEqual(game.update(by: Game.fallStep), [])
        XCTAssertEqual(game.rotate(.clockwise), [])
        XCTAssertEqual(game.tap(at: LatticePoint(0, 0)), [])
        game.moveCursor(.up)
        game.togglePause()
        XCTAssertEqual(game.phase, .gameOver)
        XCTAssertEqual(game.cursor.vertex, vertex(6, 6))
        XCTAssertEqual(game.board, board)
    }

    func testBlockedTopsThatAreStillClearingDoNotEndTheGame() {
        // JS: 'wait' — no spawn, no game over
        var board = makeBoard(Dropper.spawnCells.map { ($0.r, $0.c, 5) })
        for key in board.keys { board[key]?.clearTime = Game.clearTime }
        var game = Game(mode: .main, rng: SplitMix64(seed: 3))
        game.setBoardForTesting(board)
        XCTAssertEqual(game.update(by: Game.fallStep), [])
        XCTAssertEqual(game.phase, .playing)
        XCTAssertEqual(game.board.count, 12)
    }

    func testEndlessGameEventuallyFillsUp() {
        // JS (Math.random): an idle endless game fills the bin in ~3000 steps
        var game = Game(mode: .endless, rng: SplitMix64(seed: 2024))
        var last: [GameEvent] = []
        var steps = 0
        while game.phase == .playing && steps < 20_000 {
            last = game.update(by: Game.fallStep)
            steps += 1
        }
        XCTAssertEqual(game.phase, .gameOver)
        XCTAssertEqual(last.last, .gameOver(won: false))
        XCTAssertFalse(game.won)
        XCTAssertTrue(Dropper.spawnCells.allSatisfy { game.board[$0] != nil && Dropper.isResting(game.board, $0) })
    }

    func testSprintEndsWhenTimeRunsOut() {
        // JS: update(100000) → 80000 left; update(79000) → 1000; update(1000) → gameover(false)
        var game = Game(mode: .sprint, rng: SplitMix64(seed: 4))
        XCTAssertFalse(game.update(by: 100).contains(.gameOver(won: false)))
        XCTAssertEqual(game.sprintTimeRemaining, 80)
        XCTAssertFalse(game.update(by: 79).contains(.gameOver(won: false)))
        XCTAssertEqual(game.sprintTimeRemaining, 1)
        XCTAssertEqual(game.phase, .playing)
        XCTAssertEqual(game.update(by: 1), [.gameOver(won: false)])
        XCTAssertEqual(game.sprintTimeRemaining, 0)
        XCTAssertEqual(game.phase, .gameOver)
        XCTAssertFalse(game.won)
    }

    func testSprintOvershootClampsToZero() {
        var game = Game(mode: .sprint, rng: SplitMix64(seed: 4))
        XCTAssertEqual(game.update(by: 500), [.gameOver(won: false)])
        XCTAssertEqual(game.sprintTimeRemaining, 0)
    }

    func testOtherModesHaveNoClock() {
        var game = Game(mode: .main, rng: SplitMix64(seed: 4))
        _ = game.update(by: 500)
        XCTAssertNil(game.sprintTimeRemaining)
        XCTAssertEqual(game.phase, .playing)
    }

    func testPauseStopsUpdates() {
        var game = Game(mode: .sprint, rng: SplitMix64(seed: 6))
        game.setBoardForTesting(makeBoard([(6, -11, 0), (5, 5, 1)]))
        game.togglePause()
        XCTAssertEqual(game.phase, .paused)
        let board = game.board
        for _ in 0..<50 { XCTAssertEqual(game.update(by: Game.fallStep), []) }
        XCTAssertEqual(game.board, board)
        XCTAssertEqual(game.sprintTimeRemaining, 180)
        // Input is ignored too
        XCTAssertEqual(game.rotate(.clockwise), [])
        game.moveCursor(.down)
        game.moveCursor(to: vertex(6, 0))
        XCTAssertEqual(game.cursor.vertex, vertex(6, 6))
        XCTAssertEqual(game.board, board)

        game.togglePause()
        XCTAssertEqual(game.phase, .playing)
        let events = game.update(by: Game.fallStep)
        XCTAssertTrue(events.contains(where: \.isSpawn))
        XCTAssertEqual(placedColors(game.board)[cell(6, -9)], 0) // falling again
        XCTAssertEqual(game.sprintTimeRemaining ?? 0, 180 - Game.fallStep, accuracy: 1e-9)
    }

    func testCatchUpIsCappedAtThreeSteps() {
        // JS: at most three fall steps per update, then the clock resets
        var game = Game(mode: .main, rng: SplitMix64(seed: 8))
        game.setBoardForTesting(makeBoard([(6, -11, 0)]))
        _ = game.update(by: 10)
        XCTAssertEqual(placedColors(game.board), layout([(6, -5, 0)]))
        XCTAssertEqual(game.fallProgress, 0)
    }
}
