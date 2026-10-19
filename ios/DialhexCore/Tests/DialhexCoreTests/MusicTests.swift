// MusicTests.swift — The chord network, voice leading, and the conductor

import XCTest
@testable import DialhexCore

final class HarmonyTests: XCTestCase {
    private let score = MusicScore.base
    private func chord(_ name: String) -> Chord { score.chords.first { $0.name == name }! }

    func testSharedTonesCountCoreTonesOnly() {
        let cmaj7 = chord("Cmaj7")
        XCTAssertEqual(cmaj7.shared(with: chord("Am7")), 3)
        XCTAssertEqual(cmaj7.shared(with: chord("Fmaj7")), 2)
        XCTAssertEqual(cmaj7.shared(with: chord("Ebmaj7")), 1)
        XCTAssertEqual(cmaj7.shared(with: cmaj7), 4)
    }

    func testNetworkPicksAChordSharingExactlyTheTarget() {
        let current = chord("Cmaj7")
        let previous = chord("Am7")
        for seed in 0..<50 {
            var rng = SplitMix64(seed: UInt64(seed))
            for target in 1...3 {
                let next = ChordNetwork.next(after: current, previous: previous, in: score.chords,
                                             sharing: target, home: score.home, using: &rng)
                XCTAssertEqual(next.shared(with: current), target, "\(next.name) for \(target)")
                XCTAssertNotEqual(next, current)
                XCTAssertNotEqual(next, previous)
            }
        }
    }

    func testNetworkFallsBackHomeWhenNothingFits() {
        var rng = SplitMix64(seed: 1)
        // Nothing in the pool shares three tones with Ebmaj7
        let next = ChordNetwork.next(after: chord("Ebmaj7"), previous: nil, in: score.chords,
                                     sharing: 3, home: score.home, using: &rng)
        XCTAssertEqual(next, score.home)
    }

    func testNetworkAtHomeTakesTheClosestFit() {
        var rng = SplitMix64(seed: 1)
        let pool = [chord("Cmaj7"), chord("Fmaj7"), chord("Dm7")]
        // Nothing shares 3 with Cmaj7; Fmaj7 (2) is closer than Dm7 (1)
        let next = ChordNetwork.next(after: score.home, previous: nil, in: pool,
                                     sharing: 3, home: score.home, using: &rng)
        XCTAssertEqual(next.name, "Fmaj7")
    }

    func testNearestStaysInTheRange() {
        XCTAssertEqual(VoiceLeading.nearest(4, to: 60, in: 48...72), 64)
        XCTAssertEqual(VoiceLeading.nearest(4, to: 71, in: 60...84), 76)
        XCTAssertEqual(VoiceLeading.nearest(4, to: 90, in: 48...72), 64)
        XCTAssertEqual(VoiceLeading.above(0, 60), 72)
        XCTAssertEqual(VoiceLeading.above(4, 60), 64)
    }

    func testVoiceLeadingKeepsCommonTonesStill() {
        let first = VoiceLeading.voice(chord("Cmaj7"), after: [], in: score.padRange)
        XCTAssertEqual(first, [60, 64, 67, 71])
        let next = VoiceLeading.voice(chord("Am7"), after: first, in: score.padRange)
        // C, E and G stay put; only B moves, down a step to A
        XCTAssertEqual(next, [60, 64, 67, 69])
    }
}

final class ConductorTests: XCTestCase {
    private let score = MusicScore.base

    /// Drives a conductor on its own step clock, recording each note at the absolute time it sounds.
    private struct Driver {
        var conductor: Conductor
        var time = 0.0
        var notes: [(time: Double, note: MusicNote)] = []

        init(_ score: MusicScore, stepTime: Double = 0.14, seed: UInt64 = 7) {
            conductor = Conductor(score: score, stepTime: stepTime, colors: [0, 1], rng: SplitMix64(seed: seed))
        }

        mutating func run(seconds: Double, dt: Double = 1.0 / 60, danger: Double = 0, sprint: Double? = nil,
                          events: [GameEvent] = []) {
            var first = events
            let end = time + seconds
            while time < end - 1e-9 {
                time += dt
                let progress = time.truncatingRemainder(dividingBy: conductor.stepTime) / conductor.stepTime
                for note in conductor.advance(fallProgress: progress, events: first, danger: danger,
                                              sprintTimeRemaining: sprint) {
                    notes.append((time + note.delay, note))
                }
                first = []
            }
        }

        var pads: [(time: Double, note: MusicNote)] { notes.filter { $0.note.part == .pad } }
    }

