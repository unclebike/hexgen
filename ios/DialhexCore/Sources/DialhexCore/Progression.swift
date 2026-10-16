// Progression.swift — Colours, levels, pace, and scoring

public enum Palette {
    /// Piece colours as 0xRRGGBB, in order of introduction.
    public static let colors: [UInt32] = [
        0x4CAF50, // green
        0xFF9800, // orange
        0xFFEB3B, // yellow
        0xF44336, // red
        0x2196F3, // blue
        0x9C27B0, // purple
        0x00BCD4, // cyan
        0x2E7D32, // dark green
    ]
    public static let empty: UInt32 = 0x1A1A2E
    public static let background: UInt32 = 0x0F0F23
}

public enum Progression {
    public static let hexesPerLevel = 6
    /// Main mode is won after six hexes of every colour.
    public static let winHexes = hexesPerLevel * Palette.colors.count
    public static let initialColors = [0, 1]

    /// Seconds between new triangles.
    public static func spawnInterval(level: Int) -> Double {
        max(0.7, 1.8 - 0.15 * Double(level - 2))
    }

    /// Points for clearing `count` hexes at once.
    public static func score(hexes count: Int, level: Int) -> Int {
        count * 100 * level
    }
}
