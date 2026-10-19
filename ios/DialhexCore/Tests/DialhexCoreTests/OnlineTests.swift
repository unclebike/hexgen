// OnlineTests.swift — Online co-op: snapshots, the wire format, and its defences

import Foundation
import Testing
@testable import DialhexCore

private let host = OnlineCoop.hostPlayer, guest = OnlineCoop.guestPlayer

/// A co-op game some way in: pieces falling and landed, and a turn mid-animation.
private func playedGame(seed: UInt64 = 7, seconds: Double = 20) -> CoopGame {
    var game = CoopGame(mode: .sprint, speed: .normal, rng: SplitMix64(seed: seed))
    var input = SplitMix64(seed: seed &+ 1)
    let directions: [Direction] = [.up, .down, .left, .right]
    var t = 0.0
    while t < seconds && game.phase == .playing {
        _ = game.update(by: 1.0 / 60)
        if input.next() % 8 == 0 {
            let player = input.next() % 2 == 0 ? host : guest
            if input.next() % 2 == 0 {
                _ = game.apply(.rotate(.clockwise), from: player)
            } else {
                _ = game.apply(.move(directions[Int(input.next() % 4)]), from: player)
            }
        }
        t += 1.0 / 60
    }
    _ = game.apply(.rotate(.counterClockwise), from: host)
    return game
}

private func roundTrip(_ snapshot: CoopSnapshot) throws -> CoopSnapshot {
    let data = OnlineMessage.state(seq: 1, ack: 0, snapshot).encoded
    guard case .state(_, _, let decoded) = try #require(OnlineMessage.decode(data, from: .host)) else {
        Issue.record("not a state message")
        throw WireError.invalid
    }
    return decoded
}

/// The same game, allowing for timers sent to the millisecond and the fall to 1/65535.
private func expectSame(_ a: CoopSnapshot, _ b: CoopSnapshot) {
    #expect(a.mode == b.mode && a.speed == b.speed && a.phase == b.phase && a.won == b.won)
    #expect(a.score == b.score && a.level == b.level && a.hexesCleared == b.hexesCleared)
    #expect(a.hexesThisLevel == b.hexesThisLevel && a.activeColors == b.activeColors)
    #expect(abs((a.sprintTimeRemaining ?? -1) - (b.sprintTimeRemaining ?? -1)) < 0.001)
    #expect(abs(a.fallProgress - b.fallProgress) < 0.0001)
    #expect(a.dials == b.dials)
    #expect(a.board.keys == b.board.keys)
    for (cell, piece) in a.board {
        let other = b.board[cell]
        #expect(other?.id == piece.id && other?.color == piece.color && other?.power == piece.power)
        #expect(other?.from == piece.from)
        #expect(abs((other?.clearTime ?? -1) - piece.clearTime) < 0.001)
    }
    #expect(a.dialTurns.map { $0?.vertex } == b.dialTurns.map { $0?.vertex })
    #expect(a.dialTurns.map { $0?.pieceIDs } == b.dialTurns.map { $0?.pieceIDs })
}

struct OnlineSnapshotTests {
    @Test func aSnapshotSurvivesTheTrip() throws {
        let snapshot = playedGame().snapshot
        #expect(!snapshot.board.isEmpty)
        #expect(snapshot.dialTurns.contains { $0 != nil })
        expectSame(snapshot, try roundTrip(snapshot))
    }

    @Test func aRestoredCopyDrawsTheSameGame() throws {
        let game = playedGame(seed: 11)
        let copy = CoopGame(restoring: try roundTrip(game.snapshot))
        #expect(copy.board.keys == game.board.keys)
        #expect(copy.board.mapValues(\.id) == game.board.mapValues(\.id))
        #expect(copy.cursor(for: host) == game.cursor(for: host))
        #expect(copy.cursor(for: guest) == game.cursor(for: guest))
        #expect(copy.score == game.score && copy.phase == game.phase && copy.mode == game.mode)
        #expect(abs(copy.fallProgress - game.fallProgress) < 0.0001)
    }

    @Test func aPlayerWhoLeftStaysGone() throws {
        var game = playedGame(seed: 3, seconds: 2)
        game.leave(guest)
        let copy = CoopGame(restoring: try roundTrip(game.snapshot))
        #expect(copy.seatedPlayers == [host])
        #expect(copy.cursor(for: guest) == nil)
    }

