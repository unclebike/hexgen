// SoundEngine.swift — Procedural sound engine (port of audio.js)
// All sounds are synthesized into PCM buffers (no audio files) and played through AVAudioEngine.
// Filters are AVAudioUnitEQ bands, polyphony is a pool of player nodes, master gain is the main mixer.
// The active skin picks the tone colour: oscillator wave, octave, and whether the pad plays
// (skins.json still calls it the drone). The music's notes come from the `Conductor`, scheduled
// ahead on the audio clock; the sounds here are the effects around it. A score with a groove
// adds drums and vinyl crackle, both low-passed, and gives the pad a tape wobble.

import AVFoundation
import DialhexCore

enum Sound {
    case rotate
    case shimmer               // a clear's or level-up's sparkle; the music plays the notes
    case levelUp(color: Int)
    case gameOver
}

private let sampleRate = 44_100.0
private let masterVolume: Float = 0.5
private let mutedKey = "dialhex_muted"

/// The music's mix, in one place for tuning by ear.
private enum Mix {
    /// Peak gain of one voice note (before the wave's level correction).
    static let voice = 0.12
    /// Gain of each pad tone; four sound at once.
    static let pad = 0.035
    /// Seconds a pad takes to fade in, and to fade out into the next.
    static let padFade = 0.35
    /// Notes the skin's octave would push below this (in Hz) go up an octave instead:
    /// phone and TV speakers can't play much lower.
    static let lowest = 100.0

    /// The groove's drums, peak gains: an undertone, under the voices.
    static let kick = 0.22
    static let snare = 0.08
    /// A ghost note's gain, as a share of the snare's.
    static let ghost = 0.3
    static let hat = 0.025
    static let accent = 0.04
    static let crackle = 0.05
    /// Where the drums and crackle are cut off, for a dusty, sampled sound.
    static let drumTone: Float = 6000
    /// The pad's tape wobble, for scores with a groove: how far its pitch drifts (a share of it), and how often.
    static let wobbleDepth = 0.004
    static let wobbleRate = 0.5
}

// Base frequencies for colour-mapped tones (C4 to G4, chromatic), in unlock order
private let colorFrequencies: [Double] = [
    261.63, // C4
    277.18, // C#4
    293.66, // D4
    311.13, // D#4
    329.63, // E4
    349.23, // F4
    369.99, // F#4
    392.00, // G4
]

@MainActor
final class SoundEngine {
    private let format: AVAudioFormat
    private var graph: AudioGraph
    private var buffers: [String: AVAudioPCMBuffer] = [:]   // rendered lazily, once per key
    private var shimmerVariant = 0
    private var crackleVariant = 0
    private var observers: [NSObjectProtocol] = []           // engine lives for the app's lifetime
    private var activating = false                           // a session activation is in flight

    /// The skin's tone colour. Buffers are cached per style, so switching is cheap after the first play.
    var style = SkinSpec.Sound(wave: .sine, octave: 0, drone: true)
    /// The music has a groove: the pad wobbles like tape.
    var lofi = false

    /// Persisted in UserDefaults under "dialhex_muted".
    var isMuted: Bool {
        didSet {
            UserDefaults.standard.set(isMuted, forKey: mutedKey)
            applyVolume()
        }
    }

    init() {
        // Mono float, 44.1 kHz; the main mixer converts to whatever the hardware wants.
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        self.format = format
        isMuted = UserDefaults.standard.bool(forKey: mutedKey)
        graph = AudioGraph(format: format)
        applyVolume()
        observeSession()
    }

    /// Start (or restart after an interruption) the audio engine. Safe to call repeatedly.
    /// The session is activated in the background, so sounds played meanwhile are skipped.
    func start() {
        guard !graph.engine.isRunning, !activating else { return }
        activating = true
        // Session calls can block while the system arbitrates audio, so keep them off the main thread
        Task.detached(priority: .userInitiated) { [weak self] in
            let active = Self.activateSession()
            await self?.sessionActivated(active)
        }
    }

