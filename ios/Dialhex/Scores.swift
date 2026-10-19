// Scores.swift — Each mode's best score, its Game Center leaderboard, and sign-in
//
// The one place scores live. The device keeps each mode's best (`HighScores`),
// Game Center keeps the leaderboards, and every sync makes the two agree: a
// better Game Center score is taken back onto the device (after a reinstall, or
// from another device), and a better device score is sent up (played signed
// out or offline, or a send that failed).
//
// Game Center fails quietly: a player who isn't signed in (or is offline)
// still gets their bests, just no leaderboards.

import DialhexCore
import GameKit
import Observation
import UIKit

/// One mode's leaderboard, as the menu shows it: the world's best and where the player stands.
struct LeaderboardSummary: Equatable {
    var topName: String
    var topScore: Int
    /// The player's own best and rank; nil until they've posted a score.
    var playerScore: Int?
    var playerRank: Int?
}

@MainActor @Observable
final class Scores {
    /// Leaderboard IDs; these must match the leaderboards set up for Game Center.
    static func leaderboardID(for mode: Mode) -> String { "dialhex.\(mode.rawValue)" }

    /// Each mode's best, on this device or Game Center, whichever is higher.
    private(set) var bests: [Mode: Int]
    /// Each mode's Game Center leaderboard, once loaded.
    private(set) var leaderboards: [Mode: LeaderboardSummary] = [:]
    private(set) var isAuthenticated = false

    @ObservationIgnored private let local: HighScores
    /// Whether the menu is showing, so the access point only appears there.
    @ObservationIgnored private var onMenu = true
    @ObservationIgnored private var syncing = false
    /// A sync was asked for while one was running; run another when it ends.
    @ObservationIgnored private var syncAgain = false

    init(local: HighScores = HighScores()) {
        self.local = local
        bests = Dictionary(uniqueKeysWithValues: Mode.allCases.map { ($0, local.best(for: $0)) })
    }

    func best(for mode: Mode) -> Int { bests[mode] ?? 0 }

    /// Record a finished game. Every game goes to Game Center, not just records:
    /// the leaderboard keeps the best, and challenges count each attempt.
    /// Returns true if it's a new best.
    @discardableResult
    func finish(_ score: Int, mode: Mode) -> Bool {
        let isBest = keep(score, for: mode)
        if isAuthenticated && score > 0 {
            Task {
                try? await Self.submit(score, for: mode)
                await sync()
            }
        }
        return isBest
    }

    // MARK: - Game Center

    /// Sign the local player in. GameKit calls the handler again whenever the
    /// player's state changes, such as signing out in Settings.
    func authenticate() {
        GKAccessPoint.shared.location = .topLeading
        GKAccessPoint.shared.showHighlights = false
        GKLocalPlayer.local.authenticateHandler = { [weak self] viewController, _ in
            Task { @MainActor in
                guard let self else { return }
                if let viewController {
                    Self.present(viewController)
                    return
                }
                self.isAuthenticated = GKLocalPlayer.local.isAuthenticated
                TipState.gameCenterSignedIn = self.isAuthenticated
                self.updateAccessPoint()
                if self.isAuthenticated {
                    await self.sync()
                } else {
                    self.leaderboards = [:]
                }
            }
        }
    }

    /// Show the access point on the menu and hide it in play, where it would cover the board.
    func setOnMenu(_ onMenu: Bool) {
        self.onMenu = onMenu
        updateAccessPoint()
    }

    /// Open the dashboard on a mode's leaderboard.
    func showLeaderboard(for mode: Mode) {
        guard isAuthenticated else { return }
        if #available(iOS 18, tvOS 18, *) {
            GKAccessPoint.shared.trigger(leaderboardID: Self.leaderboardID(for: mode), playerScope: .global, timeScope: .allTime)
        } else {
            GKAccessPoint.shared.trigger(state: .leaderboards) {}
        }
    }

    /// Save `score` on the device if it beats the best. Returns true if it did.
    private func keep(_ score: Int, for mode: Mode) -> Bool {
        guard local.record(score, for: mode) else { return false }
        bests[mode] = score
        return true
    }

    /// Load the leaderboards and make them agree with the device: take back a
    /// better Game Center score, and send up a better device one.
    private func sync() async {
        guard isAuthenticated else { return }
        guard !syncing else {
            syncAgain = true
            return
        }
        syncing = true
        defer { syncing = false }
        repeat {
            syncAgain = false
            var (summaries, loaded) = await Self.loadSummaries()
            var sent = false
            // Only modes whose leaderboard loaded: an unknown Game Center score
            // isn't a reason to send the device best again
            for mode in loaded {
                let remote = summaries[mode]?.playerScore ?? 0
                if remote > best(for: mode) {
                    _ = keep(remote, for: mode)
                } else if best(for: mode) > remote {
                    if (try? await Self.submit(best(for: mode), for: mode)) != nil { sent = true }
                }
            }
            if sent { (summaries, _) = await Self.loadSummaries() }
            leaderboards = summaries
        } while syncAgain && isAuthenticated
    }

    private static func submit(_ score: Int, for mode: Mode) async throws {
        try await GKLeaderboard.submitScore(score, context: 0, player: GKLocalPlayer.local,
                                            leaderboardIDs: [leaderboardID(for: mode)])
    }

    /// The top entry and the player's own entry on every mode's all-time
    /// leaderboard, and which modes loaded. A mode that loaded but has no scores
    /// yet is in `loaded` without a summary.
    private static func loadSummaries() async -> (summaries: [Mode: LeaderboardSummary], loaded: Set<Mode>) {
        let ids = Mode.allCases.map(leaderboardID)
        guard let leaderboards = try? await GKLeaderboard.loadLeaderboards(IDs: ids) else { return ([:], []) }
        var summaries: [Mode: LeaderboardSummary] = [:]
        var loaded: Set<Mode> = []
        for leaderboard in leaderboards {
            guard let mode = Mode.allCases.first(where: { leaderboardID(for: $0) == leaderboard.baseLeaderboardID }),
                  let (local, top, _) = try? await leaderboard.loadEntries(for: .global, timeScope: .allTime,
                                                                          range: NSRange(location: 1, length: 1))
            else { continue }
            loaded.insert(mode)
            guard let first = top.first else { continue }
            summaries[mode] = LeaderboardSummary(topName: first.player.displayName, topScore: first.score,
                                                 playerScore: local?.score, playerRank: local?.rank)
        }
        return (summaries, loaded)
    }

    /// Not on Apple TV: there the access point is a focusable button, and the
    /// remote's input belongs to the game, so it could never be reached.
    private func updateAccessPoint() {
        #if os(tvOS)
        GKAccessPoint.shared.isActive = false
        #else
        GKAccessPoint.shared.isActive = isAuthenticated && onMenu
        #endif
    }

    /// Present GameKit's sign-in sheet over whatever is on screen.
    private static func present(_ viewController: UIViewController) {
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive } ?? UIApplication.shared.connectedScenes.first as? UIWindowScene
        var top = scene?.keyWindow?.rootViewController
        while let presented = top?.presentedViewController { top = presented }
        top?.present(viewController, animated: true)
    }
}
