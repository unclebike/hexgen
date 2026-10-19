// CoopTests.swift — Two dials on one shared bin, never overlapping

import Testing
@testable import DialhexCore

private let p1 = PlayerID(0), p2 = PlayerID(1)

private func dialCells(_ game: CoopGame, _ player: PlayerID) -> Set<Cell> {
    game.cursor(for: player).map { Set(Grid.dialCells($0.vertex)) } ?? []
}

struct CoopTests {
    @Test func dialsStartApartWithP1OnTheLeft() throws {
        let game = CoopGame(rng: SplitMix64(seed: 1))
        let a = try #require(game.cursor(for: p1)).vertex
        let b = try #require(game.cursor(for: p2)).vertex
        #expect(Grid.isDial(a) && Grid.isDial(b))
        #expect(dialCells(game, p1).isDisjoint(with: dialCells(game, p2)))
        // Screen x is -lattice y, so the left dial has the larger lattice y
        #expect(Grid.position(of: a).y > Grid.position(of: b).y)
        #expect(game.seatedPlayers == [p1, p2])
    }

    @Test func dialsNeverOverlapUnderRandomMoves() {
        var game = CoopGame(rng: SplitMix64(seed: 2))
        var input = SplitMix64(seed: 99)
        let directions: [Direction] = [.up, .down, .left, .right]
        for _ in 0..<5_000 {
            let player = input.next() % 2 == 0 ? p1 : p2
            _ = game.apply(.move(directions[Int(input.next() % 4)]), from: player)
            #expect(dialCells(game, p1).isDisjoint(with: dialCells(game, p2)))
        }
    }

    @Test func aDialInTheWayBlocksTheMove() {
        var game = CoopGame(rng: SplitMix64(seed: 3))
        let start = game.cursor(for: p1)
        // Both neighbours to P1's right share cells with P2's dial
        _ = game.apply(.move(.right), from: p1)
        #expect(game.cursor(for: p1) == start)
        // Nor can a dial be put down on top of the other
        game.moveCursorForTesting(p1, to: Vertex(k: 5, j: 7))
        #expect(game.cursor(for: p1) == start)
        // Moving away is fine
        _ = game.apply(.move(.left), from: p1)
        #expect(game.cursor(for: p1) != start)
    }

    /// A phone's mini bin puts a dial straight down, but never on the other player's.
    @Test func placingADialRespectsTheOtherOne() {
        var game = CoopGame(rng: SplitMix64(seed: 3))
        let start = game.cursor(for: p1)
        _ = game.apply(.place(CoopGame.startDials[1]), from: p1)
        #expect(game.cursor(for: p1) == start)
        // Somewhere free, it goes straight there
        let free = Vertex(k: 6, j: -4)
        #expect(Grid.isDial(free))
        _ = game.apply(.place(free), from: p1)
        #expect(game.cursor(for: p1)?.vertex == free)
    }

    @Test func bothDialsHoldTheirTriangles() {
        var game = CoopGame(rng: SplitMix64(seed: 4))
        // One loose triangle at the top of each dial
        let top1 = Grid.dialCells(CoopGame.startDials[0])[1]
        let top2 = Grid.dialCells(CoopGame.startDials[1])[1]
        game.setBoardForTesting(makeBoard([(top1.r, top1.c, 3), (top2.r, top2.c, 4)]))
        _ = game.update(by: Game.fallStep)
        #expect(placedColors(game.board) == [top1: 3, top2: 4])

        // P2 leaves: their triangle drops, P1's stays held
        game.leave(p2)
        _ = game.update(by: Game.fallStep)
        let placed = placedColors(game.board)
        #expect(placed[top1] == 3)
        #expect(placed[top2] == nil)
        #expect(placed.values.sorted() == [3, 4])
    }

    @Test func eachPlayerTurnsOnlyTheirOwnDial() throws {
        var game = CoopGame(rng: SplitMix64(seed: 5))
        let cells1 = Grid.dialCells(CoopGame.startDials[0])
        let cells2 = Grid.dialCells(CoopGame.startDials[1])
        game.setBoardForTesting(makeBoard([(cells1[0].r, cells1[0].c, 3), (cells2[0].r, cells2[0].c, 4)]))

        #expect(game.apply(.rotate(.clockwise), from: p1) == [.rotate])
        #expect(placedColors(game.board) == [cells1[1]: 3, cells2[0]: 4])
        #expect(game.apply(.rotate(.counterClockwise), from: p2) == [.rotate])
        #expect(placedColors(game.board) == [cells1[1]: 3, cells2[5]: 4])

        // Both turns animate at once
        #expect(game.dialTurns.count == 2)
        #expect(try #require(game.dialTurn(for: p1)).vertex == CoopGame.startDials[0])
        #expect(try #require(game.dialTurn(for: p2)).direction == .counterClockwise)
        _ = game.update(by: Game.rotateTime)
        #expect(game.dialTurns.isEmpty)
    }

    @Test func clearsAnywhereScoreForTheTeam() {
        var game = CoopGame(rng: SplitMix64(seed: 6))
        // A finished hex under P2's dial: held cells count as settled
        game.setBoardForTesting(makeBoard(Grid.dialCells(CoopGame.startDials[1]).map { ($0.r, $0.c, 7) }))
        let events = game.update(by: 0.01)
        #expect(events.contains { $0.isClear })
        #expect(game.score == 200)
        #expect(game.hexesCleared == 1)
    }

    @Test func aPlayerWhoLeftIsIgnoredAndFreesTheirSpace() {
        var game = CoopGame(rng: SplitMix64(seed: 7))
        game.leave(p2)
        #expect(game.seatedPlayers == [p1])
        #expect(game.cursor(for: p2) == nil)
        #expect(game.apply(.rotate(.clockwise), from: p2).isEmpty)
        // P1 can now go where P2's dial was
        game.moveCursorForTesting(p1, to: CoopGame.startDials[1])
        #expect(game.cursor(for: p1)?.vertex == CoopGame.startDials[1])
    }

    @Test func pauseStopsTheSharedClockAndInput() {
        var game = CoopGame(mode: .sprint, rng: SplitMix64(seed: 8))
        game.togglePause()
        #expect(game.phase == .paused)
        #expect(game.update(by: 1).isEmpty)
        #expect(game.sprintTimeRemaining == Game.sprintLength)
        let start = game.cursor(for: p1)
        _ = game.apply(.move(.left), from: p1)
        #expect(game.cursor(for: p1) == start)
        game.togglePause()
        _ = game.update(by: 1)
        #expect(game.sprintTimeRemaining == Game.sprintLength - 1)
    }

    @Test func aFullBinEndsTheGameForBoth() {
        var game = CoopGame(rng: SplitMix64(seed: 9))
        game.setBoardForTesting(makeBoard(Grid.cells.map { ($0.r, $0.c, $0.r % 2 == 0 ? 5 : 6) }))
        let events = game.update(by: Game.fallStep)
        #expect(events.contains(.gameOver(won: false)))
        #expect(game.phase == .gameOver)
    }
}
