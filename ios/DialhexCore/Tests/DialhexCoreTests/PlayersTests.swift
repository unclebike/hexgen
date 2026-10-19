// PlayersTests.swift — Player slots, the seeded generator, and the roster

import Testing
@testable import DialhexCore

struct PlayerIDTests {
    @Test func numbersFromOne() {
        #expect(PlayerID.all.map(\.description) == ["P1", "P2", "P3", "P4"])
        #expect(PlayerID(0) < PlayerID(3))
    }
}

struct SeededGeneratorTests {
    @Test func matchesTheTestGenerator() {
        // The same SplitMix64 the Game tests have always used
        var seeded = SeededGenerator(seed: 42)
        var reference = SplitMix64(seed: 42)
        for _ in 0..<100 { #expect(seeded.next() == reference.next()) }
    }

    @Test func sameSeedDealsTheSameGame() {
        var a = Game(mode: .endless, rng: SeededGenerator(seed: 7))
        var b = Game(mode: .endless, rng: SeededGenerator(seed: 7))
        for _ in 0..<200 {
            #expect(a.update(by: Game.fallStep) == b.update(by: Game.fallStep))
        }
        #expect(a.board == b.board)
    }
}

struct RosterTests {
    @Test func joinFillsTheLowestFreeSlot() {
        var roster = Roster<String>()
        #expect(roster.join("pad A") == PlayerID(0))
        #expect(roster.join("pad B") == PlayerID(1))
        // Joining again keeps the same player
        #expect(roster.join("pad A") == PlayerID(0))
        #expect(roster.players == [PlayerID(0), PlayerID(1)])
        #expect(roster.player(for: "pad B") == PlayerID(1))
        #expect(roster.player(for: "phone") == nil)
    }

    @Test func fullRosterTurnsAwayNewSources() {
        var roster = Roster<Int>(capacity: 2)
        roster.join(1)
        roster.join(2)
        #expect(roster.join(3) == nil)
        #expect(roster.players.count == 2)
    }

    @Test func leavingTheLobbyMovesLaterPlayersUp() {
        var roster = Roster<String>()
        for source in ["a", "b", "c"] { roster.join(source) }
        #expect(roster.leave("a") == PlayerID(0))
        #expect(roster.player(for: "b") == PlayerID(0))
        #expect(roster.player(for: "c") == PlayerID(1))
        #expect(roster.join("d") == PlayerID(2))
        #expect(roster.leave("nobody") == nil)
    }

    @Test func aDropMidMatchHoldsTheSlot() {
        var roster = Roster<String>()
        for source in ["a", "b", "c"] { roster.join(source) }
        roster.lock()
        #expect(roster.leave("b") == PlayerID(1))
        #expect(roster.seats[PlayerID(1)] == .dropped)
        #expect(roster.dropped == [PlayerID(1)])
        // Nobody moves up while the match is on
        #expect(roster.player(for: "c") == PlayerID(2))
    }

    @Test func theNextNewSourceReclaimsADroppedSlot() {
        var roster = Roster<String>()
        for source in ["a", "b", "c"] { roster.join(source) }
        roster.lock()
        roster.leave("c")
        roster.leave("a")
        // The lowest dropped slot first
        #expect(roster.join("b again") == PlayerID(0))
        #expect(roster.join("d") == PlayerID(2))
        // No dropped slots left: a running match takes no one new
        #expect(roster.join("e") == nil)
        #expect(roster.dropped.isEmpty)
    }

    @Test func forfeitingFreesTheSlotForGood() {
        var roster = Roster<String>()
        for source in ["a", "b"] { roster.join(source) }
        roster.lock()
        roster.leave("b")
        roster.forfeit(PlayerID(1))
        #expect(roster.players == [PlayerID(0)])
        #expect(roster.join("c") == nil)
        // Only dropped players can be forfeited
        roster.forfeit(PlayerID(0))
        #expect(roster.players == [PlayerID(0)])
    }

    @Test func backToTheLobbyClearsDropsAndClosesGaps() {
        var roster = Roster<String>()
        for source in ["a", "b", "c"] { roster.join(source) }
        roster.lock()
        roster.leave("a")
        roster.unlock()
        #expect(!roster.isLocked)
        #expect(roster.players == [PlayerID(0), PlayerID(1)])
        #expect(roster.player(for: "b") == PlayerID(0))
        #expect(roster.player(for: "c") == PlayerID(1))
    }
}
