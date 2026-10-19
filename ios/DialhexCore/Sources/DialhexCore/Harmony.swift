// Harmony.swift — Chords, the common-tone chord network, and voice leading
//
// A chord is a set of pitch classes (0 = C … 11 = B). Nothing is written out
// note by note: the next chord is found by how many notes it shares with the
// current one (more shared notes is a subtler change, fewer a bigger shift),
// and each voice moves to the nearest chord tone in its register.

public struct Chord: Hashable, Sendable {
    public let name: String
    /// The four core tones as pitch classes: root, third, fifth, seventh (or sixth).
    public let tones: [Int]
    /// A colour tone above the chord (a 9th or 11th) that voices may reach for.
    /// It isn't counted when comparing chords.
    public let added: Int

    public init(_ name: String, _ tones: [Int], added: Int) {
        self.name = name
        self.tones = tones
        self.added = added
    }

    /// Pitch class of a chord degree: 0 root, 1 third, 2 fifth, 3 seventh, 4 the added tone.
    public func degree(_ index: Int) -> Int {
        index < tones.count ? tones[index] : added
    }

    /// How many core tones the two chords have in common.
    public func shared(with other: Chord) -> Int {
        Set(tones).intersection(other.tones).count
    }
}

public enum ChordNetwork {
    /// Pick the chord after `current`: one from `pool` that shares exactly
    /// `target` tones with it, never `current` itself or the chord before it
    /// (so the music can't rock between two). If nothing fits, fall back to
    /// `home`; already home, take whichever comes closest to the target.
    public static func next(after current: Chord, previous: Chord?, in pool: [Chord],
                            sharing target: Int, home: Chord,
                            using rng: inout some RandomNumberGenerator) -> Chord {
        let candidates = pool.filter { $0 != current && $0 != previous }
        if let pick = candidates.filter({ $0.shared(with: current) == target }).randomElement(using: &rng) {
            return pick
        }
        if current != home { return home }
        return candidates.min {
            abs($0.shared(with: current) - target) < abs($1.shared(with: current) - target)
        } ?? home
    }
}

public enum VoiceLeading {
    /// The MIDI note with pitch class `pitchClass` in `range` that's nearest to
    /// `previous` (the lower one on a tie). The range must span an octave.
    public static func nearest(_ pitchClass: Int, to previous: Int, in range: ClosedRange<Int>) -> Int {
        precondition(range.count >= 12, "a register must span an octave")
        return range.filter { ($0 - pitchClass) % 12 == 0 }.min { abs($0 - previous) < abs($1 - previous) }!
    }

    /// The lowest MIDI note with pitch class `pitchClass` above `note`.
    public static func above(_ pitchClass: Int, _ note: Int) -> Int {
        note + 1 + ((pitchClass - note - 1) % 12 + 12) % 12
    }

    /// Voice `chord`'s core tones so each voice of `previous` moves as little
    /// as it can: tones the chords share stay exactly where they were. With no
    /// previous voicing, stack the chord upward from the bottom of `range`
    /// (tones that would climb out of it drop back in).
    public static func voice(_ chord: Chord, after previous: [Int], in range: ClosedRange<Int>) -> [Int] {
        guard previous.count == chord.tones.count else {
            var voicing: [Int] = []
            var note = range.lowerBound - 1
            for tone in chord.tones {
                note = above(tone, note)
                voicing.append(nearest(tone, to: note, in: range))
            }
            return voicing
        }
        // Try every way of handing the tones to the voices; keep the smallest total motion
        var best: (motion: Int, voicing: [Int])?
        for order in permutations(chord.tones) {
            let voicing = zip(order, previous).map { nearest($0, to: $1, in: range) }
            let motion = zip(voicing, previous).reduce(0) { $0 + abs($1.0 - $1.1) }
            if best == nil || motion < best!.motion { best = (motion, voicing) }
        }
        return best!.voicing
    }

    private static func permutations(_ items: [Int]) -> [[Int]] {
        guard items.count > 1 else { return [items] }
        return items.indices.flatMap { i -> [[Int]] in
            var rest = items
            let first = rest.remove(at: i)
            return permutations(rest).map { [first] + $0 }
        }
    }
}
