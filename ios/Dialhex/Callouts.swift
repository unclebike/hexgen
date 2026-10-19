// Callouts.swift — One quiet line beside the bin when play shifts
//
// Tips wait for a pause; callouts say what just changed while it happens, in
// the HUD's stats column and never over the bin. Each one explains itself the
// first few times it shows, then shrinks to its title. The first-time kinds
// (a glowing piece, the dial holding one) stop once they've explained.

import SwiftUI
import DialhexCore

/// What a callout is about, most important first: a more important one
/// cuts a less important one short.
enum CalloutKind: String, CaseIterable {
    case rescue, drain, swap, levelUp, finale, danger, hint, glow, held

    /// Teaches something once: shown only while it explains, at most once a game.
    var firstTimesOnly: Bool { self == .glow || self == .held || self == .hint }

    fileprivate var rank: Int { Self.allCases.firstIndex(of: self)! }
}

struct Callout: Equatable, Identifiable {
    let id: Int
    let kind: CalloutKind
    let title: String
    /// The line that explains it; dropped once the player has seen it enough.
    var detail: String?
    /// Colours drawn after the title: the new colour, or a swap's from and to.
    let colors: [Int]
}

/// Queues callouts and shows them one at a time, on the game's clock so a
/// pause holds them. Remembers how often each kind has shown, across games.
@MainActor
final class CalloutFeed {
    private static let seenKey = "dialhex_callouts_seen"
    /// Showings that carry the explaining line.
    private static let explainedShowings = 3
    /// Seconds on screen with just a title, and with the explaining line too.
    private static let briefTime = 1.6
    private static let explainedTime = 3.4
    /// Seconds of nothing between two callouts, so one fades before the next.
    private static let gapTime = 0.25
    /// Callouts waiting beyond this are stale by the time they'd show.
    private static let maxWaiting = 2

    private(set) var current: Callout?
    private var timeLeft = 0.0
    private var gapLeft = 0.0
    private var waiting: [Callout] = []
    private var postedThisGame: Set<CalloutKind> = []
    private var seen: [String: Int]
    private var nextID = 0

    init() {
        seen = UserDefaults.standard.dictionary(forKey: Self.seenKey) as? [String: Int] ?? [:]
    }

    /// Whether posting `kind` now would show anything.
    func wants(_ kind: CalloutKind) -> Bool {
        !kind.firstTimesOnly || (!postedThisGame.contains(kind) && showings(kind) < Self.explainedShowings)
    }

    /// Say `kind` happened. `fill` replaces `{key}` placeholders in its copy.
    func post(_ kind: CalloutKind, fill: [String: String] = [:], colors: [Int] = []) {
        guard wants(kind) else { return }
        let copy = Brand.copy.callouts[kind]
        postedThisGame.insert(kind)
        func filled(_ text: String) -> String {
            fill.reduce(text) { $0.replacingOccurrences(of: "{\($1.key)}", with: $1.value) }
        }
        let callout = Callout(id: nextID, kind: kind, title: filled(copy.title),
                              detail: copy.detail.map(filled), colors: colors)
        nextID += 1

        // A newer one of the same kind replaces the old; a more important one cuts in
        waiting.removeAll { $0.kind == kind }
        if let current, current.kind.rank > kind.rank || current.kind == kind {
            show(callout)
            return
        }
        waiting.append(callout)
        waiting.sort { $0.kind.rank < $1.kind.rank }
        if waiting.count > Self.maxWaiting { waiting.removeLast(waiting.count - Self.maxWaiting) }
        if current == nil && gapLeft <= 0 { showNext() }
    }

    /// Advance by `dt` seconds of play.
    func tick(_ dt: Double) {
        if current != nil {
            timeLeft -= dt
            if timeLeft <= 0 {
                current = nil
                gapLeft = Self.gapTime
            }
        } else if gapLeft > 0 {
            gapLeft -= dt
            if gapLeft <= 0 { showNext() }
        }
    }

    /// A new game: nothing showing or waiting, and the first-time kinds may teach again.
    func reset() {
        current = nil
        waiting = []
        gapLeft = 0
        postedThisGame = []
    }

