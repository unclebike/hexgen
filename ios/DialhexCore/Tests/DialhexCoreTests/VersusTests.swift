// VersusTests.swift — Split-screen versus: N ordinary Games, one clock, one result

import Testing
@testable import DialhexCore

private let p1 = PlayerID(0), p2 = PlayerID(1), p3 = PlayerID(2)

/// A finished hex of colour 7 under the start dial (6, 6). Held cells count
/// as settled, so it clears on the next update for 1 × 100 × level 2 points.
private func hexUnderStartDial() -> Board {
    makeBoard(Grid.dialCells(vertex(6, 6)).map { ($0.r, $0.c, 7) })
}

/// A bin stacked to the top with no hexes: game over on the next spawn.
private func fullBin() -> Board {
    makeBoard(Grid.cells.map { ($0.r, $0.c, $0.r % 2 == 0 ? 5 : 6) })
}

/// Every cell but the column tops in colour 7: 80 hexes at once, which wins MAIN.
private func winningBin() -> Board {
    let tops = Set(Dropper.spawnCells)
    return makeBoard(Grid.cells.filter { !tops.contains($0) }.map { ($0.r, $0.c, 7) })
}

private extension [Versus.Event] {
    /// Everything but the boards' own events.
    var matchEvents: [Versus.Event] {
        filter {
            if case .board = $0 { return false }
            return true
        }
    }
}

/// Step the match until something happens beyond the boards' own events (a
/// full bin only ends its game at the next spawn, up to 13 steps away).
private func stepUntilMatchEvent(_ match: inout Versus) -> [Versus.Event] {
    for _ in 0..<20 {
        let events = match.update(by: Game.fallStep).matchEvents
        if !events.isEmpty { return events }
    }
    return []
}

struct VersusSetupTests {
    @Test(arguments: Versus.Rule.allCases)
    func everyBoardPlaysTheRulesMode(rule: Versus.Rule) {
        let match = Versus(players: [p1, p2, p3], rule: rule, seed: 1)
        #expect(match.players == [p1, p2, p3])
        #expect(match.boards.values.allSatisfy { $0.mode == rule.mode })
        #expect(match.phase == .playing)
        #expect(match.winners == nil)
    }

    @Test func boardsAreDealtTheSamePieces() {
        var match = Versus(players: [p1, p2], rule: .survival, seed: 99)
        for _ in 0..<40 { _ = match.update(by: Game.fallStep) }
        #expect(match.boards[p1]?.board == match.boards[p2]?.board)
    }

    @Test func eachBoardPlaysLikeASoloGame() {
        var match = Versus(players: [p1, p2], rule: .sprintRace, seed: 5)
        var solo = Game(mode: .sprint, rng: SeededGenerator(seed: 5))
        let script: [PlayerInput] = [.move(.left), .rotate(.clockwise), .move(.up), .rotate(.counterClockwise)]
        for step in 0..<300 {
            let soloEvents = solo.update(by: Game.fallStep)
            let events = match.update(by: Game.fallStep)
            #expect(events.compactMap { event -> GameEvent? in
                if case .board(p2, let e) = event { return e }
                return nil
            } == soloEvents)
            if step % 7 == 0 {
                let input = script[(step / 7) % script.count]
                switch input {
                case .move(let direction): solo.moveCursor(direction)
                case .place(let vertex): solo.moveCursor(to: vertex)
                case .rotate(let direction): _ = solo.rotate(direction)
                }
                _ = match.apply(input, from: p2)
            }
        }
        #expect(match.boards[p2]?.board == solo.board)
        #expect(match.boards[p2]?.score == solo.score)
        #expect(match.boards[p2]?.cursor == solo.cursor)
    }

    @Test func inputOnlyReachesThatPlayersBoard() {
        var match = Versus(players: [p1, p2], rule: .survival, seed: 3)
        match.setBoardForTesting(makeBoard([(5, 5, 3)]), for: p1)
        match.setBoardForTesting(makeBoard([(5, 5, 3)]), for: p2)
        let p1Before = match.boards[p1]!

        #expect(match.apply(.rotate(.clockwise), from: p2) == [.board(p2, .rotate)])
        _ = match.apply(.move(.down), from: p2)

        #expect(match.boards[p1]?.board == p1Before.board)
        #expect(match.boards[p1]?.cursor == p1Before.cursor)
        #expect(colors(match.boards[p2]!.board) == layout([(5, 6, 3)]))
        #expect(match.boards[p2]?.cursor.vertex == vertex(6, 8))
    }
}

struct SprintRaceTests {
    @Test func theClockEndsEveryoneAndTheBestScoreWins() {
        var match = Versus(players: [p1, p2, p3], rule: .sprintRace, seed: 1)
        match.setBoardForTesting(hexUnderStartDial(), for: p2)
        _ = match.update(by: Game.fallStep)
        #expect(match.boards[p2]?.score == 200)

        let events = match.update(by: Game.sprintLength)
        #expect(events.matchEvents == [.matchOver(winners: [p2])])
        #expect(match.winners == [p2])
        #expect(match.phase == .gameOver)
        // Running out of time isn't being knocked out
        #expect(match.eliminated.isEmpty)
    }

    @Test func equalScoresShareTheWin() {
        var match = Versus(players: [p1, p2], rule: .sprintRace, seed: 1)
        #expect(match.update(by: Game.sprintLength).matchEvents == [.matchOver(winners: [p1, p2])])
    }