    /// Ambient: mixes with the user's music and respects the silent switch.
    nonisolated private static func activateSession() -> Bool {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.ambient)
            try session.setActive(true)
            return true
        } catch {
            return false
        }
    }

    private func sessionActivated(_ active: Bool) {
        activating = false
        guard active, !graph.engine.isRunning else { return }
        do {
            try graph.engine.start()
        } catch {
            return // audio unavailable — silent mode; retried on the next start()/play()
        }
        graph.restartPlayers()
    }

    func play(_ sound: Sound) {
        guard !isMuted else { return }
        start()
        guard graph.engine.isRunning else { return }

        switch sound {
        case .rotate:
            // Rotation: soft white noise click, linear fade, through a 2 kHz bandpass
            graph.clicks.play(cachedBuffer("rotate") { renderNotes($0, [Note(.noise, length: 0.02, gain: 0.1, decay: .linear)]) })

        case .shimmer:
            // High white noise with fade, starting at +0.15 s (baked in as leading silence).
            // A few noise variants so simultaneous clears don't sum coherently.
            shimmerVariant = (shimmerVariant + 1) % 4
            graph.shimmer.play(cachedBuffer("shimmer\(shimmerVariant)") {
                renderNotes($0, [Note(.noise, at: 0.15, length: 0.4, gain: 0.08)])
            })

        case .levelUp(let color):
            // Level up: major chord
            let (c, f) = tone(color)
            let (wave, level) = voice
            graph.tones.play(cachedBuffer("levelUp\(c)\(styleKey)") { format in
                renderNotes(format, [1, 5.0 / 4, 3.0 / 2].map { Note(wave, f * $0, length: 0.5, gain: 0.15 * level) })
            })

        case .gameOver:
            // Game over: descending chromatic run, G4 down to E4, sawtooth through a 1 kHz lowpass
            graph.buzz.play(cachedBuffer("gameOver") { format in
                renderNotes(format, [392, 369.99, 349.23, 329.63].enumerated().map { i, f in
                    Note(.sawtooth, f, at: Double(i) * 0.15, length: 0.15, gain: 0.12)
                })
            })
        }
    }

    /// The conductor's notes, each at its delay from now. Voices use the skin's wave and octave;
    /// the pad plays only for skins with a drone.
    func play(_ notes: [MusicNote]) {
        guard !isMuted, !notes.isEmpty else { return }
        start()
        guard graph.engine.isRunning else { return }

        let (wave, level) = voice
        for note in notes {
            switch note.part {
            case .pad:
                guard style.drone else { continue }
                // Rounded to 10 ms so the cache holds one buffer per chord voicing and speed
                let length = (note.length * 100).rounded() / 100
                let freqs = note.pitches.map(frequency)
                let wobble = lofi
                graph.pads.play(cachedBuffer("pad\(note.pitches)-\(length)\(styleKey)\(wobble ? "-tape" : "")") {
                    renderPad($0, freqs, length: length, wobble: wobble)
                }, after: note.delay)
            case .voice:
                for pitch in note.pitches {
                    graph.music.play(cachedBuffer("note\(pitch)-\(note.length)\(styleKey)") {
                        renderNotes($0, [Note(wave, frequency(pitch), length: note.length, gain: Mix.voice * level)])
                    }, after: note.delay)
                }
            case .drum(.crackle):
                // A few variants, so the pops don't repeat every bar
                crackleVariant = (crackleVariant + 1) % 3
                let length = (note.length * 100).rounded() / 100
                graph.crackle.play(cachedBuffer("crackle\(crackleVariant)-\(length)") {
                    renderCrackle($0, length: length)
                }, after: note.delay)
            case .drum(let drum):
                graph.drums.play(cachedBuffer("drum\(drum)") { renderDrum($0, drum) }, after: note.delay)
            }
        }
    }

    // MARK: - Private

    /// Color index → (cache index, frequency, shifted by the skin's octave); unknown colors fall back to C4 like the JS.
    private func tone(_ color: Int) -> (Int, Double) {
        let c = colorFrequencies.indices.contains(color) ? color : 0
        return (c, colorFrequencies[c] * pow(2, Double(style.octave)))
    }

    /// MIDI note → Hz, shifted by the skin's octave but kept above `Mix.lowest`.
    private func frequency(_ midi: Int) -> Double {
        let hz = 440 * pow(2, Double(midi - 69) / 12 + Double(style.octave))
        return hz < Mix.lowest ? hz * 2 : hz
    }

    /// The skin's wave, and a gain that keeps it level with a sine (square and sawtooth carry far more energy).
    private var voice: (Note.Wave, Double) {
        switch style.wave {
        case .sine: return (.sine, 1)
        case .triangle: return (.triangle, 0.9)
        case .square: return (.square, 0.4)
        case .sawtooth: return (.sawtooth, 0.5)
        }
    }

    private var styleKey: String { "-\(style.wave.rawValue)\(style.octave)" }

    private func cachedBuffer(_ key: String, _ make: (AVAudioFormat) -> AVAudioPCMBuffer?) -> AVAudioPCMBuffer? {
        if let cached = buffers[key] { return cached }
        let made = make(format)
        buffers[key] = made
        return made
    }

    private func applyVolume() {
        graph.engine.mainMixerNode.outputVolume = isMuted ? 0 : masterVolume
    }

    /// Interruptions and hardware changes stop the engine; start() brings it back (now or on the next play).
    private func observeSession() {
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: AVAudioSession.interruptionNotification,
                                            object: nil, queue: .main) { [weak self] note in
            let kind = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            let began = kind == AVAudioSession.InterruptionType.began.rawValue
            MainActor.assumeIsolated {
                guard let self else { return }
                if began { self.graph.engine.stop() } else { self.start() }
            }
        })
        observers.append(center.addObserver(forName: .AVAudioEngineConfigurationChange,
                                            object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.start() }
        })
        // Media server crashed: every node is dead, so rebuild the graph from scratch
        observers.append(center.addObserver(forName: AVAudioSession.mediaServicesWereResetNotification,
                                            object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.rebuild() }
        })
    }

    private func rebuild() {
        graph.engine.stop()
        graph = AudioGraph(format: format)
        applyVolume()
        start()
    }
}

