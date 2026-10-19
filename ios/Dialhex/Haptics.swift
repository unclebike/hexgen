// Haptics.swift — Device haptics (UIFeedbackGenerator) plus controller rumble (CoreHaptics)
//
// Apple TV has no device haptics, so there only the controller rumbles.

import CoreHaptics
import GameController
import UIKit

enum HapticEvent { case rotate, clear(hexes: Int), power, levelUp, gameOver }

@MainActor
final class Haptics {
    #if os(iOS)
    private let light = UIImpactFeedbackGenerator(style: .light)
    private let medium = UIImpactFeedbackGenerator(style: .medium)
    private let heavy = UIImpactFeedbackGenerator(style: .heavy)
    private let rigid = UIImpactFeedbackGenerator(style: .rigid)
    private let notification = UINotificationFeedbackGenerator()
    #endif

    private weak var controller: GCController?
    /// Created lazily for `controller`; dropped (and rebuilt on next play) when it stops or resets.
    private var engine: CHHapticEngine?

    init() {
        #if os(iOS)
        light.prepare()
        #endif
    }

    /// The controller to rumble; nil = rumble the device only.
    func setController(_ controller: GCController?) {
        guard controller !== self.controller else { return }
        engine?.stop(completionHandler: nil)
        engine = nil
        self.controller = controller
    }

    func play(_ event: HapticEvent) {
        playDevice(event)
        playController(event)
    }

    // MARK: - Device

    private func playDevice(_ event: HapticEvent) {
        #if os(iOS)
        switch event {
        case .rotate:
            light.impactOccurred()
            light.prepare()
        case .clear(let hexes):
            let generator = hexes >= 6 ? heavy : medium
            generator.impactOccurred(intensity: CGFloat(min(1, 0.55 + 0.05 * Double(hexes))))
            generator.prepare()
        case .power:
            rigid.impactOccurred()
        case .levelUp:
            notification.notificationOccurred(.success)
        case .gameOver:
            notification.notificationOccurred(.error)
        }
        #endif
    }

    // MARK: - Controller

    /// Short continuous pulses (controller motors don't render transients well):
    /// (start time, duration, intensity, sharpness).
    private static func pulses(for event: HapticEvent) -> [(TimeInterval, TimeInterval, Float, Float)] {
        switch event {
        case .rotate:
            return [(0, 0.04, 0.35, 0.8)]
        case .clear(let hexes):
            return [(0, 0.08 + 0.01 * Double(min(hexes, 12)), min(1, 0.5 + 0.05 * Float(hexes)), 0.5)]
        case .power:
            return [(0, 0.06, 0.8, 0.9), (0.1, 0.12, 1, 0.4)]
        case .levelUp:
            return [(0, 0.06, 0.5, 0.6), (0.1, 0.06, 0.7, 0.6), (0.2, 0.1, 1, 0.6)]
        case .gameOver:
            return [(0, 0.35, 1, 0.2), (0.4, 0.5, 0.6, 0.1)]
        }
    }

    private func playController(_ event: HapticEvent) {
        guard let engine = controllerEngine() else { return }
        var events: [CHHapticEvent] = []
        for (start, duration, intensity, sharpness) in Self.pulses(for: event) {
            events.append(CHHapticEvent(eventType: .hapticContinuous, parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: sharpness),
            ], relativeTime: start, duration: duration))
        }
        do {
            let pattern = try CHHapticPattern(events: events, parameters: [])
            try engine.makePlayer(with: pattern).start(atTime: CHHapticTimeImmediate)
        } catch {
            self.engine = nil // rebuilt on the next event
        }
    }

    private func controllerEngine() -> CHHapticEngine? {
        if let engine { return engine }
        guard let made = controller?.haptics?.createEngine(withLocality: .default) else { return nil }
        made.playsHapticsOnly = true
        // These run on a CoreHaptics queue: hop to the main actor and forget the engine if it's still ours.
        let id = ObjectIdentifier(made)
        made.resetHandler = { @Sendable [weak self] in
            Task { @MainActor in self?.engineDied(id) }
        }
        made.stoppedHandler = { @Sendable [weak self] _ in
            Task { @MainActor in self?.engineDied(id) }
        }
        do { try made.start() } catch { return nil }
        engine = made
        return made
    }

    private func engineDied(_ id: ObjectIdentifier) {
        if let engine, ObjectIdentifier(engine) == id { self.engine = nil }
    }
}