    private func showings(_ kind: CalloutKind) -> Int { seen[kind.rawValue, default: 0] }

    private func showNext() {
        guard !waiting.isEmpty else { return }
        show(waiting.removeFirst())
    }

    private func show(_ callout: Callout) {
        var callout = callout
        if showings(callout.kind) >= Self.explainedShowings { callout.detail = nil }
        seen[callout.kind.rawValue] = showings(callout.kind) + 1
        UserDefaults.standard.set(seen, forKey: Self.seenKey)
        current = callout
        timeLeft = callout.detail == nil ? Self.briefTime : Self.explainedTime
        gapLeft = 0
        let spoken = [callout.title, callout.detail].compactMap(\.self).joined(separator: " ")
        AccessibilityNotification.Announcement(spoken).post()
    }
}

// MARK: - View

/// A callout in the HUD: its title in display type, any colours it's about,
/// and the explaining line under it in secondary ink. Where the height offered
/// can't take the explaining line (over the bin on a small phone), it's just the title.
struct CalloutView: View {
    let callout: Callout
    let skin: Skin
    var alignment: HorizontalAlignment = .center

    var body: some View {
        ViewThatFits(in: .vertical) {
            full
            title
        }
        .multilineTextAlignment(alignment == .leading ? .leading : .center)
        // It's announced as it appears; VoiceOver needn't find it again
        .accessibilityHidden(true)
    }

    private var full: some View {
        VStack(alignment: alignment, spacing: pt(3)) {
            title
            if let detail = callout.detail {
                Text(detail)
                    .font(skin.font(.text, 12))
                    .foregroundStyle(skin.ink.color(secondary))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var title: some View {
        HStack(spacing: pt(6)) {
            Text(callout.title)
                .font(skin.font(.display, 15))
                .foregroundStyle(skin.ink.color)
            ForEach(Array(callout.colors.enumerated()), id: \.offset) { index, color in
                if index > 0 { arrow }
                ColorHex(color: color, count: 6, inPlay: true, skin: skin)
                    .frame(width: pt(14), height: pt(14) * 2 / 3.0.squareRoot())
            }
        }
    }

    /// A swap's "into", drawn at the line weight so it matches in every skin's font.
    private var arrow: some View {
        Canvas { context, size in
            var path = Path()
            let mid = size.height / 2
            path.move(to: CGPoint(x: 0, y: mid))
            path.addLine(to: CGPoint(x: size.width, y: mid))
            path.move(to: CGPoint(x: size.width - mid, y: 0))
            path.addLine(to: CGPoint(x: size.width, y: mid))
            path.addLine(to: CGPoint(x: size.width - mid, y: size.height))
            context.stroke(path, with: .color(skin.ink.color(secondary)), lineWidth: max(1, pt(1.5)))
        }
        .frame(width: pt(10), height: pt(8))
    }
}

#Preview("Callouts") {
    let samples = [
        Callout(id: 0, kind: .levelUp, title: "level 3.", detail: "a new colour joins. every hex now scores 300.", colors: [2]),
        Callout(id: 1, kind: .swap, title: "swap.", detail: "the glowing piece turned one colour into another.", colors: [0, 1]),
        Callout(id: 2, kind: .danger, title: "bin filling.", detail: nil, colors: []),
    ]
    VStack(spacing: 0) {
        ForEach([0, 2], id: \.self) { index in
            let skin = Skin(Brand.tokens.skins[index])
            VStack(spacing: 20) {
                ForEach(samples) { CalloutView(callout: $0, skin: skin) }
                CalloutView(callout: samples[1], skin: skin, alignment: .leading)
                    .frame(maxWidth: 120, alignment: .leading)
                // Over the bin on a small phone: too little height for the explaining line
                CalloutView(callout: samples[0], skin: skin)
                    .frame(maxWidth: 200, maxHeight: 40, alignment: .top)
                    .border(skin.ink.color(0.2))
            }
            .padding(24)
            .frame(maxWidth: .infinity)
            .background(skin.background.color)
        }
    }
}