// MARK: - Node graph

/// Player pools (some through a one-band EQ filter) → main mixer (master gain) → output.
private final class AudioGraph {
    let engine: AVAudioEngine
    let tones: VoicePool    // sines, unfiltered
    let clicks: VoicePool   // rotate noise → bandpass 2 kHz
    let shimmer: VoicePool  // clear shimmer noise → highpass 4 kHz
    let buzz: VoicePool     // game-over sawtooths → lowpass 1 kHz
    let music: VoicePool    // the conductor's voices, unfiltered
    let pads: VoicePool     // the conductor's pad: two, so each unit's chord crossfades into the next
    let drums: VoicePool    // the groove's drums → lowpass
    let crackle: VoicePool  // a bar of vinyl crackle at a time → lowpass

    init(format: AVAudioFormat) {
        let engine = AVAudioEngine()
        self.engine = engine
        tones = VoicePool(engine, size: 8, format: format)
        music = VoicePool(engine, size: 16, format: format)
        pads = VoicePool(engine, size: 2, format: format)
        drums = VoicePool(engine, size: 8, format: format, filter: (type: .lowPass, frequency: Mix.drumTone, bandwidth: 1))
        crackle = VoicePool(engine, size: 2, format: format, filter: (type: .lowPass, frequency: Mix.drumTone, bandwidth: 1))
        // Web Audio bandpass Q 1 ≈ 1.39 octaves: BW = 2·asinh(1/2Q)/ln 2
        clicks = VoicePool(engine, size: 2, format: format, filter: (type: .bandPass, frequency: 2000, bandwidth: 1.39))
        // Plain (non-resonant) high/low pass; bandwidth is ignored for these types
        shimmer = VoicePool(engine, size: 4, format: format, filter: (type: .highPass, frequency: 4000, bandwidth: 1))
        buzz = VoicePool(engine, size: 1, format: format, filter: (type: .lowPass, frequency: 1000, bandwidth: 1))
    }

    /// Players stop when the engine does; after a (re)start they must be played again.
    func restartPlayers() {
        for pool in [tones, clicks, shimmer, buzz, music, pads, drums, crackle] { pool.restart() }
    }
}

/// A few always-playing player nodes sharing one output, so sounds can overlap.
/// Round-robin; when all are busy the oldest voice is cut off.
private final class VoicePool {
    private let players: [AVAudioPlayerNode]
    private var next = 0