    func testPadsStartOnUnitBoundaries() {
        var driver = Driver(score)
        driver.run(seconds: 10)
        let unit = Double(score.unitSteps) * 0.14
        XCTAssertGreaterThan(driver.pads.count, 5)
        for (i, pad) in driver.pads.enumerated().dropFirst() {
            XCTAssertEqual(pad.time, Double(i) * unit, accuracy: 1.0 / 60, "pad \(i)")
            XCTAssertEqual(pad.note.length, unit, accuracy: 1.0 / 60)
        }
    }

    func testChordsChangeOnTheirOwnAndMoveSmoothly() {
        var driver = Driver(score)
        var chords = [driver.conductor.chord]
        for _ in 0..<40 {
            driver.run(seconds: 0.5)
            if driver.conductor.chord != chords.last { chords.append(driver.conductor.chord) }
        }
        XCTAssertGreaterThan(chords.count, 2)
        for (a, b) in zip(chords, chords.dropFirst()) {
            XCTAssertTrue(b == score.home || [2, 3].contains(a.shared(with: b)), "\(a.name) → \(b.name)")
        }
    }

    func testSpawnPlaysAChordToneInItsColoursVoice() {
        var driver = Driver(score)
        for _ in 0..<30 {
            driver.run(seconds: 0.3, events: [.spawn(color: 1)])
        }
        let spawned = driver.notes.filter { $0.note.part == .voice(1) }
        XCTAssertEqual(spawned.count, 30)
        for (_, note) in spawned {
            XCTAssertTrue(score.voices[1].range.contains(note.pitches[0]))
        }
    }

    func testLevelUpMovesFarAndStrumsTheNewVoice() {
        var driver = Driver(score)
        driver.run(seconds: 0.2)
        let before = driver.conductor.chord
        driver.run(seconds: 1.5, events: [.levelUp(color: 2)])
        let after = driver.conductor.chord
        XCTAssertTrue(after.shared(with: before) == 1 || after == score.home, after.name)
        XCTAssertEqual(driver.notes.filter { $0.note.part == .voice(2) }.count, 5)
    }

    func testDangerHoldsTheTensionChordThenResolvesHome() {
        var driver = Driver(score)
        driver.run(seconds: 1.2, danger: 0.8)
        XCTAssertEqual(driver.conductor.chord, score.tension)
        driver.run(seconds: 10, danger: 0.8)
        XCTAssertEqual(driver.conductor.chord, score.tension, "held while the bin stays full")
        driver.run(seconds: 1.2, danger: 0.6)
        XCTAssertEqual(driver.conductor.chord, score.tension, "inside the hysteresis band")
        driver.run(seconds: 1.2, danger: 0.3)
        XCTAssertEqual(driver.conductor.chord, score.home)
    }

    func testClearArpeggioLandsOnTheNextSixteenths() {
        var driver = Driver(score)
        driver.run(seconds: 0.5)
        let clearedAt = driver.time
        let hex = Hex(center: Vertex(k: 6, j: 0), color: 0, cells: [])
        driver.run(seconds: 1, events: [.clear(hexes: [hex], points: 100)])
        let run = driver.notes.filter { $0.note.part == .voice(0) && $0.time > clearedAt }
        XCTAssertEqual(run.count, 3)
        for (i, note) in run.enumerated() {
            let steps = note.time / 0.14
            XCTAssertEqual(steps, steps.rounded(), accuracy: 0.13, "on a 16th")
            if i > 0 { XCTAssertGreaterThan(note.note.pitches[0], run[i - 1].note.pitches[0]) }
        }
    }

    func testWinEndsOnHome() {
        var driver = Driver(score)
        driver.run(seconds: 5)
        driver.run(seconds: 1, events: [.gameOver(won: true)])
        XCTAssertEqual(driver.conductor.chord, score.home)
        let count = driver.notes.count
        driver.run(seconds: 3)
        XCTAssertEqual(driver.notes.count, count, "silent after the game ends")
    }

    // MARK: - Skins

    private static let scores: [(String, MusicScore)] = [
        ("base", .base), ("riso", .riso), ("crt", .crt), ("flash", .flash), ("mono", .mono), ("acid", .acid),
    ]

    func testEverySkinHasItsScore() {
        for (id, score) in Self.scores {
            XCTAssertEqual(MusicScore.forSkin(id).home, score.home, id)
        }
        XCTAssertEqual(MusicScore.forSkin("unknown").home, MusicScore.base.home)
    }

