// HighScores.swift — Best score per mode, kept in UserDefaults

import Foundation

public struct HighScores {
    private static let key = "dialhex_highscores"
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    private var all: [Mode: Int] {
        get {
            guard let data = defaults.data(forKey: Self.key),
                  let scores = try? JSONDecoder().decode([Mode: Int].self, from: data) else { return [:] }
            return scores
        }
        nonmutating set {
            defaults.set(try? JSONEncoder().encode(newValue), forKey: Self.key)
        }
    }

    public func best(for mode: Mode) -> Int { all[mode] ?? 0 }

    /// Save `score` if it beats the record for `mode`. Returns true if it did.
    @discardableResult
    public func record(_ score: Int, for mode: Mode) -> Bool {
        guard score > best(for: mode) else { return false }
        all[mode] = score
        return true
    }
}