    @Test func aFullBinStopsScoringButTheRaceGoesOn() {
        var match = Versus(players: [p1, p2], rule: .sprintRace, seed: 1)
        match.setBoardForTesting(hexUnderStartDial(), for: p1)
        _ = match.update(by: Game.fallStep)
        match.setBoardForTesting(fullBin(), for: p1)

        #expect(stepUntilMatchEvent(&match) == [.eliminated(p1)])
        #expect(match.phase == .playing)
        #expect(match.activePlayers == [p2])

        // P1's 200 still beats P2's nothing when the clock runs out
        #expect(match.update(by: Game.sprintLength).matchEvents == [.matchOver(winners: [p1])])
    }
}

struct SurvivalTests {
    @Test func theLastBinStandingWins() {
        var match = Versus(players: [p1, p2], rule: .survival, seed: 1)
        match.setBoardForTesting(fullBin(), for: p1)
        let events = match.update(by: Game.fallStep)
        #expect(events.matchEvents == [.eliminated(p1), .matchOver(winners: [p2])])
        #expect(match.eliminated == [p1])
        #expect(match.winners == [p2])
    }

    @Test func withMorePlayersTheMatchGoesOn() {
        var match = Versus(players: [p1, p2, p3], rule: .survival, seed: 1)
        match.setBoardForTesting(fullBin(), for: p2)
        #expect(match.update(by: Game.fallStep).matchEvents == [.eliminated(p2)])
        #expect(match.phase == .playing)
        #expect(match.activePlayers == [p1, p3])

        // A knocked-out board takes no more input or time
        let board = match.boards[p2]!.board
        #expect(match.apply(.rotate(.clockwise), from: p2).isEmpty)
        _ = match.update(by: Game.fallStep)
        #expect(match.boards[p2]?.board == board)

        match.setBoardForTesting(fullBin(), for: p3)
        #expect(stepUntilMatchEvent(&match) == [.eliminated(p3), .matchOver(winners: [p1])])
        #expect(match.eliminated == [p2, p3])
    }

    @Test func goingOutTogetherIsATie() {
        var match = Versus(players: [p1, p2], rule: .survival, seed: 1)
        match.setBoardForTesting(fullBin(), for: p1)
        match.setBoardForTesting(fullBin(), for: p2)
        #expect(match.update(by: Game.fallStep).matchEvents
                == [.eliminated(p1), .eliminated(p2), .matchOver(winners: [p1, p2])])
    }
}

struct FirstToWinTests {
    @Test func theFirstToWinTakesTheMatch() {
        var match = Versus(players: [p1, p2], rule: .firstToWin, seed: 11)
        match.setBoardForTesting(winningBin(), for: p2)
        let events = match.update(by: Game.fallStep)
        #expect(events.contains(.board(p2, .gameOver(won: true))))
        #expect(events.matchEvents == [.matchOver(winners: [p2])])
        #expect(match.eliminated.isEmpty)
    }

    @Test func theLastOneLeftAlsoWins() {
        var match = Versus(players: [p1, p2], rule: .firstToWin, seed: 1)
        match.setBoardForTesting(fullBin(), for: p2)
        #expect(match.update(by: Game.fallStep).matchEvents == [.eliminated(p2), .matchOver(winners: [p1])])
    }
}

struct VersusControlTests {
    @Test func pauseCoversEveryBoard() {
        var match = Versus(players: [p1, p2], rule: .sprintRace, seed: 6)
        match.togglePause()
        #expect(match.phase == .paused)
        #expect(match.boards.values.allSatisfy { $0.phase == .paused })
        #expect(match.update(by: 10).isEmpty)
        #expect(match.apply(.rotate(.clockwise), from: p1).isEmpty)
        #expect(match.boards[p1]?.sprintTimeRemaining == Game.sprintLength)

        match.togglePause()
        #expect(match.phase == .playing)
        #expect(match.boards.values.allSatisfy { $0.phase == .playing })
        #expect(match.update(by: Game.fallStep).count == 2) // a spawn on each board
    }

    @Test func pausingLeavesFinishedBoardsAlone() {
        var match = Versus(players: [p1, p2, p3], rule: .survival, seed: 1)
        match.setBoardForTesting(fullBin(), for: p1)
        _ = match.update(by: Game.fallStep)
        match.togglePause()
        match.togglePause()
        #expect(match.boards[p1]?.phase == .gameOver)
    }

    @Test func forfeitingKnocksAPlayerOut() {
        var match = Versus(players: [p1, p2, p3], rule: .survival, seed: 1)
        match.togglePause() // a controller dropped, so the match paused
        #expect(match.forfeit(p3) == [.eliminated(p3)])
        #expect(match.isOut(p3))
        #expect(match.forfeit(p3).isEmpty) // only once
        #expect(match.forfeit(p2) == [.eliminated(p2), .matchOver(winners: [p1])])
        #expect(match.phase == .gameOver)
    }

    @Test func aForfeitedPlayerCannotWinTheRace() {
        var match = Versus(players: [p1, p2], rule: .sprintRace, seed: 1)
        match.setBoardForTesting(hexUnderStartDial(), for: p1)
        _ = match.update(by: Game.fallStep)
        #expect(match.forfeit(p1) == [.eliminated(p1)])
        #expect(match.update(by: Game.sprintLength).matchEvents == [.matchOver(winners: [p2])])
    }

    @Test func nothingMovesAfterTheMatch() {
        var match = Versus(players: [p1, p2], rule: .survival, seed: 1)
        match.setBoardForTesting(fullBin(), for: p1)
        _ = match.update(by: Game.fallStep)
        let board = match.boards[p2]!.board
        #expect(match.update(by: Game.fallStep).isEmpty)
        #expect(match.apply(.move(.up), from: p2).isEmpty)
        #expect(match.boards[p2]?.board == board)
        match.togglePause()
        #expect(match.phase == .gameOver)
    }
}
