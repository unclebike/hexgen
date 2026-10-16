// TestSupport.swift — Shared helpers for the DialhexCore tests
//
// Expected values throughout these tests were computed by running the
// original JS modules (grid.js, dropper.js, rotation.js, hexdetect.js,
// gamestate.js) under Node, so the Swift port is checked against the real
// JS behaviour. JS works in milliseconds; Swift in seconds.

import XCTest
@testable import DialhexCore

/// Deterministic SplitMix64 generator, so Game runs are reproducible.
struct SplitMix64: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

/// Ids for hand-placed pieces start here, well clear of the ids a Game hands
/// to the pieces it spawns (0, 1, 2, ...).
let testPieceBaseID = 10_000

/// Build a board from (r, c, color) triples. The piece's color doubles as a
/// tag, so tests can follow individual pieces around.
func makeBoard(_ pieces: [(Int, Int, Int)]) -> Board {
    var board: Board = [:]
    for (i, p) in pieces.enumerated() {
        board[Cell(r: p.0, c: p.1)] = Piece(id: testPieceBaseID + i, color: p.2, power: nil, from: nil, clearTime: 0)
    }
    return board
}

/// The board's colours by cell, for comparing whole layouts.
func colors(_ board: Board) -> [Cell: Int] {
    board.mapValues { $0.color }
}

/// Only the hand-placed pieces (not ones a Game spawned), by cell.
func placedColors(_ board: Board) -> [Cell: Int] {
    board.filter { $0.value.id >= testPieceBaseID }.mapValues { $0.color }
}

/// An expected layout from (r, c, color) triples.
func layout(_ pieces: [(Int, Int, Int)]) -> [Cell: Int] {
    var result: [Cell: Int] = [:]
    for p in pieces { result[Cell(r: p.0, c: p.1)] = p.2 }
    return result
}

func cell(_ r: Int, _ c: Int) -> Cell { Cell(r: r, c: c) }
func vertex(_ k: Int, _ j: Int) -> Vertex { Vertex(k: k, j: j) }

func assertPoint(
    _ actual: LatticePoint, _ x: Double, _ y: Double, accuracy: Double = 1e-12,
    file: StaticString = #filePath, line: UInt = #line
) {
    XCTAssertEqual(actual.x, x, accuracy: accuracy, "x", file: file, line: line)
    XCTAssertEqual(actual.y, y, accuracy: accuracy, "y", file: file, line: line)
}

extension GameEvent {
    var isSpawn: Bool {
        if case .spawn = self { return true }
        return false
    }
}
