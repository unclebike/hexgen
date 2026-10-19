// Conductor.swift — Turns a game into music
//
// The game's step clock is the beat: one fall step is a 16th note, so the
// tempo follows the speed setting. Each new triangle plays the next note of
// its colour's voice, on the step it arrived. Clears play an arpeggio on the
// following 16ths. Chords change only on unit boundaries, where the pad starts
// each unit's chord, and the game decides how far each change moves: further
// for a level-up, and not at all while the bin is nearly full. A score with a
// groove adds drums on the same 16ths, swung.
//
// It reads only the game's events and `fallProgress`, so the rules don't know
// the music exists. Notes come back with a delay in seconds, for the sound
// engine to schedule ahead on the audio clock.

public struct MusicNote: Sendable, Equatable {
    public enum Part: Sendable, Equatable {
        /// A piece colour's voice.
        case voice(Int)
        case pad
        /// The groove's drums; they have no pitch.
        case drum(Drum)
    }

    public enum Drum: Sendable, Equatable {
        case kick, snare, ghost, hat, accent
        /// Vinyl crackle, one bar of it (`length`) on each downbeat.
        case crackle
    }

    public let part: Part
    /// MIDI notes, sounding together.
    public let pitches: [Int]
    /// Seconds from now.
    public let delay: Double
    /// Seconds it rings; a pad holds this long, then fades.
    public let length: Double
}

public struct Conductor {
    public let score: MusicScore
    public let stepTime: Double
    /// The chord sounding now (or about to, at the coming boundary).
    public private(set) var chord: Chord

    /// A note waiting for its step: an arpeggio or strum, one chord degree at
    /// a time. Its pitch is found when it's handed out, so it fits the chord
    /// sounding then.
    private struct Pending {
        let step: Int
        let voice: Int
        let degree: Int
        /// Starts the run at the bottom of the voice; later notes climb from the one before.
        let first: Bool
        let length: Double
    }

    private var previousChord: Chord?
    private var padVoicing: [Int]
    private var rng: any RandomNumberGenerator

    /// Step boundaries crossed so far, and how far (0…1) into the current step the game is.
    private var step = 0
    private var progress = 0.0
    private var started = false
    /// The last unit whose chord and pad have been handed out.
    private var scheduledUnit = -1
    private var unitsSinceChange = 0
    /// Shared tones asked for at the next boundary.
    private var requested: Int?
    private var tense = false
    /// Whether the music is holding the tension chord over a nearly full bin.
    public var isTense: Bool { tense }
    private var resolving = false
    /// In a sprint's last stretch, for scores that react to it.
    private var finishing = false
    /// A colour that just arrived; its voice strums the next unit's chord.
    private var strum: Int?
    private var pending: [Pending] = []
    private var finished = false
    /// The last step whose drums have been handed out.
    private var drumStep = -1

    // Per voice
    private var lastPitch: [Int?]
    private var runPitch: [Int]
    private var motifStep: [Int]
    private var motifLength: [Int]
    private var active: Set<Int>

    public init(score: MusicScore, stepTime: Double, colors: [Int],
                rng: any RandomNumberGenerator = SystemRandomNumberGenerator()) {
        self.score = score
        self.stepTime = stepTime
        self.rng = rng
        chord = score.home
        padVoicing = VoiceLeading.voice(score.home, after: [], in: score.padRange)
        let count = score.voices.count
        lastPitch = Array(repeating: nil, count: count)
        runPitch = score.voices.map(\.range.lowerBound)
        motifStep = Array(repeating: 0, count: count)
        motifLength = score.voices.map { min(2, $0.motif.count) }
        active = Set(colors.map { ($0 % count + count) % count })
    }

    /// Call once per frame, after the game's update, with the events it
    /// returned, its `fallProgress`, how full the bin is (0…1), and the
    /// sprint clock if there is one.
    public mutating func advance(fallProgress: Double, events: [GameEvent], danger: Double,
                                 sprintTimeRemaining: Double? = nil) -> [MusicNote] {
        guard !finished else { return [] }
        if started && fallProgress < progress { step += 1 }
        started = true
        progress = fallProgress

        var notes: [MusicNote] = []
        for event in events {
            handle(event, &notes)
            if finished { return notes }
        }
        if score.reactions.contains(.danger) {
            if !tense && danger >= score.danger.upperBound {
                tense = true
            } else if tense && danger < score.danger.lowerBound {
                tense = false
                resolving = true
            }
        }
        if score.reactions.contains(.sprintFinish), let left = sprintTimeRemaining {
            finishing = left <= score.sprintFinish
        }
        scheduleUnits(&notes)
        releasePending(&notes)
        playGroove(&notes)
        return notes
    }