    /// The fullest board possible: every cell taken, mid-clear, with a power and a move to animate.
    @Test func aFullBoardFitsInOneMessage() throws {
        var board: Board = [:]
        for (i, cell) in Grid.cells.enumerated() {
            board[cell] = Piece(id: Int(UInt32.max) - i, color: i % Progression.colorCount, power: .swap,
                                from: Cell(r: cell.r, c: cell.c - 2), clearTime: Game.clearTime)
        }
        var game = CoopGame(rng: SplitMix64(seed: 1))
        game.setBoardForTesting(board)
        let data = OnlineMessage.state(seq: .max, ack: .max, game.snapshot).encoded
        #expect(data.count <= OnlineCoop.maxHostMessageBytes)
        expectSame(game.snapshot, try roundTrip(game.snapshot))
    }

    @Test func everyKindOfMessageSurvivesTheTrip() throws {
        let hexes = [Hex(center: Grid.dials[3], color: 2, cells: Grid.dialCells(Grid.dials[3]))]
        let fromGuest: [OnlineMessage] = [
            .input(seq: 1, .move(.left)), .input(seq: 2, .place(Grid.dials[0])),
            .input(seq: .max, .rotate(.counterClockwise)), .pause(true), .pause(false), .rematch, .bye,
        ]
        for message in fromGuest {
            #expect(OnlineMessage.decode(message.encoded, from: .guest) == message)
        }
        let events: OnlineMessage = .events(by: guest, [
            .spawn(color: 1), .rotate, .clear(hexes: hexes, points: 120), .power(.drain), .power(.swap),
            .levelUp(color: 7), .gameOver(won: true),
        ])
        #expect(OnlineMessage.decode(events.encoded, from: .host) == events)
        #expect(OnlineMessage.decode(OnlineMessage.events(by: nil, []).encoded, from: .host) == .events(by: nil, []))
        let hello = OnlineMessage.hello(.init(nonce: 0xDEAD_BEEF_0000_0001, inviter: true))
        #expect(OnlineMessage.decode(hello.encoded, from: .undecided) == hello)
    }
}

struct OnlineDefenceTests {
    private let state = OnlineMessage.state(seq: 4, ack: 2, playedGame(seed: 5).snapshot).encoded

    @Test func messagesOnlyComeFromTheRightSide() {
        // A guest can't send the game, and a host can't send inputs
        #expect(OnlineMessage.decode(state, from: .guest) == nil)
        #expect(OnlineMessage.decode(state, from: .undecided) == nil)
        #expect(OnlineMessage.decode(OnlineMessage.input(seq: 1, .rotate(.clockwise)).encoded, from: .host) == nil)
        #expect(OnlineMessage.decode(OnlineMessage.pause(true).encoded, from: .host) == nil)
        // Hellos only before roles are settled
        let hello = OnlineMessage.hello(.init(nonce: 1, inviter: false)).encoded
        #expect(OnlineMessage.decode(hello, from: .guest) == nil)
        #expect(OnlineMessage.decode(hello, from: .host) == nil)
    }

    @Test func otherVersionsAndStrangersAreTurnedAway() {
        var wrongVersion = state
        wrongVersion[1] = OnlineCoop.version &+ 1
        #expect(OnlineMessage.decode(wrongVersion, from: .host) == nil)
        var wrongMagic = state
        wrongMagic[0] = 0
        #expect(OnlineMessage.decode(wrongMagic, from: .host) == nil)
        var unknownKind = OnlineMessage.rematch.encoded
        unknownKind[2] = 200
        #expect(OnlineMessage.decode(unknownKind, from: .guest) == nil)
        #expect(OnlineMessage.decode(Data(), from: .host) == nil)
        #expect(OnlineMessage.decode(Data("hello there".utf8), from: .guest) == nil)
    }

    @Test func oversizedMessagesAreDroppedUnread() {
        let padded = OnlineMessage.rematch.encoded + Data(count: OnlineCoop.maxGuestMessageBytes)
        #expect(OnlineMessage.decode(padded, from: .guest) == nil)
        #expect(OnlineMessage.decode(Data(count: OnlineCoop.maxHostMessageBytes + 1), from: .host) == nil)
    }

    @Test func trailingBytesAreRejected() {
        #expect(OnlineMessage.decode(OnlineMessage.rematch.encoded + Data([0]), from: .guest) == nil)
        #expect(OnlineMessage.decode(state + Data([0]), from: .host) == nil)
    }

    @Test func everyTruncationIsRejected() {
        for length in 0..<state.count {
            #expect(OnlineMessage.decode(state.prefix(length), from: .host) == nil)
        }
    }

