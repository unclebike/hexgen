// ControllerProtocolTests.swift — The phone ↔ TV messages survive JSON, and the TV's door rules

import Foundation
import Testing
@testable import DialhexCore

private func roundTrip<T: Codable & Equatable>(_ value: T) throws -> T {
    try JSONDecoder().decode(T.self, from: JSONEncoder().encode(value))
}

struct ControllerProtocolTests {
    static let phoneMessages: [PhoneMessage] = [
        .hello(Hello(peer: "A1B2", name: "iPhone", joinCode: "0427")),
        .direction(.up, pressed: true), .direction(.down, pressed: false),
        .direction(.left, pressed: true), .direction(.right, pressed: false),
        .place(Vertex(k: 6, j: 0)), .rotate(.clockwise), .rotate(.counterClockwise),
        .confirm, .cancel, .pause, .ping(123_456_789), .bye,
    ]

    static let tvMessages: [TVMessage] = [
        .welcome(PlayerID(2)), .rejected(.wrongVersion), .rejected(.wrongCode), .rejected(.full), .rejected(.matchRunning),
        .screen(.menu), .screen(.lobby), .screen(.playing), .screen(.paused), .screen(.over(won: true)), .screen(.over(won: false)),
        .haptic(.rotate), .haptic(.clear(hexes: 3)), .haptic(.power), .haptic(.levelUp), .haptic(.gameOver),
        .dial(.empty), .dial(DialPieces(vertex: Vertex(k: 4, j: 2), colors: [0, nil, 3, 7, nil, 1])),
        .pong(42),
    ]

    @Test(arguments: phoneMessages)
    func phoneMessagesRoundTrip(message: PhoneMessage) throws {
        #expect(try roundTrip(message) == message)
    }

    @Test(arguments: tvMessages)
    func tvMessagesRoundTrip(message: TVMessage) throws {
        #expect(try roundTrip(message) == message)
    }

    @Test func directionsTravelByName() throws {
        let json = try #require(String(data: JSONEncoder().encode([Direction.up, .left]), encoding: .utf8))
        #expect(json == #"["up","left"]"#)
    }

    @Test func garbageIsAnErrorNotACrash() {
        let bad = [#"{"direction":{"_0":"sideways","pressed":true}}"#, #"{"teleport":{}}"#, "not json", "{}"]
        for text in bad {
            #expect(throws: (any Error).self) { try JSONDecoder().decode(PhoneMessage.self, from: Data(text.utf8)) }
        }
    }

    @Test func theTVChecksVersionAndCode() {
        let hello = Hello(peer: "p", name: "iPhone", joinCode: "1234")
        #expect(ControllerProtocol.admit(hello, joinCode: "1234") == nil)
        #expect(ControllerProtocol.admit(hello, joinCode: "9999") == .wrongCode)
        var old = hello
        old.version = ControllerProtocol.version - 1
        #expect(ControllerProtocol.admit(old, joinCode: "1234") == .wrongVersion)
    }

    @Test func joinCodesAreFourDigits() {
        var rng = SeededGenerator(seed: 3)
        for _ in 0..<200 {
            let code = ControllerProtocol.makeJoinCode(using: &rng)
            #expect(code.count == 4)
            #expect(code.allSatisfy { $0.isNumber })
        }
    }

    // MARK: - The dial on the phone

    @Test func everyDialHasSixDistinctSlots() {
        for dial in Grid.dials {
            let order = DialPieces.screenOrder(dial)
            #expect(order.count == 6)
            #expect(Set(order) == Set(Grid.dialCells(dial)))
        }
    }

    /// The phone's guess at a turn matches the turn the game really makes.
    @Test(arguments: [RotationDirection.clockwise, .counterClockwise])
    func aTurnOnThePhoneMatchesTheBoard(direction: RotationDirection) {
        let dial = vertex(6, 0)
        var board = makeBoard(Grid.dialCells(dial).enumerated().map { i, cell in (cell.r, cell.c, i) })
        let before = DialPieces.at(dial, on: board)
        #expect(Dial.rotate(&board, at: dial, direction: direction))
        #expect(DialPieces.at(dial, on: board) == before.turned(direction))
    }

    @Test func emptyAndClearingCellsShowEmpty() {
        let dial = vertex(6, 0)
        let cells = DialPieces.screenOrder(dial)
        var board = makeBoard([(cells[0].r, cells[0].c, 4), (cells[1].r, cells[1].c, 5)])
        board[cells[1]]?.clearTime = 0.2
        #expect(DialPieces.at(dial, on: board) == DialPieces(vertex: dial, colors: [4, nil, nil, nil, nil, nil]))
    }
}
