// Score.swift — What a skin's music is made of
//
// A score holds a pool of chords and some musical properties, not a melody,
// plus the rules for what in the game the music reacts to. The `Conductor`
// turns it into notes as the game plays. Each skin has its own.

public struct MusicScore: Sendable {
    /// One piece colour's voice: where it sits and the chord degrees it steps
    /// through, one per triangle of that colour. It starts with the first two
    /// steps and gains one more every level, so the tune grows with the game.
    public struct Voice: Sendable {
        /// MIDI notes, at least an octave.
        public let range: ClosedRange<Int>
        /// Chord degrees (0 root, 1 third, 2 fifth, 3 seventh, 4 added tone).
        public let motif: [Int]
        /// Seconds each note rings.
        public let length: Double
    }

    /// What in the game moves the harmony. Whatever a score leaves out, its
    /// chords drift on their own clock regardless.
    public struct Reactions: OptionSet, Sendable {
        public let rawValue: Int
        public init(rawValue: Int) { self.rawValue = rawValue }

        /// A level-up moves to a far chord (one shared tone), strummed by the new colour's voice.
        public static let levels = Reactions(rawValue: 1 << 0)
        /// A clear of two hexes or more changes chord at the next boundary.
        public static let combos = Reactions(rawValue: 1 << 1)
        /// A nearly full bin holds the tension chord until it empties again.
        public static let danger = Reactions(rawValue: 1 << 2)
        /// Sprint's last stretch changes chord on every boundary.
        public static let sprintFinish = Reactions(rawValue: 1 << 3)
    }

    /// Where the music starts, and the safe chord to fall back to.
    public let home: Chord
    /// Every chord the network may move to, home included.
    public let chords: [Chord]
    /// Held, unresolved, while the bin is nearly full; once the danger passes the music resolves home.
    public let tension: Chord
    /// One per colour, in unlock order.
    public let voices: [Voice]
    /// Where the pad's four voices live, in MIDI notes.
    public let padRange: ClosedRange<Int>
    /// Chords change only on boundaries this many fall steps apart (16ths).
    public let unitSteps: Int
    /// Units a chord lasts when nothing in the game asks for a change.
    public let unitsPerChange: Int
    /// Shared tones for an unprompted change, picked at random: 3 is subtle, 2 a clear move, 1 a jump.
    public let calmSharing: [Int]
    /// Shared tones for the change a combo asks for.
    public let comboSharing: Int
    public let reactions: Reactions
    /// Board fill (0…1): above the upper bound the music holds the tension
    /// chord, and it lets go below the lower one.
    public let danger: ClosedRange<Double>
    /// Seconds left in a sprint when the finish starts.
    public let sprintFinish: Double
    /// Drums under the music, for scores that have them.
    public var groove: Groove? = nil
}

/// A chill hop drum bar on the step clock: kick and snare from the start,
/// hats and ghost notes joining as colours do, vinyl crackle under it all.
/// While the bin is nearly full it thins to a kick on each downbeat.
public struct Groove: Sendable {
    /// Two bars of 16ths per drum, "x" a hit and "." a rest; hats use "X" for an accent.
    public let kick: [String]
    public let snare: [String]
    /// Quiet snares, between the backbeats.
    public let ghost: [String]
    public let hat: [String]
    /// How late the off 16ths land, as a fraction of a 16th: 0 is straight, 1/3 a triplet shuffle.
    public let swing: Double
    /// Above this tempo (quarter notes a minute, a fall step being a 16th) the groove plays half-time,
    /// so the fast speed still sits in chill hop's range.
    public let halfTimeAbove: Double
    /// Colours in play before the hats join, and before the ghost notes do.
    public let hatsFrom: Int
    public let ghostsFrom: Int
}

extension MusicScore {
    /// The score for a skin, by its id in skins.json; unknown ids get the base score.
    public static func forSkin(_ id: String) -> MusicScore {
        switch id {
        case "riso": riso
        case "crt": crt
        case "flash": flash
        case "mono": mono
        case "acid": acid
        default: base
        }
    }