    // MARK: - Events

    private mutating func handle(_ event: GameEvent, _ notes: inout [MusicNote]) {
        switch event {
        case .spawn(let color):
            // The colour's next motif step, as the nearest chord tone in its register
            let v = voice(for: color)
            let spec = score.voices[v]
            let degree = spec.motif[motifStep[v] % motifLength[v]]
            motifStep[v] += 1
            let from = lastPitch[v] ?? (spec.range.lowerBound + spec.range.upperBound) / 2
            let pitch = VoiceLeading.nearest(chord.degree(degree), to: from, in: spec.range)
            lastPitch[v] = pitch
            notes.append(MusicNote(part: .voice(v), pitches: [pitch], delay: 0, length: spec.length))

        case .clear(let hexes, _):
            // A rising arpeggio on the next 16ths; bigger clears climb further and move the harmony
            guard let color = hexes.first?.color else { return }
            queueRun(voice: voice(for: color), from: step + 1, notes: min(5, 2 + hexes.count), length: 0.4)
            if hexes.count > 1 && score.reactions.contains(.combos) { requested = score.comboSharing }

        case .levelUp(let color):
            // A new voice joins, the others' tunes grow a step, and the next chord moves far.
            // Only the first time: in versus every bin reaches each colour on its own.
            let v = voice(for: color)
            guard !active.contains(v) else { return }
            for other in active where other != v {
                motifLength[other] = min(motifLength[other] + 1, score.voices[other].motif.count)
            }
            active.insert(v)
            if score.reactions.contains(.levels) {
                requested = 1
                strum = v
            }

        case .gameOver(let won):
            finished = true
            pending = []
            guard won else { return }
            // Home, to finish: the pad and a strum of the home chord
            previousChord = chord
            chord = score.home
            padVoicing = VoiceLeading.voice(chord, after: padVoicing, in: score.padRange)
            let unit = Double(score.unitSteps) * stepTime
            notes.append(MusicNote(part: .pad, pitches: padVoicing, delay: 0, length: 2 * unit))
            let v = min(1, score.voices.count - 1)
            var pitch = 0
            for i in 0..<5 {
                pitch = runNote(voice: v, degree: i, first: i == 0, after: pitch)
                notes.append(MusicNote(part: .voice(v), pitches: [pitch], delay: Double(i) * stepTime, length: 0.8))
            }

        case .rotate, .power:
            break
        }
    }

    // MARK: - Harmony

    /// Hand out the current unit if it never was (the first frame), and the
    /// next one once its boundary is close enough to schedule ahead.
    private mutating func scheduleUnits(_ notes: inout [MusicNote]) {
        let current = step / score.unitSteps
        if scheduledUnit < current { startUnit(current, &notes) }
        if time(of: (current + 1) * score.unitSteps) <= lookahead { startUnit(current + 1, &notes) }
    }

    private mutating func startUnit(_ unit: Int, _ notes: inout [MusicNote]) {
        guard unit > scheduledUnit else { return }
        if scheduledUnit >= 0 { changeChordIfDue() }
        scheduledUnit = unit
        let start = unit * score.unitSteps
        let delay = max(0, time(of: start))
        let length = time(of: start + score.unitSteps) - delay
        notes.append(MusicNote(part: .pad, pitches: padVoicing, delay: delay, length: length))
        if let v = strum {
            strum = nil
            queueRun(voice: v, from: start, notes: 5, length: 0.6)
        }
    }

    /// A sprint's finish changes chord on every boundary.
    private var unitsPerChange: Int { finishing ? 1 : score.unitsPerChange }

