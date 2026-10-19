// Progression.swift — Levels, pace, and scoring
// The colours themselves belong to the app's skins (skins.json).

/// How fast triangles fall and arrive. Turning and clearing keep their timing.
public enum Speed: String, CaseIterable, Sendable, Codable {
    case slow, normal, fast

    /// Multiplies the time per fall step and between spawns.
    public var pace: Double {
        switch self {
        case .slow: 1.4
        case .normal: 1
        case .fast: 0.7
        }
    }

    /// Scales the points for a clear, so a slower game can't outscore a faster one for free.
    public var pointsMultiplier: Double {
        switch self {
        case .slow: 0.5
        case .normal: 1
        case .fast: 1.5
        }
    }
}

public enum Progression {
    public static let hexesPerLevel = 6
    /// Piece colours, introduced one per level.
    public static let colorCount = 8
    /// Main mode is won after six hexes of every colour.
    public static let winHexes = hexesPerLevel * colorCount
    public static let initialColors = [0, 1]

    /// Seconds between new triangles.
    public static func spawnInterval(level: Int) -> Double {
        max(0.7, 1.8 - 0.15 * Double(level - 2))
    }

    // MARK: - Assisted games
    //
    // A new player's first few games ease them in: the opening level is slower,
    // each new colour arrives without also speeding things up, and a full bin
    // is drained once instead of ending the game. Points are scored as normal.

    /// Finished games a new player is assisted in, unless they win MAIN first.
    public static let assistedGames = 3
    /// The opening level of an assisted game spawns this much slower.
    public static let assistedOpeningPace = Speed.slow.pace
    /// After the opening, an assisted game's pace lags this many levels behind.
    public static let assistedPaceLag = 2

    /// Seconds between new triangles, eased in an assisted game.
    public static func spawnInterval(level: Int, assisted: Bool) -> Double {
        guard assisted else { return spawnInterval(level: level) }
        if level <= 2 { return spawnInterval(level: 2) * assistedOpeningPace }
        return spawnInterval(level: max(2, level - assistedPaceLag))
    }

    /// Points for clearing `count` hexes at once.
    public static func score(hexes count: Int, level: Int) -> Int {
        count * 100 * level
    }
}