    init(_ engine: AVAudioEngine, size: Int, format: AVAudioFormat,
         filter: (type: AVAudioUnitEQFilterType, frequency: Float, bandwidth: Float)? = nil) {
        players = (0..<size).map { _ in AVAudioPlayerNode() }
        var output: AVAudioNode = engine.mainMixerNode
        if let filter {
            // Players → submix → EQ → main mixer (an EQ has a single input bus)
            let submix = AVAudioMixerNode()
            let eq = AVAudioUnitEQ(numberOfBands: 1)
            let band = eq.bands[0]
            band.filterType = filter.type
            band.frequency = filter.frequency
            band.bandwidth = filter.bandwidth
            band.bypass = false
            engine.attach(submix)
            engine.attach(eq)
            engine.connect(submix, to: eq, format: format)
            engine.connect(eq, to: engine.mainMixerNode, format: format)
            output = submix
        }
        for player in players {
            engine.attach(player)
            engine.connect(player, to: output, format: format)
        }
    }

    func restart() {
        for player in players {
            player.stop()
            player.play()
        }
    }

    /// Play now, or `delay` seconds from now on the player's own sample clock, so notes
    /// scheduled ahead land exactly in time whatever the frame rate.
    func play(_ buffer: AVAudioPCMBuffer?, after delay: Double = 0) {
        guard let buffer else { return }
        let player = players[next]
        next = (next + 1) % players.count
        var when: AVAudioTime?
        if delay > 0, let nodeTime = player.lastRenderTime, let now = player.playerTime(forNodeTime: nodeTime) {
            when = AVAudioTime(sampleTime: now.sampleTime + AVAudioFramePosition(delay * now.sampleRate),
                               atRate: now.sampleRate)
        }
        player.scheduleBuffer(buffer, at: when, options: .interrupts, completionHandler: nil)
    }
}

// MARK: - Synthesis

/// One oscillator note with the JS gain envelope: starts at `gain`, ramps exponentially to 0.001
/// over `length` (or linearly to 0 for the rotate click), then stops. `at` delays it within the buffer.
private struct Note {
    enum Wave { case sine, triangle, square, sawtooth, noise }
    enum Decay { case exponential, linear }

    let wave: Wave, freq: Double, at: Double, length: Double, gain: Double, decay: Decay

    init(_ wave: Wave, _ freq: Double = 0, at: Double = 0, length: Double, gain: Double,
         decay: Decay = .exponential) {
        self.wave = wave
        self.freq = freq
        self.at = at
        self.length = length
        self.gain = gain
        self.decay = decay
    }

    func sample(_ t: Double) -> Double {
        let u = t - at
        guard u >= 0, u < length else { return 0 }
        let envelope = decay == .linear
            ? gain * (1 - u / length)
            : gain * pow(0.001 / gain, u / length)
        return envelope * oscillator(u)
    }

    private func oscillator(_ t: Double) -> Double {
        switch wave {
        case .sine:
            return sin(2 * .pi * freq * t)
        case .triangle, .square:
            // Band-limited odd harmonics up to Nyquist, like Web Audio's
            var sum = 0.0
            var k = 1.0
            while k * freq < sampleRate / 2 {
                if wave == .square {
                    sum += sin(2 * .pi * k * freq * t) / k
                } else {
                    let sign: Double = Int(k / 2) % 2 == 0 ? 1 : -1
                    sum += sign * sin(2 * .pi * k * freq * t) / (k * k)
                }
                k += 2
            }
            return wave == .square ? sum * 4 / .pi : sum * 8 / (.pi * .pi)
        case .noise:
            return Double.random(in: -1...1)
        case .sawtooth:
            // Band-limited like Web Audio's: Fourier series up to Nyquist
            var sum = 0.0
            var k = 1.0
            while k * freq < sampleRate / 2 {
                let sign: Double = Int(k) % 2 == 1 ? 1 : -1
                sum += sign * sin(2 * .pi * k * freq * t) / k
                k += 1
            }
            return sum * 2 / .pi
        }
    }
}