    private mutating func changeChordIfDue() {
        unitsSinceChange += 1
        defer { requested = nil }
        let target: Chord?
        if tense {
            // Hold the suspended chord until the danger passes
            target = chord == score.tension ? nil : score.tension
        } else if resolving {
            resolving = false
            target = chord == score.home ? nil : score.home
        } else if let sharing = requested
                    ?? (unitsSinceChange >= unitsPerChange ? score.calmSharing.randomElement(using: &rng) : nil) {
            target = ChordNetwork.next(after: chord, previous: previousChord, in: score.chords,
                                       sharing: sharing, home: score.home, using: &rng)
        } else {
            target = nil
        }
        guard let target else { return }
        previousChord = chord
        chord = target
        unitsSinceChange = 0
        padVoicing = VoiceLeading.voice(chord, after: padVoicing, in: score.padRange)
    }

    // MARK: - Runs

    private mutating func queueRun(voice v: Int, from start: Int, notes count: Int, length: Double) {
        for i in 0..<count {
            pending.append(Pending(step: start + i, voice: v, degree: i, first: i == 0, length: length))
        }
    }

    private mutating func releasePending(_ notes: inout [MusicNote]) {
        var waiting: [Pending] = []
        for note in pending {
            let t = time(of: note.step)
            guard t <= lookahead else {
                waiting.append(note)
                continue
            }
            let pitch = runNote(voice: note.voice, degree: note.degree, first: note.first, after: runPitch[note.voice])
            runPitch[note.voice] = pitch
            notes.append(MusicNote(part: .voice(note.voice), pitches: [pitch], delay: max(0, t), length: note.length))
        }
        pending = waiting
    }

    /// A run starts on the lowest root in the voice's register and climbs one chord tone at a time.
    private func runNote(voice v: Int, degree: Int, first: Bool, after previous: Int) -> Int {
        let range = score.voices[v].range
        let pitchClass = chord.degree(degree)
        return first
            ? VoiceLeading.nearest(pitchClass, to: range.lowerBound, in: range)
            : VoiceLeading.above(pitchClass, previous)
    }

    // MARK: - Groove

    /// Fall steps per 16th of the groove: two when the step clock is too fast for chill hop.
    private func groovePace(_ groove: Groove) -> Int {
        60 / (4 * stepTime) > groove.halfTimeAbove ? 2 : 1
    }

    /// Hand out each step's drums once its boundary is close enough to schedule ahead.
    /// The off 16ths land late by the groove's swing.
    private mutating func playGroove(_ notes: inout [MusicNote]) {
        guard let groove = score.groove else { return }
        let pace = groovePace(groove)
        let sixteenth = Double(pace) * stepTime
        while time(of: drumStep + 1) <= lookahead {
            drumStep += 1
            let t = time(of: drumStep)
            // Steps long gone (a stalled frame) are skipped rather than played in a pile
            guard t > -stepTime / 2, drumStep % pace == 0 else { continue }
            let position = (drumStep / pace) % 32
            let bar = position / 16, i = position % 16
            let delay = max(0, t) + (i % 2 == 1 ? groove.swing * sixteenth : 0)

            func hit(_ drum: MusicNote.Drum, length: Double = 0) {
                notes.append(MusicNote(part: .drum(drum), pitches: [], delay: delay, length: length))
            }
            func on(_ pattern: [String]) -> Character {
                let line = pattern[bar % pattern.count]
                return line[line.index(line.startIndex, offsetBy: i % line.count)]
            }

            if i == 0 { hit(.crackle, length: 16 * sixteenth) }
            if tense {
                // A heartbeat while the bin is nearly full
                if i == 0 { hit(.kick) }
                continue
            }
            if on(groove.kick) == "x" { hit(.kick) }
            if on(groove.snare) == "x" { hit(.snare) }
            if active.count >= groove.ghostsFrom && on(groove.ghost) == "x" { hit(.ghost) }
            if active.count >= groove.hatsFrom {
                switch on(groove.hat) {
                case "X": hit(.accent)
                case "x": hit(.hat)
                default: break
                }
            }
        }
    }

    // MARK: - Clock

    /// Schedule this far ahead, well under a step so no boundary is handed out twice.
    private var lookahead: Double { stepTime * 0.6 }

    /// Seconds from now until step boundary `s` (negative if it's passed).
    private func time(of s: Int) -> Double {
        (Double(s - step) - progress) * stepTime
    }

    private func voice(for color: Int) -> Int {
        let count = score.voices.count
        return (color % count + count) % count
    }
}
