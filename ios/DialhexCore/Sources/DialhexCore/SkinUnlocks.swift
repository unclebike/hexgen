// SkinUnlocks.swift — Lifetime progress toward skins, kept in UserDefaults (mirrors skins.js)
//
// The first skin is always open. Every MAIN win and every lifetime-hexes
// milestone reached opens the next one, in order.

import Foundation

public struct SkinUnlocks {
    public struct Progress: Codable, Equatable, Sendable {
        public var mainWins = 0
        public var hexes = 0
    }

    private static let key = "dialhex_progress"
    public let skinCount: Int
    public let milestones: [Int]
    private let defaults: UserDefaults

    public init(skinCount: Int, milestones: [Int], defaults: UserDefaults = .standard) {
        self.skinCount = skinCount
        self.milestones = milestones
        self.defaults = defaults
    }

    public var progress: Progress {
        get {
            guard let data = defaults.data(forKey: Self.key),
                  let saved = try? JSONDecoder().decode(Progress.self, from: data) else { return Progress() }
            return saved
        }
        nonmutating set {
            defaults.set(try? JSONEncoder().encode(newValue), forKey: Self.key)
        }
    }

    /// How many skins, counting from the first, are open at `progress`.
    public func unlockedCount(at progress: Progress) -> Int {
        let reached = milestones.filter { progress.hexes >= $0 }.count
        return min(skinCount, 1 + progress.mainWins + reached)
    }

    public var unlockedCount: Int { unlockedCount(at: progress) }

    /// Open every skin (the hidden 20-taps-on-the-logo shortcut). Tops progress
    /// up rather than replacing it, so a real record is never lost.
    public func unlockAll() {
        var next = progress
        next.hexes = max(next.hexes, milestones.max() ?? 0)
        next.mainWins = max(next.mainWins, skinCount - 1 - milestones.count)
        progress = next
    }

    /// Bank a finished game. Returns the indices of the skins it opened.
    @discardableResult
    public func record(hexes: Int, mainWin: Bool) -> Range<Int> {
        var next = progress
        let before = unlockedCount(at: next)
        next.hexes += hexes
        if mainWin { next.mainWins += 1 }
        progress = next
        return before..<unlockedCount(at: next)
    }
}