/// Render `duration` seconds of mono samples, `sample(t)` per frame.
private func renderBuffer(_ format: AVAudioFormat, duration: Double,
                          _ sample: (Double) -> Double) -> AVAudioPCMBuffer? {
    let frames = AVAudioFrameCount((duration * format.sampleRate).rounded())
    guard frames > 0,
          let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames),
          let data = buffer.floatChannelData?[0] else { return nil }
    for i in 0..<Int(frames) {
        data[i] = Float(sample(Double(i) / format.sampleRate))
    }
    buffer.frameLength = frames
    return buffer
}

/// Mix notes into one buffer long enough for the last one to finish.
private func renderNotes(_ format: AVAudioFormat, _ notes: [Note]) -> AVAudioPCMBuffer? {
    let duration = notes.map { $0.at + $0.length }.max() ?? 0
    return renderBuffer(format, duration: duration) { t in
        notes.reduce(0.0) { $0 + $1.sample(t) }
    }
}

/// Pad chord: soft sines with a quiet octave above, fading in over `Mix.padFade` and out over it
/// after `length`. The next unit's pad starts as this one fades, so the two crossfade.
/// With `wobble` its pitch drifts slowly sharp and back, like worn tape.
private func renderPad(_ format: AVAudioFormat, _ freqs: [Double], length: Double, wobble: Bool) -> AVAudioPCMBuffer? {
    let fade = Mix.padFade
    let depth = wobble ? Mix.wobbleDepth : 0, rate = Mix.wobbleRate
    return renderBuffer(format, duration: length + fade) { t in
        let envelope = min(1, t / fade, (length + fade - t) / fade)
        // Time as the tape plays it: the integral of 1 + depth·sin(2π·rate·t)
        let u = t + depth * (1 - cos(2 * .pi * rate * t)) / (2 * .pi * rate)
        return Mix.pad * envelope * freqs.reduce(0.0) { $0 + sin(2 * .pi * $1 * u) + 0.2 * sin(4 * .pi * $1 * u) }
    }
}

/// One drum hit. A kick is a sine falling from 160 to 70 Hz with a click on top, so phone speakers
/// still hear it; a snare is noise over a short 185 Hz tone; hats are noise with its lows taken out.
private func renderDrum(_ format: AVAudioFormat, _ drum: MusicNote.Drum) -> AVAudioPCMBuffer? {
    switch drum {
    case .kick:
        let tau = 0.03, high = 160.0, low = 70.0
        return renderBuffer(format, duration: 0.3) { t in
            let phase = 2 * .pi * (low * t + (high - low) * tau * (1 - exp(-t / tau)))
            let body = (sin(phase) + 0.3 * sin(2 * phase)) * pow(0.001, t / 0.3)
            let click = Double.random(in: -1...1) * exp(-t / 0.003) * 0.3
            return Mix.kick * (body + click)
        }
    case .snare, .ghost:
        let gain = drum == .ghost ? Mix.snare * Mix.ghost : Mix.snare
        let length = drum == .ghost ? 0.1 : 0.18
        return renderBuffer(format, duration: length) { t in
            let tone = sin(2 * .pi * 185 * t) * exp(-t / 0.03) * 0.5
            let noise = Double.random(in: -1...1) * pow(0.001, t / length)
            return gain * (tone + noise)
        }
    case .hat, .accent:
        let gain = drum == .accent ? Mix.accent : Mix.hat
        let length = drum == .accent ? 0.06 : 0.035
        var previous = 0.0
        return renderBuffer(format, duration: length) { t in
            // Each sample minus the last: a first-order high-pass
            let noise = Double.random(in: -1...1)
            defer { previous = noise }
            return gain * (noise - previous) * 0.5 * pow(0.001, t / length)
        }
    case .crackle:
        return renderCrackle(format, length: 0.1)
    }
}

/// `length` seconds of vinyl: a few soft pops a second over a faint hiss.
private func renderCrackle(_ format: AVAudioFormat, length: Double) -> AVAudioPCMBuffer? {
    let chance = 7 / format.sampleRate
    var pop = 0.0
    return renderBuffer(format, duration: length) { _ in
        if Double.random(in: 0..<1) < chance {
            pop = Double.random(in: 0.2...1) * (Bool.random() ? 1 : -1)
        }
        defer { pop *= 0.55 }
        return Mix.crackle * (pop + 0.05 * Double.random(in: -1...1))
    }
}
