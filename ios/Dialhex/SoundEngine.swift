// SoundEngine.swift — Procedural sound engine (port of audio.js)
// All sounds are synthesized into PCM buffers (no audio files) and played through AVAudioEngine.
// Filters are AVAudioUnitEQ bands, polyphony is a pool of player nodes, master gain is the main mixer.

import AVFoundation

enum Sound {
    case place(color: Int)     // a new triangle enters
    case rotate
    case clear(color: Int)
    case levelUp(color: Int)
    case gameOver
}

private let sampleRate = 44_100.0
private let masterVolume: Float = 0.5
private let mutedKey = "dialhex_muted"

// Base frequencies for color-mapped tones (C4 to C5, chromatic)
private let colorFrequencies: [Double] = [
    261.63, // C4  — green
    277.18, // C#4 — orange
    293.66, // D4  — yellow
    311.13, // D#4 — red
    329.63, // E4  — blue
    349.23, // F4  — purple
    369.99, // F#4 — cyan
    392.00, // G4  — dark green
]

@MainActor
final class SoundEngine {
    private let format: AVAudioFormat
    private var graph: AudioGraph
    private var buffers: [String: AVAudioPCMBuffer] = [:]   // rendered lazily, once per key
    private var droneColorCount: Int?                        // non-nil while the drone should play
    private var shimmerVariant = 0
    private var observers: [NSObjectProtocol] = []           // engine lives for the app's lifetime

    /// Persisted in UserDefaults under "dialhex_muted".
    var isMuted: Bool {
        didSet {
            UserDefaults.standard.set(isMuted, forKey: mutedKey)
            applyVolume()
        }
    }

    init() {
        // Mono float, 44.1 kHz; the main mixer converts to whatever the hardware wants.
        format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        isMuted = UserDefaults.standard.bool(forKey: mutedKey)
        graph = AudioGraph(format: format)
        applyVolume()
        observeSession()
    }

