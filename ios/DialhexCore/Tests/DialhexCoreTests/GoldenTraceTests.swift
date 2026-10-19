// GoldenTraceTests.swift — Pins Game's exact behaviour across long seeded runs
//
// Each trace plays a seeded game with seeded random input for a few thousand
// frames and folds everything observable (events, board, score, dial, turn)
// into a running FNV-1a digest. The expected digests were recorded from Game
// before its rules moved into the shared engine, so any drift in spawning,
// gravity, clears, powers, or the dial shows up here.

import Testing
@testable import DialhexCore

/// FNV-1a, 64-bit: stable across runs and processes, unlike `Hasher`.
private struct Digest {
    private(set) var value: UInt64 = 0xCBF2_9CE4_8422_2325

    mutating func add(_ text: String) {
        for byte in text.utf8 {
            value ^= UInt64(byte)
            value &*= 0x0000_0100_0000_01B3
        }
        value ^= 0xFF // separator
        value &*= 0x0000_0100_0000_01B3
    }
}

/// Everything a player or renderer can see of a game, in a fixed order.
private func snapshot(_ game: Game) -> String {
    let cells = game.board.keys.sorted { ($0.r, $0.c) < ($1.r, $1.c) }
    let pieces = cells.map { cell -> String in
        let p = game.board[cell]!
        let from = p.from.map { "\($0.r),\($0.c)" } ?? "-"
        return "\(cell.r),\(cell.c):\(p.id)/\(p.color)/\(String(describing: p.power))/\(from)/\(p.clearTime)"
    }.joined(separator: ";")
    let turn = game.dialTurn.map {
        "\($0.vertex.k),\($0.vertex.j),\($0.direction.rawValue),\($0.pieceIDs.sorted()),\($0.elapsed)"
    } ?? "-"
    return [
        "\(game.phase)", "\(game.won)", "\(game.score)", "\(game.level)", "\(game.hexesCleared)",
        "\(game.hexesThisLevel)", "\(game.activeColors)", "\(game.cursor.vertex.k),\(game.cursor.vertex.j),\(game.cursor.stickyJ)",
        turn, "\(String(describing: game.sprintTimeRemaining))", "\(game.fallProgress)", pieces,
    ].joined(separator: "|")
}

private struct TraceResult: Sendable {
    var digest: UInt64
    var events: [String: Int] = [:]
}

/// Play `frames` frames of `game` with input chosen by `inputSeed`, folding each frame into a digest.
private func trace(_ game: inout Game, inputSeed: UInt64, frames: Int) -> TraceResult {
    var input = SplitMix64(seed: inputSeed)
    var digest = Digest()
    var counts: [String: Int] = [:]
    func record(_ events: [GameEvent]) {
        for event in events {
            digest.add("\(event)")
            let name = "\(event)".prefix { $0 != "(" }
            counts[String(name), default: 0] += 1
        }
    }
    let directions: [Direction] = [.up, .down, .left, .right]
    for frame in 0..<frames {
        let roll = input.next() % 100
        switch roll {
        case 0..<12: game.moveCursor(directions[Int(input.next() % 4)])
        case 12..<24: record(game.rotate(input.next() % 2 == 0 ? .clockwise : .counterClockwise))
        case 24..<27:
            let dial = Grid.dials[Int(input.next() % UInt64(Grid.dials.count))]
            record(game.tap(at: Grid.position(of: dial)))
        case 27: game.moveCursor(to: Grid.dials[Int(input.next() % UInt64(Grid.dials.count))])
        case 28 where frame % 7 == 0: game.togglePause()
        case 29: game.togglePause()
        default: break
        }
        // Mostly 60 fps, with the odd long frame to exercise the catch-up limit
        let dt = input.next() % 200 == 0 ? 0.9 : 1.0 / 60
        record(game.update(by: dt))
        digest.add(snapshot(game))
    }
    return TraceResult(digest: digest.value, events: counts)
}

/// A two-colour bin, mostly full and close to many hexes, so random turning
/// clears often; a sprinkling of power pieces fire when they go.
private func busyBoard() -> Board {
    var board = makeBoard(Grid.cells.filter { Grid.center(of: $0).x > 0.5 }.map { ($0.r, $0.c, ($0.r / 2 + $0.c / 3) & 1) })
    for (i, cell) in board.keys.sorted(by: { ($0.r, $0.c) < ($1.r, $1.c) }).enumerated() where i % 9 == 0 {
        board[cell]?.power = i % 2 == 0 ? .drain : .swap
    }
    return board
}

struct GoldenTraceTests {
    struct Case: Sendable, CustomTestStringConvertible {
        let name: String
        let mode: Mode
        let speed: Speed
        let seed: UInt64
        let busy: Bool
        let expected: UInt64
        var testDescription: String { name }
    }

    static let cases: [Case] = [
        Case(name: "main normal", mode: .main, speed: .normal, seed: 1, busy: false, expected: 0x32d8_1d91_4fc2_c7b0),
        Case(name: "endless fast", mode: .endless, speed: .fast, seed: 2, busy: false, expected: 0xf55c_a47f_e60a_b5c7),
        Case(name: "sprint slow", mode: .sprint, speed: .slow, seed: 3, busy: false, expected: 0xa1c0_c6a9_5c03_4fab),
        Case(name: "main busy", mode: .main, speed: .normal, seed: 4, busy: true, expected: 0xc359_44d9_eb7b_a922),
        Case(name: "endless busy", mode: .endless, speed: .fast, seed: 5, busy: true, expected: 0xef13_66cd_6452_0e11),
    ]

    /// Each case's trace, played once and shared by both tests.
    private static let results: [String: TraceResult] = Dictionary(uniqueKeysWithValues: cases.map { c in
        var game = Game(mode: c.mode, speed: c.speed, rng: SplitMix64(seed: c.seed))
        if c.busy { game.setBoardForTesting(busyBoard()) }
        return (c.name, trace(&game, inputSeed: c.seed &* 31, frames: 12_000))
    })

    @Test(arguments: cases)
    func gameMatchesRecordedTrace(_ c: Case) {
        let digest = Self.results[c.name]?.digest ?? 0
        #expect(digest == c.expected, "digest \(String(digest, radix: 16))")
    }

    /// The traces only mean something if they reach the interesting rules.
    @Test func tracesCoverEveryKindOfEvent() {
        var seen: [String: Int] = [:]
        for result in Self.results.values { seen.merge(result.events, uniquingKeysWith: +) }
        for kind in ["spawn", "rotate", "clear", "power", "levelUp", "gameOver"] {
            #expect(seen[kind, default: 0] > 0, "no \(kind) in any trace")
        }
    }
}