    /// Eight voices shared by the scores: a bass, then registers spread so
    /// neighbouring colours don't sit on top of each other.
    static let voices = [
        Voice(range: 48...62, motif: [0, 2, 0, 1, 0, 3], length: 0.9),  // bass
        Voice(range: 60...74, motif: [1, 2, 3, 2, 4, 1], length: 0.6),
        Voice(range: 67...81, motif: [2, 4, 3, 1, 0, 2], length: 0.6),
        Voice(range: 55...69, motif: [3, 1, 2, 0, 4, 2], length: 0.7),
        Voice(range: 72...86, motif: [4, 2, 1, 3, 2, 0], length: 0.5),
        Voice(range: 64...78, motif: [0, 3, 4, 1, 2, 3], length: 0.6),
        Voice(range: 74...88, motif: [2, 1, 4, 3, 0, 1], length: 0.5),
        Voice(range: 50...64, motif: [1, 4, 0, 2, 3, 4], length: 0.8),
    ]

    /// Base: C major seventh chords, with a few borrowed from C minor for the
    /// bigger shifts a level-up asks for. Reacts to levels, combos and danger,
    /// over a swung chill hop groove.
    public static let base = MusicScore(
        home: Chord("Cmaj7", [0, 4, 7, 11], added: 2),
        chords: [
            Chord("Cmaj7", [0, 4, 7, 11], added: 2),
            Chord("Am7", [9, 0, 4, 7], added: 11),
            Chord("Fmaj7", [5, 9, 0, 4], added: 7),
            Chord("Em7", [4, 7, 11, 2], added: 9),
            Chord("Dm7", [2, 5, 9, 0], added: 4),
            Chord("Gadd9", [7, 11, 2, 9], added: 4),
            Chord("Cadd9", [0, 4, 7, 2], added: 9),
            Chord("Ebmaj7", [3, 7, 10, 2], added: 5),
            Chord("Abmaj7", [8, 0, 3, 7], added: 10),
            Chord("Bbadd9", [10, 2, 5, 0], added: 7),
        ],
        tension: Chord("G7sus4", [7, 0, 2, 5], added: 9),
        voices: voices,
        padRange: 52...72,
        unitSteps: 8,
        unitsPerChange: 4,
        calmSharing: [3, 3, 2],
        comboSharing: 2,
        reactions: [.levels, .combos, .danger],
        danger: 0.55...0.7,
        sprintFinish: 30,
        groove: Groove(
            //       1   2   3   4       1   2   3   4
            kick:  ["x.........x.....", "x......x..x....."],
            snare: ["....x.......x...", "....x.......x..."],
            ghost: [".........x......", ".........x.....x"],
            hat:   ["X.x.X.xxX.x.X.x.", "X.x.X.x.X.x.X.xx"],
            swing: 0.3,
            halfTimeAbove: 120,
            hatsFrom: 3,
            ghostsFrom: 5
        )
    )

    /// Riso: bright D major add9 chords that keep close to the pentatonic, with
    /// a lydian C for the jumps. Combos are what it answers: each one leaps.
    public static let riso = MusicScore(
        home: Chord("Dadd9", [2, 6, 9, 4], added: 11),
        chords: [
            Chord("Dadd9", [2, 6, 9, 4], added: 11),
            Chord("Bm7", [11, 2, 6, 9], added: 4),
            Chord("D6", [2, 6, 9, 11], added: 4),
            Chord("F#m7", [6, 9, 1, 4], added: 11),
            Chord("Gadd9", [7, 11, 2, 9], added: 4),
            Chord("Em7", [4, 7, 11, 2], added: 6),
            Chord("Aadd9", [9, 1, 4, 11], added: 6),
            Chord("Cmaj7", [0, 4, 7, 11], added: 2),
        ],
        tension: Chord("Asus4", [9, 2, 4, 7], added: 11),
        voices: voices,
        padRange: 54...74,
        unitSteps: 8,
        unitsPerChange: 4,
        calmSharing: [3, 2],
        comboSharing: 1,
        reactions: [.levels, .combos],
        danger: 0.55...0.7,
        sprintFinish: 30
    )