    func testEveryScoreIsWellFormed() {
        for (id, score) in Self.scores {
            XCTAssertTrue(score.chords.contains(score.home), id)
            XCTAssertEqual(Set(score.chords.map(\.name)).count, score.chords.count, "\(id): names are unique")
            for chord in score.chords + [score.tension] {
                XCTAssertEqual(Set(chord.tones).count, 4, "\(id) \(chord.name)")
                XCTAssertTrue((chord.tones + [chord.added]).allSatisfy((0..<12).contains), "\(id) \(chord.name)")
                XCTAssertFalse(chord.tones.contains(chord.added), "\(id) \(chord.name): added tone is new")
            }
            XCTAssertEqual(score.voices.count, Progression.colorCount, id)
            XCTAssertTrue(score.voices.allSatisfy { $0.range.count >= 12 }, id)
            let voicing = VoiceLeading.voice(score.home, after: [], in: score.padRange)
            XCTAssertTrue(voicing.allSatisfy(score.padRange.contains), "\(id): \(voicing)")
        }
    }

    /// A long, busy game in every skin: every note belongs to a chord of its
    /// score and stays in its register, and the pad stays in its range.
    func testEveryScoreStaysInTuneThroughABusyGame() {
        for (id, score) in Self.scores {
            var driver = Driver(score, seed: 11)
            var rng = SplitMix64(seed: 5)
            for i in 0..<200 {
                var events: [GameEvent] = [.spawn(color: Int.random(in: 0..<8, using: &rng))]
                if i % 7 == 0 {
                    let hexes = (0..<Int.random(in: 1...3, using: &rng)).map { _ in
                        Hex(center: Vertex(k: 6, j: 0), color: Int.random(in: 0..<8, using: &rng), cells: [])
                    }
                    events.append(.clear(hexes: hexes, points: 100))
                }
                if i % 25 == 24 { events.append(.levelUp(color: i / 25 + 2)) }
                let danger = i % 60 < 30 ? 0.2 : 0.8
                driver.run(seconds: 0.25, danger: danger, sprint: 200 - Double(i), events: events)
            }
            let pitchClasses = Set((score.chords + [score.tension]).flatMap { $0.tones + [$0.added] })
            for (_, note) in driver.notes {
                switch note.part {
                case .pad:
                    XCTAssertTrue(note.pitches.allSatisfy(score.padRange.contains), "\(id): pad \(note.pitches)")
                case .voice:
                    XCTAssertTrue(note.pitches.allSatisfy { pitchClasses.contains($0 % 12) }, id)
                case .drum:
                    XCTAssertTrue(note.pitches.isEmpty, id)
                }
                XCTAssertGreaterThanOrEqual(note.delay, 0)
            }
            XCTAssertGreaterThan(driver.notes.count, 200, id)
        }
    }

    func testMonoReactsToAlmostNothing() {
        var driver = Driver(.mono)
        driver.run(seconds: 0.2)
        driver.run(seconds: 3, danger: 0.9, events: [.levelUp(color: 2)])
        XCTAssertEqual(driver.conductor.chord, MusicScore.mono.home, "no jump, no tension")
        XCTAssertTrue(driver.notes.allSatisfy { $0.note.part != .voice(2) }, "no strum")
    }

    func testRisoCombosLeap() {
        var driver = Driver(.riso)
        driver.run(seconds: 0.2)
        let hex = Hex(center: Vertex(k: 6, j: 0), color: 0, cells: [])
        driver.run(seconds: 1.2, events: [.clear(hexes: [hex, hex], points: 400)])
        XCTAssertEqual(driver.conductor.chord.shared(with: MusicScore.riso.home), 1, driver.conductor.chord.name)
    }

    func testFlashSprintFinishChangesEveryUnit() {
        var driver = Driver(.flash)
        let unit = Double(MusicScore.flash.unitSteps) * 0.14
        var chords: [Chord] = []
        driver.run(seconds: unit / 2, sprint: 20)
        for _ in 0..<6 {
            driver.run(seconds: unit, sprint: 20)
            chords.append(driver.conductor.chord)
        }
        for (a, b) in zip(chords, chords.dropFirst()) { XCTAssertNotEqual(a, b) }

        // Outside the finish the same score holds each chord for several units
        var calm = Driver(.flash)
        calm.run(seconds: unit / 2, sprint: 120)
        let first = calm.conductor.chord
        calm.run(seconds: unit * 2, sprint: 120)
        XCTAssertEqual(calm.conductor.chord, first)
    }

    func testCrtDangerStartsEarlier() {
        var crt = Driver(.crt)
        var base = Driver(.base)
        crt.run(seconds: 1.2, danger: 0.62)
        base.run(seconds: 1.2, danger: 0.62)
        XCTAssertEqual(crt.conductor.chord, MusicScore.crt.tension)
        XCTAssertNotEqual(base.conductor.chord, MusicScore.base.tension)
    }

    // MARK: - Groove

    private func drums(_ driver: Driver, _ drum: MusicNote.Drum? = nil) -> [Double] {
        driver.notes.compactMap {
            guard case .drum(let d) = $0.note.part, drum == nil || d == drum else { return nil }
            return $0.time
        }
    }

