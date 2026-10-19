// Versus.swift — Split-screen versus: one ordinary Game per player, side by side
//
// Every board is a plain `Game`, dealt from the same seed and run on the same
// clock, so each one plays exactly like a solo game. Versus only adds who's
// out, who won, and a pause that covers everyone.

public struct Versus {
    public enum Rule: String, CaseIterable, Sendable, Codable {
        /// Highest score when the sprint clock runs out.
        case sprintRace
        /// Endless boards; a full bin is out, and the last one left wins.
        case survival
        /// Main boards; the first to win, or the last one left, wins.
        case firstToWin

        public var mode: Mode {
            switch self {
            case .sprintRace: .sprint
            case .survival: .endless
            case .firstToWin: .main
            }
        }
    }

    public enum Event: Sendable, Equatable {
        case board(PlayerID, GameEvent)
        /// A bin filled up (or the player left the match); their board stops.
        case eliminated(PlayerID)
        case matchOver(winners: [PlayerID])
    }

    public static let playerRange = 2...PlayerID.maxPlayers

    public let rule: Rule
    /// The players in the match, P1 first.
    public let players: [PlayerID]
    public private(set) var boards: [PlayerID: Game] = [:]
    public private(set) var phase: Phase = .playing
    /// Players knocked out so far, in the order they went.
    public private(set) var eliminated: [PlayerID] = []
    /// Set once the match is over; more than one on a tie.
    public private(set) var winners: [PlayerID]?
    private var forfeited: Set<PlayerID> = []

    public init(players: [PlayerID], rule: Rule, seed: UInt64) {
        let players = players.sorted()
        precondition(Self.playerRange.contains(players.count), "versus needs 2–4 players")
        precondition(Set(players).count == players.count, "duplicate player")
        self.rule = rule
        self.players = players
        for player in players {
            boards[player] = Game(mode: rule.mode, rng: SeededGenerator(seed: seed))
        }
    }

    /// Players whose boards are still going.
    public var activePlayers: [PlayerID] { players.filter { !isOut($0) } }

    /// A board stops when its own game ends or its player leaves.
    public func isOut(_ player: PlayerID) -> Bool {
        forfeited.contains(player) || boards[player]?.phase == .gameOver
    }

    /// Advance every board still going by `dt` seconds, P1 first.
    public mutating func update(by dt: Double) -> [Event] {
        guard phase == .playing else { return [] }
        var events: [Event] = []
        var finished: [PlayerID] = []
        for player in activePlayers {
            guard var game = boards[player] else { continue }
            for event in game.update(by: dt) { events.append(.board(player, event)) }
            boards[player] = game
            if game.phase == .gameOver { finished.append(player) }
        }
        settle(finished, &events)
        return events
    }

    /// One player's move or turn, on their own board only.
    public mutating func apply(_ input: PlayerInput, from player: PlayerID) -> [Event] {
        guard phase == .playing, !isOut(player), var game = boards[player] else { return [] }
        var events: [GameEvent] = []
        switch input {
        case .move(let direction): game.moveCursor(direction)
        case .place(let vertex): game.moveCursor(to: vertex)
        case .rotate(let direction): events = game.rotate(direction)
        }
        boards[player] = game
        return events.map { .board(player, $0) }
    }

    /// Any player pauses (and resumes) every board at once.
    public mutating func togglePause() {
        switch phase {
        case .playing: phase = .paused
        case .paused: phase = .playing
        case .gameOver: return
        }
        // Keep each board's own phase in step, so a renderer can follow it
        for player in activePlayers {
            boards[player]?.togglePause()
        }
    }

    /// Go on without a player (their controller dropped and nobody took over).
    public mutating func forfeit(_ player: PlayerID) -> [Event] {
        guard phase != .gameOver, players.contains(player), !isOut(player) else { return [] }
        forfeited.insert(player)
        var events: [Event] = []
        settle([player], &events)
        return events
    }

    /// Knock out the boards that just stopped, then end the match if the rule says so.
    private mutating func settle(_ finished: [PlayerID], _ events: inout [Event]) {
        guard !finished.isEmpty else { return }
        let won = finished.filter { boards[$0]?.won == true && !forfeited.contains($0) }
        // A sprint board stopping on the clock isn't knocked out; a full bin is
        for player in finished where !won.contains(player) && !isTimeUp(player) {
            eliminated.append(player)
            events.append(.eliminated(player))
        }

        let active = activePlayers
        let result: [PlayerID]?
        if !won.isEmpty {
            result = won
        } else if rule == .sprintRace {
            // A score race: a full bin only stops your scoring, so wait for the clock
            result = active.isEmpty ? topScorers() : nil
        } else if active.count == 1 {
            result = active
        } else if active.isEmpty {
            result = finished // they all went out together
        } else {
            result = nil
        }
        if let result { endMatch(result, &events) }
    }

    private func isTimeUp(_ player: PlayerID) -> Bool {
        !forfeited.contains(player) && boards[player]?.sprintTimeRemaining == 0
    }

    /// Everyone who didn't leave the match, with the best score.
    private func topScorers() -> [PlayerID] {
        let stayed = players.filter { !forfeited.contains($0) }
        let best = stayed.compactMap { boards[$0]?.score }.max()
        return stayed.filter { boards[$0]?.score == best }
    }

    private mutating func endMatch(_ result: [PlayerID], _ events: inout [Event]) {
        winners = result
        phase = .gameOver
        events.append(.matchOver(winners: result))
    }
}

// MARK: - Testing

extension Versus {
    /// Test hook: set up one player's board.
    mutating func setBoardForTesting(_ board: Board, for player: PlayerID) {
        boards[player]?.setBoardForTesting(board)
    }
}