    /// CRT: D dorian, like an old console's minor tune, changing quickly. It
    /// watches the bin: its danger zone starts earlier than the others'.
    public static let crt = MusicScore(
        home: Chord("Dm7", [2, 5, 9, 0], added: 4),
        chords: [
            Chord("Dm7", [2, 5, 9, 0], added: 4),
            Chord("Fmaj7", [5, 9, 0, 4], added: 7),
            Chord("G7", [7, 11, 2, 5], added: 9),
            Chord("Am7", [9, 0, 4, 7], added: 11),
            Chord("Cadd9", [0, 4, 7, 2], added: 9),
            Chord("Em7", [4, 7, 11, 2], added: 9),
            Chord("Bbmaj7", [10, 2, 5, 9], added: 0),
        ],
        tension: Chord("A7sus4", [9, 2, 4, 7], added: 11),
        voices: voices,
        padRange: 50...70,
        unitSteps: 8,
        unitsPerChange: 2,
        calmSharing: [3, 2, 2],
        comboSharing: 2,
        reactions: [.levels, .danger],
        danger: 0.45...0.6,
        sprintFinish: 30
    )

    /// Flash: A minor synthwave (the i–VI–III–VII family), with a B♭ for the
    /// jumps. A sprint's last thirty seconds change chord every boundary.
    public static let flash = MusicScore(
        home: Chord("Am(add9)", [9, 0, 4, 11], added: 2),
        chords: [
            Chord("Am(add9)", [9, 0, 4, 11], added: 2),
            Chord("Fmaj7", [5, 9, 0, 4], added: 7),
            Chord("Cadd9", [0, 4, 7, 2], added: 11),
            Chord("Gadd9", [7, 11, 2, 9], added: 4),
            Chord("Dm(add9)", [2, 5, 9, 4], added: 0),
            Chord("Em7", [4, 7, 11, 2], added: 9),
            Chord("Bbmaj7", [10, 2, 5, 9], added: 0),
        ],
        tension: Chord("E7sus4", [4, 9, 11, 2], added: 7),
        voices: voices,
        padRange: 50...70,
        unitSteps: 8,
        unitsPerChange: 4,
        calmSharing: [3, 2],
        comboSharing: 2,
        reactions: [.levels, .combos, .sprintFinish],
        danger: 0.55...0.7,
        sprintFinish: 30
    )

    /// Mono: two chords stacked in fourths, swaying slowly. It reacts to
    /// almost nothing; only the voices joining show the game going on.
    public static let mono = MusicScore(
        home: Chord("E quartal", [4, 9, 2, 7], added: 11),
        chords: [
            Chord("E quartal", [4, 9, 2, 7], added: 11),
            Chord("A quartal", [9, 2, 7, 0], added: 4),
        ],
        tension: Chord("E quartal", [4, 9, 2, 7], added: 11),
        voices: voices,
        padRange: 52...72,
        unitSteps: 8,
        unitsPerChange: 8,
        calmSharing: [3],
        comboSharing: 3,
        reactions: [],
        danger: 0.55...0.7,
        sprintFinish: 30
    )

    /// Acid: C, E and A♭ (keys a major third apart) and their relative minors.
    /// Neighbours share one tone, so even the calm changes jump. Reacts to everything.
    public static let acid = MusicScore(
        home: Chord("Cadd9", [0, 4, 7, 2], added: 11),
        chords: [
            Chord("Cadd9", [0, 4, 7, 2], added: 11),
            Chord("Eadd9", [4, 8, 11, 6], added: 3),
            Chord("Abadd9", [8, 0, 3, 10], added: 7),
            Chord("Am(add9)", [9, 0, 4, 11], added: 2),
            Chord("C#m(add9)", [1, 4, 8, 3], added: 6),
            Chord("Fm(add9)", [5, 8, 0, 7], added: 10),
        ],
        tension: Chord("G7sus4", [7, 0, 2, 5], added: 9),
        voices: voices,
        padRange: 52...72,
        unitSteps: 8,
        unitsPerChange: 2,
        calmSharing: [1, 2, 2],
        comboSharing: 1,
        reactions: [.levels, .combos, .danger, .sprintFinish],
        danger: 0.55...0.7,
        sprintFinish: 30
    )
}
