// AssistTests.swift — Gentle spawns and one-turn hints for assisted games

import Testing
@testable import DialhexCore

struct GentleSpawnTests {
    /// Spawn into copies of `board` many times and tally what arrived where.
    private func spawns(on board: Board, colors: [Int], gentle: Bool, count: Int = 3000) -> (columns: [Int: Int], colors: [Int: Int]) {
        var rng = SplitMix64(seed: 42)
        var columns: [Int: Int] = [:]
        var tally: [Int: Int] = [:]
        for _ in 0..<count {
            var trial = board
            #expect(Dropper.spawn(into: &trial, colors: colors, id: 9999, gentle: gentle, using: &rng) == .spawned)
            guard let (cell, piece) = trial.first(where: { $0.value.id == 9999 }) else { continue }
            columns[cell.r, default: 0] += 1
            tally[piece.color, default: 0] += 1
        }
        return (columns, tally)
    }

    @Test func leansAwayFromTallColumns() {
        // Column 5 is full to just under its top; the rest are empty
        let column = Dropper.columns[5]
        let board = makeBoard(column.dropFirst().map { ($0.r, $0.c, 3) })
        let even = spawns(on: board, colors: [0, 1], gentle: false).columns[5, default: 0]
        let gentle = spawns(on: board, colors: [0, 1], gentle: true).columns[5, default: 0]
        // Uniform gives it about one in twelve; weighted by room, about one in a hundred
        #expect(even > 150)
        #expect(gentle < 80)
    }

    @Test func leansTowardAColourAHexIsWaitingFor() {
        // Four of colour 0 around a dial, two empty cells: only colour 0 finishes it
        let dial = Vertex(k: 6, j: 10)
        let board = makeBoard(Grid.dialCells(dial).prefix(4).map { ($0.r, $0.c, 0) })
        #expect(Dropper.wantedColors(on: board, among: [0, 1]) == [0])
        let even = spawns(on: board, colors: [0, 1], gentle: false).colors[0, default: 0]
        let gentle = spawns(on: board, colors: [0, 1], gentle: true).colors[0, default: 0]
        #expect(abs(even - 1500) < 150)
        #expect(gentle > 1850) // about two in three
    }

    @Test func nothingIsWantedFromAMixedOrFinishedDial() {
        let dial = Vertex(k: 6, j: 10)
        let cells = Grid.dialCells(dial)
        let mixed = makeBoard(cells.prefix(4).enumerated().map { ($1.r, $1.c, $0 == 0 ? 1 : 0) })
        #expect(Dropper.wantedColors(on: mixed, among: [0, 1]).isEmpty)
        // A colour not yet in play can't be asked for
        let unused = makeBoard(cells.prefix(5).map { ($0.r, $0.c, 4) })
        #expect(Dropper.wantedColors(on: unused, among: [0, 1]).isEmpty)
    }
}

struct HintTests {
    /// The resting hex the drain test clears, at the bottom of the bin.
    private let hex = Vertex(k: 6, j: 10)

    /// A dial that shares cells with the hex.
    private var neighbour: Vertex {
        Grid.dials.first { $0 != hex && !Set(Grid.dialCells($0)).isDisjoint(with: Grid.dialCells(hex)) }!
    }

    /// The hex of colour 0, broken up by one clockwise turn of the neighbour.
    private func scrambled() -> Board {
        var board = makeBoard(Grid.dialCells(hex).map { ($0.r, $0.c, 0) })
        #expect(Dial.rotate(&board, at: neighbour, direction: .clockwise))
        return board
    }

    @Test func turningBackFinishesTheHex() {
        let board = scrambled()
        #expect(Dial.findHexes(board, heldCells: Set(Grid.dialCells(neighbour))).isEmpty)
        #expect(Hints.finishesHex(board, at: neighbour))
        #expect(Hints.oneTurnFromHex(on: board, near: neighbour) == neighbour)
    }

    @Test func anEmptyOrHopelessBoardHasNoHint() {
        #expect(Hints.oneTurnFromHex(on: [:], near: hex) == nil)
        // Two colours, three each, can't make a hex in one turn
        let mixed = makeBoard(Grid.dialCells(hex).enumerated().map { ($1.r, $1.c, $0 % 2) })
        #expect(Hints.oneTurnFromHex(on: mixed, near: hex) == nil)
    }

    @Test func aHexAlreadyThereIsNoHint() {
        // The finished hex will clear on its own; turning near it isn't a hint
        let board = makeBoard(Grid.dialCells(hex).map { ($0.r, $0.c, 0) })
        #expect(!Hints.finishesHex(board, at: neighbour))
    }

    @Test func aClearingDialCannotTurn() {
        var board = scrambled()
        for cell in Grid.dialCells(neighbour) where board[cell] != nil { board[cell]?.clearTime = Game.clearTime }
        #expect(!Hints.finishesHex(board, at: neighbour))
    }

    @Test func theHintMatchesWhatTheGameDoes() {
        // Put the dial there, turn it back, and the game clears the hex
        var game = Game(mode: .endless, rng: SplitMix64(seed: 5))
        game.setBoardForTesting(scrambled())
        game.moveCursor(to: neighbour)
        _ = game.rotate(.counterClockwise)
        let cleared = game.update(by: 0).contains { if case .clear = $0 { true } else { false } }
        #expect(cleared)
    }
}