    /// Start (or restart after an interruption) the audio engine. Safe to call repeatedly.
    func start() {
        guard !graph.engine.isRunning else { return }
        do {
            // Ambient: mixes with the user's music and respects the silent switch
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.ambient)
            try session.setActive(true)
            try graph.engine.start()
        } catch {
            return // audio unavailable — silent mode; retried on the next start()/play()
        }
        graph.restartPlayers()
        if let colorCount = droneColorCount { loopDrone(colorCount) }
    }

    func play(_ sound: Sound) {
        guard !isMuted else { return }
        start()
        guard graph.engine.isRunning else { return }

        switch sound {
        case .place(let color):
            // Triangle place: short sine tone mapped to color
            let (c, f) = tone(color)
            graph.tones.play(cachedBuffer("place\(c)") { renderNotes($0, [Note(.sine, f, length: 0.08, gain: 0.15)]) })

        case .rotate:
            // Rotation: soft white noise click, linear fade, through a 2 kHz bandpass
            graph.clicks.play(cachedBuffer("rotate") { renderNotes($0, [Note(.noise, length: 0.02, gain: 0.1, decay: .linear)]) })

        case .clear(let color):
            // Hex clear: rising arpeggio (root, third, fifth approx), 50 ms apart
            let (c, f) = tone(color)
            graph.tones.play(cachedBuffer("clear\(c)") { format in
                renderNotes(format, [1, 1.25, 1.5].enumerated().map { i, ratio in
                    Note(.sine, f * ratio, at: Double(i) * 0.05, length: 0.1, gain: 0.2)
                })
            })
            // Shimmer: high white noise with fade, starting at +0.15 s (baked in as leading silence).
            // A few noise variants so simultaneous clears don't sum coherently.
            shimmerVariant = (shimmerVariant + 1) % 4
            graph.shimmer.play(cachedBuffer("shimmer\(shimmerVariant)") {
                renderNotes($0, [Note(.noise, at: 0.15, length: 0.4, gain: 0.08)])
            })

        case .levelUp(let color):
            // Level up: major chord
            let (c, f) = tone(color)
            graph.tones.play(cachedBuffer("levelUp\(c)") { format in
                renderNotes(format, [1, 5.0 / 4, 3.0 / 2].map { Note(.sine, f * $0, length: 0.5, gain: 0.15) })
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

    /// Background drone: 40 Hz sine with vibrato at `colorCount` Hz (1 Hz per color).
    func startDrone(colorCount: Int) {
        droneColorCount = colorCount
        if graph.engine.isRunning { loopDrone(colorCount) } else { start() }
    }

    func stopDrone() {
        droneColorCount = nil
        graph.drone.stop()
    }

    // MARK: - Private

    private func loopDrone(_ colorCount: Int) {
        let drone = graph.drone
        drone.stop()
        guard let buffer = cachedBuffer("drone\(colorCount)", { renderDrone($0, vibratoHz: colorCount) }) else { return }
        drone.scheduleBuffer(buffer, at: nil, options: .loops, completionHandler: nil)
        drone.play()
    }

    /// Color index → (cache index, frequency); unknown colors fall back to C4 like the JS.
    private func tone(_ color: Int) -> (Int, Double) {
        let c = colorFrequencies.indices.contains(color) ? color : 0
        return (c, colorFrequencies[c])
    }

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
                if began { self?.graph.engine.stop() } else { self?.start() }
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
    let drone: AVAudioPlayerNode

    init(format: AVAudioFormat) {
        let engine = AVAudioEngine()
        self.engine = engine
        tones = VoicePool(engine, size: 8, format: format)
        // Web Audio bandpass Q 1 ≈ 1.39 octaves: BW = 2·asinh(1/2Q)/ln 2
        clicks = VoicePool(engine, size: 2, format: format, filter: (type: .bandPass, frequency: 2000, bandwidth: 1.39))
        // Plain (non-resonant) high/low pass; bandwidth is ignored for these types
        shimmer = VoicePool(engine, size: 4, format: format, filter: (type: .highPass, frequency: 4000, bandwidth: 1))
        buzz = VoicePool(engine, size: 1, format: format, filter: (type: .lowPass, frequency: 1000, bandwidth: 1))
        let drone = AVAudioPlayerNode()
        engine.attach(drone)
        engine.connect(drone, to: engine.mainMixerNode, format: format)
        self.drone = drone
    }

    /// Players stop when the engine does; after a (re)start they must be played again.
    func restartPlayers() {
        for pool in [tones, clicks, shimmer, buzz] { pool.restart() }
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

    func play(_ buffer: AVAudioPCMBuffer?) {
        guard let buffer else { return }
        let player = players[next]
        next = (next + 1) % players.count
        player.scheduleBuffer(buffer, at: nil, options: .interrupts, completionHandler: nil)
    }
}

// MARK: - Synthesis

/// One oscillator note with the JS gain envelope: starts at `gain`, ramps exponentially to 0.001
/// over `length` (or linearly to 0 for the rotate click), then stops. `at` delays it within the buffer.
private struct Note {
    enum Wave { case sine, sawtooth, noise }
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

/// Drone: 40 Hz sine, vibrato ±2 Hz at `vibratoHz`, gain 0.03, exactly 1 s for a seamless `.loops`.
/// f(t) = 40 + 2·sin(2πLt)  ⇒  phase(t) = 2π·40·t + (2/L)·(1 − cos 2πLt).
/// At t = 1 with integer L the FM term is back to 0 and the carrier has done 40 whole cycles,
/// so the last frame flows into frame 0 with continuous phase.
private func renderDrone(_ format: AVAudioFormat, vibratoHz: Int) -> AVAudioPCMBuffer? {
    let lfo = Double(max(vibratoHz, 0))
    return renderBuffer(format, duration: 1) { t in
        let vibrato = lfo > 0 ? 2 / lfo * (1 - cos(2 * .pi * lfo * t)) : 0
        return 0.03 * sin(2 * .pi * 40 * t + vibrato)
    }
}