    /// Random damage never crashes, and whatever does decode is still a legal game.
    @Test func corruptedSnapshotsNeverCrash() {
        var rng = SplitMix64(seed: 42)
        for _ in 0..<5_000 {
            var bytes = state
            for _ in 0...(rng.next() % 4) {
                let i = Int(rng.next() % UInt64(bytes.count))
                bytes[i] = UInt8(truncatingIfNeeded: rng.next())
            }
            guard case .state(_, _, let snapshot) = OnlineMessage.decode(bytes, from: .host) else { continue }
            #expect(snapshot.board.keys.allSatisfy(Grid.isCell))
            #expect(snapshot.board.values.allSatisfy { $0.color < Progression.colorCount })
            let dials = snapshot.dials.compactMap { $0?.vertex }
            #expect(dials.allSatisfy(Grid.isDial))
            _ = CoopGame(restoring: snapshot)
        }
    }

    @Test func aPlaceOffTheDialsIsRejected() {
        var bytes = OnlineMessage.input(seq: 1, .place(Grid.dials[0])).encoded
        bytes[bytes.count - 2] = 100 // k far outside the bin
        #expect(OnlineMessage.decode(bytes, from: .guest) == nil)
    }

    @Test func overlappingDialsAreRejected() {
        var snapshot = playedGame(seed: 2, seconds: 1).snapshot
        snapshot.dials[1] = snapshot.dials[0]
        let data = OnlineMessage.state(seq: 1, ack: 0, snapshot).encoded
        #expect(OnlineMessage.decode(data, from: .host) == nil)
    }

    @Test func aBadColourIsRejected() {
        var game = CoopGame(rng: SplitMix64(seed: 1))
        game.setBoardForTesting([Grid.cells[0]: Piece(id: 1, color: Progression.colorCount, power: nil, from: nil)])
        let data = OnlineMessage.state(seq: 1, ack: 0, game.snapshot).encoded
        #expect(OnlineMessage.decode(data, from: .host) == nil)
    }

    @Test func twoPiecesWithOneIDAreRejected() {
        var game = CoopGame(rng: SplitMix64(seed: 1))
        game.setBoardForTesting([
            Grid.cells[0]: Piece(id: 1, color: 0, power: nil, from: nil),
            Grid.cells[1]: Piece(id: 1, color: 1, power: nil, from: nil),
        ])
        let data = OnlineMessage.state(seq: 1, ack: 0, game.snapshot).encoded
        #expect(OnlineMessage.decode(data, from: .host) == nil)
    }
}

struct OnlineHostTests {
    @Test func theLimiterAllowsABurstThenTheRate() {
        var limiter = InputLimiter(rate: 10, burst: 3)
        let answers = [0, 0, 0, 0, 0.05, 0.15, 100, 100, 100, 100].map { limiter.allow(at: $0) }
        // Three at once, then nothing until a tenth of a second has refilled one;
        // a long quiet spell only refills to the burst
        #expect(answers == [true, true, true, false, false, true, true, true, true, false])
    }

    @Test func theHostTakesEachInputOnceAndInOrder() {
        var link = CoopHostLink()
        // The second is a repeat, and the last is older than the one before it
        let taken = [(1, 0.0), (1, 1), (3, 2), (2, 3)].map { link.accept(seq: UInt32($0.0), at: $0.1) }
        #expect(taken == [true, false, true, false])
        #expect(link.ack == 3)
    }

    @Test func aFloodIsCutOffButStillConfirmed() {
        var link = CoopHostLink()
        let taken = (1...100).filter { link.accept(seq: UInt32($0), at: 0) }
        #expect(taken.count == Int(OnlineCoop.inputBurst))
        // Dropped inputs count as seen, so the guest's prediction lets go of them
        #expect(link.ack == 100)
    }

    @Test func snapshotNumbersCountUp() {
        var link = CoopHostLink()
        let seqs = [link.nextStateSeq(), link.nextStateSeq()]
        #expect(seqs == [1, 2])
    }

    @Test func exactlyOneDeviceHosts() {
        var rng = SplitMix64(seed: 9)
        for _ in 0..<1_000 {
            let a = OnlineCoop.Hello(nonce: rng.next() % 4, inviter: rng.next() % 2 == 0)
            let b = OnlineCoop.Hello(nonce: rng.next() % 4, inviter: rng.next() % 2 == 0)
            let ab = OnlineCoop.isHost(local: a, remote: b), ba = OnlineCoop.isHost(local: b, remote: a)
            if a == b {
                #expect(ab == nil && ba == nil)
            } else {
                #expect(ab != nil && ab == ba.map(!))
            }
        }
        // Whoever sent the invite hosts, whatever the nonces
        #expect(OnlineCoop.isHost(local: .init(nonce: 0, inviter: true), remote: .init(nonce: 9, inviter: false)) == true)
    }
}