    func testOnlyBaseHasAGroove() {
        for (id, score) in Self.scores where id != "base" {
            var driver = Driver(score)
            driver.run(seconds: 3)
            XCTAssertTrue(drums(driver).isEmpty, id)
        }
    }

    func testGrooveSitsOnTheSixteenthsWithTheOffBeatsSwung() {
        var driver = Driver(score)
        driver.run(seconds: 0.2)
        driver.run(seconds: 6, events: [.levelUp(color: 2), .levelUp(color: 3), .levelUp(color: 4)])
        let swing = score.groove!.swing
        XCTAssertGreaterThan(drums(driver).count, 30)
        for time in drums(driver) {
            let steps = time / 0.14
            let sixteenth = steps.rounded(.down)
            let late = steps - sixteenth
            if Int(sixteenth) % 2 == 0 {
                XCTAssertTrue(late < 0.13 || late > 0.99, "on the beat: \(steps)")
            } else {
                XCTAssertEqual(late, swing, accuracy: 0.13, "swung: \(steps)")
            }
        }
        // Kick on each downbeat, snare on the backbeats
        let bar = 16 * 0.14
        for b in 0..<2 {
            XCTAssertTrue(drums(driver, .kick).contains { abs($0 - Double(b) * bar) < 1.0 / 30 }, "kick, bar \(b)")
            XCTAssertTrue(drums(driver, .snare).contains { abs($0 - (Double(b) + 0.25) * bar) < 1.0 / 30 })
        }
    }

    func testHatsAndGhostsJoinWithTheColours() {
        var driver = Driver(score)
        driver.run(seconds: 3)
        XCTAssertFalse(drums(driver, .kick).isEmpty)
        XCTAssertTrue(drums(driver, .hat).isEmpty && drums(driver, .accent).isEmpty, "two colours: no hats")
        driver.run(seconds: 3, events: [.levelUp(color: 2)])
        XCTAssertFalse(drums(driver, .accent).isEmpty, "three colours: hats")
        XCTAssertTrue(drums(driver, .ghost).isEmpty)
        driver.run(seconds: 3, events: [.levelUp(color: 3), .levelUp(color: 4)])
        XCTAssertFalse(drums(driver, .ghost).isEmpty, "five colours: ghost notes")
    }

    func testGrooveGoesHalfTimeAtFastSpeed() {
        let step = Game.fallStep * Speed.fast.pace
        var driver = Driver(score, stepTime: step)
        driver.run(seconds: 4)
        for time in drums(driver) {
            let steps = (time / step).rounded()
            XCTAssertEqual(Int(steps) % 2, 0, "only on every other step: \(time / step)")
        }
        // The first backbeat is four 16ths in, eight fall steps
        XCTAssertEqual(drums(driver, .snare).first ?? 0, 8 * step, accuracy: 1.0 / 60)
    }

    func testDangerThinsTheGrooveToAHeartbeat() {
        var driver = Driver(score)
        driver.run(seconds: 1.5, danger: 0.8)
        let from = driver.notes.count
        driver.run(seconds: 6, danger: 0.8)
        let kept = driver.notes.dropFirst(from).compactMap { n -> MusicNote.Drum? in
            if case .drum(let d) = n.note.part { d } else { nil }
        }
        XCTAssertFalse(kept.isEmpty)
        XCTAssertTrue(kept.allSatisfy { $0 == .kick || $0 == .crackle }, "\(Set(kept.map { "\($0)" }))")
        XCTAssertEqual(kept.filter { $0 == .kick }.count, kept.filter { $0 == .crackle }.count, "one kick a bar")
    }

    /// The real game drives it with no changes to the rules: every spawn's note
    /// sounds on a step boundary (within a frame).
    func testRealGameSpawnsLandOnTheStepGrid() {
        var game = Game(mode: .endless, speed: .normal, rng: SplitMix64(seed: 3))
        var conductor = Conductor(score: score, stepTime: game.stepTime, colors: game.activeColors,
                                  rng: SplitMix64(seed: 3))
        let dt = 1.0 / 60
        var time = 0.0
        var spawnNotes = 0
        for _ in 0..<1200 {
            time += dt
            let events = game.update(by: dt)
            let notes = conductor.advance(fallProgress: game.fallProgress, events: events,
                                          danger: Double(game.board.count) / Double(Grid.cells.count))
            for note in notes where events.contains(where: { if case .spawn = $0 { true } else { false } })
                && note.delay == 0 && { if case .voice = note.part { true } else { false } }() {
                let steps = time / game.stepTime
                XCTAssertLessThan(steps - steps.rounded(.down), dt / game.stepTime + 1e-6)
                spawnNotes += 1
            }
        }
        XCTAssertGreaterThan(spawnNotes, 10)
    }
}