struct CoopReplicaTests {
    /// The host's game and the guest's copy of it, both from the same first snapshot.
    private func pair() -> (game: CoopGame, link: CoopHostLink, replica: CoopReplica) {
        let game = CoopGame(mode: .endless, rng: SplitMix64(seed: 4))
        var link = CoopHostLink()
        let replica = CoopReplica(seq: link.nextStateSeq(), ack: link.ack, snapshot: game.snapshot)
        return (game, link, replica)
    }

    @Test func theGuestsOwnMoveShowsAtOnce() {
        var (_, _, replica) = pair()
        let before = replica.game.cursor(for: guest)
        let (seq, _) = replica.predict(.move(.right))
        #expect(seq == 1)
        #expect(replica.game.cursor(for: guest) != before)
        #expect(replica.unconfirmedCount == 1)
    }

    @Test func aMoveSurvivesASnapshotThatHasntSeenItYet() {
        var (game, link, replica) = pair()
        _ = replica.predict(.move(.right))
        let predicted = replica.game.cursor(for: guest)
        // The host sends a snapshot before the input reaches it
        _ = game.update(by: 0.05)
        replica.receive(seq: link.nextStateSeq(), ack: link.ack, snapshot: game.snapshot)
        #expect(replica.game.cursor(for: guest) == predicted)
        #expect(replica.unconfirmedCount == 1)
    }

    @Test func theHostsWordReplacesThePrediction() {
        var (game, link, replica) = pair()
        let (seq, _) = replica.predict(.move(.right))
        // The host takes the input, and its next snapshot confirms it
        let taken = link.accept(seq: seq, at: 0)
        #expect(taken)
        _ = game.apply(.move(.right), from: guest)
        replica.receive(seq: link.nextStateSeq(), ack: link.ack, snapshot: game.snapshot)
        #expect(replica.unconfirmedCount == 0)
        #expect(replica.game.cursor(for: guest) == game.cursor(for: guest))
    }

    @Test func aDroppedInputIsLetGo() {
        var (game, link, replica) = pair()
        let start = replica.game.cursor(for: guest)
        let (seq, _) = replica.predict(.move(.right))
        // Rate-limited away: confirmed but never applied
        for _ in 0..<Int(OnlineCoop.inputBurst) { _ = link.allow(at: 0) }
        let taken = link.accept(seq: seq, at: 0)
        #expect(!taken)
        replica.receive(seq: link.nextStateSeq(), ack: link.ack, snapshot: game.snapshot)
        #expect(replica.unconfirmedCount == 0)
        #expect(replica.game.cursor(for: guest) == start)
    }

    @Test func aLateSnapshotIsIgnored() {
        var (game, link, replica) = pair()
        let old = link.nextStateSeq()
        _ = game.update(by: 1)
        let newer = replica.receive(seq: link.nextStateSeq(), ack: 0, snapshot: game.snapshot)
        let older = replica.receive(seq: old, ack: 0, snapshot: CoopGame(rng: SplitMix64(seed: 99)).snapshot)
        #expect(newer && !older)
    }

    @Test func aPauseIsNeverAToggle() {
        var bytes = OnlineMessage.pause(true).encoded
        bytes[bytes.count - 1] = 2
        #expect(OnlineMessage.decode(bytes, from: .guest) == nil)
    }

    @Test func animatingMovesNothing() {
        var (game, _, replica) = pair()
        for _ in 0..<40 { _ = game.update(by: 0.05) }
        replica.receive(seq: 2, ack: 0, snapshot: game.snapshot)
        let board = replica.game.board, dials = CoopGame.players.map(replica.game.cursor)
        replica.animate(by: 10)
        #expect(replica.game.board == board && CoopGame.players.map(replica.game.cursor) == dials)
        #expect(replica.game.fallProgress == 1)
    }

    @Test func aRedoneTurnKeepsAnimatingFromWhereItWas() {
        var (game, link, replica) = pair()
        _ = replica.predict(.rotate(.clockwise))
        replica.animate(by: 0.06)
        replica.receive(seq: link.nextStateSeq(), ack: 0, snapshot: game.snapshot)
        let elapsed = replica.game.dialTurn(for: guest)?.elapsed ?? 0
        #expect(abs(elapsed - 0.06) < 1e-9)
    }

    @Test func theGuestCanOnlyMoveItsOwnDial() {
        var (_, _, replica) = pair()
        let hostDial = replica.game.cursor(for: host)
        for direction in [Direction.left, .left, .up, .down, .right, .right] {
            _ = replica.predict(.move(direction))
        }
        #expect(replica.game.cursor(for: host) == hostDial)
    }
}
