// IntroView.swift — The two-second launch intro
//
//   0.00–0.95  triangles drop in and lock into a flower of seven hexes, centred
//              where the menu's logo sits, each flashing as its sixth triangle lands
//   0.95–1.45  the flower bursts apart
//   0.80–1.55  the logo sweeps in from the right, overshoots a touch, and lands
//              exactly on the menu's own logo
//   1.40–2.00  the menu builds in underneath as the intro fades over it; since the
//              two logos coincide, the logo itself never moves or pops
//
// Tap (or any controller button) skips it. With Reduce Motion it's a short fade.

import DialhexCore
import SwiftUI

struct IntroView: View {
    let model: AppModel
    /// The menu bin's frame in the root view's coordinate space; the intro's logo lands on the logo inside it.
    let target: CGRect?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var start = Date()

    static let length = 2.0
    private static let fallTime = 0.34
    private static let burstStart = 0.95
    private static let burstTime = 0.5
    private static let logoStart = 0.8
    private static let logoTime = 0.75
    private static let revealStart = 1.4
    private static let fadeStart = 1.55

    /// One triangle of the flower, at unit side, about its own centroid.
    private struct Piece {
        let hex: Int
        /// Resting centroid, relative to the flower's centre.
        let home: CGPoint
        let shape: Path
        let mark: Path?
        /// When it starts falling, and which way it spins on the way down.
        let delay: Double
        let spin: Double
    }

    private static let pieces: [Piece] = {
        let root3 = 3.0.squareRoot()
        // The centre hex, then the ring clockwise from the right
        let centers = [CGPoint.zero] + (0..<6).map { i in
            let a = Double(i) * .pi / 3
            return CGPoint(x: cos(a) * root3, y: sin(a) * root3)
        }
        let marks = Brand.tokens.marks
        let line = LineWeights(scale: 1).line
        var pieces: [Piece] = []
        // Fill bottom-up, like gravity, so nothing falls through a hex that has already landed:
        // the lower pair, the sides, the centre, then the upper pair
        for (order, hex) in [2, 3, 1, 4, 0, 6, 5].enumerated() {
            let c = centers[hex]
            // Pointy-top hex, like the dials on the board
            let corners = (0..<6).map { i -> CGPoint in
                let a = -Double.pi / 2 + Double(i) * .pi / 3
                return CGPoint(x: c.x + cos(a), y: c.y + sin(a))
            }
            // Within a hex too, lowest triangle first
            let triangles = (0..<6).map { [c, corners[$0], corners[($0 + 1) % 6]] }
                .sorted { Marks.centroid($0).y > Marks.centroid($1).y }
            for (i, triangle) in triangles.enumerated() {
                let mid = Marks.centroid(triangle)
                let local = Marks.scaled(triangle, by: 0.9).map { CGPoint(x: $0.x - mid.x, y: $0.y - mid.y) }
                let color = colorIndex(hex)
                let mark = marks.indices.contains(color) ? Path(Marks.path(marks[color], corners: local, lineWidth: line)) : nil
                // A fixed scatter, so the intro plays the same every launch
                let jitter = Double((hex * 7 + i * 3) % 5) * 0.006
                pieces.append(Piece(hex: hex, home: mid, shape: Path(Marks.polygon(local)), mark: mark,
                                    delay: Double(order) * 0.075 + Double(i) * 0.028 + jitter,
                                    spin: (i + hex) % 2 == 0 ? 1 : -1))
            }
        }
        return pieces
    }()

    private static func colorIndex(_ hex: Int) -> Int { hex % Progression.colorCount }

    /// When each hex's last triangle lands.
    private static let formed: [Double] = (0..<7).map { hex in
        pieces.filter { $0.hex == hex }.map { $0.delay + fallTime }.max() ?? 0
    }

    var body: some View {
        let skin = model.skin
        GeometryReader { proxy in
            // The target in this view's own coordinates (it runs under the safe areas)
            let origin = proxy.frame(in: .named(RootView.space)).origin
            let bin = target.map { $0.offsetBy(dx: -origin.x, dy: -origin.y) }
            TimelineView(.animation) { timeline in
                let t = timeline.date.timeIntervalSince(start)
                Canvas { context, size in
                    let logo = Self.logo(in: bin, size: size)
                    if reduceMotion {
                        drawLogo(&context, logo: logo, size: size, t: 1, skin: skin)
                    } else {
                        draw(&context, size: size, logo: logo, t: t, skin: skin)
                    }
                }
                .background(skin.background.color)
                .opacity(fade(t))
            }
        }
        .ignoresSafeArea()
        .contentShape(Rectangle())
        .onTapGesture { model.finishIntro() }
        .accessibilityLabel(Brand.tokens.logo.word)
        .accessibilityAddTraits(.isHeader)
        .task {
            start = Date()
            if !reduceMotion {
                // Beats for each hex forming, then hand over to the menu
                for (index, time) in Self.formed.sorted().enumerated() {
                    try? await Task.sleep(until: .now + .seconds(time - Date().timeIntervalSince(start)))
                    model.introBeat(index)
                }
            }
            let reveal = reduceMotion ? 0.3 : Self.revealStart
            try? await Task.sleep(for: .seconds(max(0, reveal - Date().timeIntervalSince(start))))
            model.revealMenu()
            let length = reduceMotion ? 0.8 : Self.length
            try? await Task.sleep(for: .seconds(max(0, length - Date().timeIntervalSince(start))))
            model.finishIntro()
        }
    }

    private func fade(_ t: Double) -> Double {
        if reduceMotion { return 1 - smooth((t - 0.4) / 0.4) }
        return 1 - smooth((t - Self.fadeStart) / (Self.length - Self.fadeStart))
    }

    // MARK: - Drawing

    /// The logo exactly as the menu lays it into its bin, as one path; centred on
    /// the screen instead if the menu's bin hasn't reported in.
    private static func logo(in bin: CGRect?, size: CGSize) -> Path {
        let cells = bin.map { Marks.logoInBin(center: CGPoint(x: $0.midX, y: $0.midY), boardSide: $0.height / CGFloat(2 * Grid.size)).cells }
            ?? Marks.logoFitted(width: min(size.width * 0.8, 420), center: CGPoint(x: size.width / 2, y: size.height / 2)).cells
        return Path { path in
            for cell in cells { path.addPath(Path(Marks.polygon(Marks.scaled(cell.corners, by: 0.9)))) }
        }
    }

    private func draw(_ context: inout GraphicsContext, size: CGSize, logo: Path, t: Double, skin: Skin) {
        // The flower is 3·√3 sides wide and 5 tall, and forms where the logo will land
        let side = min(size.width * 0.62 / (3 * 3.0.squareRoot()), size.height * 0.42 / 5)
        let center = CGPoint(x: logo.boundingRect.midX, y: logo.boundingRect.midY)
        let weights = LineWeights(scale: side)
        let burst = clamp((t - Self.burstStart) / Self.burstTime)

        // Landed triangles draw over falling ones, so a late piece never covers a settled hex
        let order = Self.pieces.sorted { ($0.delay + Self.fallTime <= t ? 1 : 0) < ($1.delay + Self.fallTime <= t ? 1 : 0) }
        for piece in order {
            let fall = clamp((t - piece.delay) / Self.fallTime)
            guard fall > 0, burst < 1 else { continue }
            // Falling: accelerate in from above the screen, spinning into place
            let drop = (1 - fall * fall) * (size.height * 0.6 + piece.home.y * side)
            var position = CGPoint(x: center.x + piece.home.x * side, y: center.y + piece.home.y * side - drop)
            var angle = piece.spin * .pi / 3 * (1 - fall) * (1 - fall)
            var scale = side
            var opacity = 1.0
            if burst > 0 {
                // Fly out from the centre, tumbling and shrinking
                let out = 1 - (1 - burst) * (1 - burst)
                position.x += piece.home.x * side * 2.6 * out
                position.y += piece.home.y * side * 2.6 * out
                angle += piece.spin * .pi * out
                scale *= 1 - 0.6 * out
                opacity = 1 - burst
            }
            var layer = context
            layer.opacity = opacity
            layer.translateBy(x: position.x, y: position.y)
            layer.rotate(by: .radians(angle))
            layer.scaleBy(x: scale, y: scale)
            let fill = skin.piece(Self.colorIndex(piece.hex))
            layer.fill(piece.shape, with: .color(fill.color))
            if let outline = skin.spec.stroke.outline, let outlineColor = skin.spec.stroke.outlineColor {
                let width = (outline == .heavy ? weights.heavy : weights.line) / side
                layer.stroke(piece.shape, with: .color(outlineColor.color), style: StrokeStyle(lineWidth: width, lineJoin: .miter))
            }
            if let mark = piece.mark {
                layer.fill(mark, with: .color(skin.markColor(on: fill).color))
            }
        }

        // Each hex flashes in ink as it forms, and its outline rings out
        for (hex, time) in Self.formed.enumerated() {
            let p = (t - time) / 0.22
            guard p >= 0, p < 1 else { continue }
            let c = hex == 0 ? CGPoint.zero : CGPoint(x: cos(Double(hex - 1) * .pi / 3) * 3.0.squareRoot(),
                                                     y: sin(Double(hex - 1) * .pi / 3) * 3.0.squareRoot())
            let hexPath = Path(Marks.polygon((0..<6).map { i in
                let a = -Double.pi / 2 + Double(i) * .pi / 3
                return CGPoint(x: center.x + (c.x + cos(a)) * side, y: center.y + (c.y + sin(a)) * side)
            }))
            var flash = context
            flash.opacity = 0.7 * (1 - p)
            flash.fill(hexPath, with: .color(skin.ink.color))
            var ring = context
            let grow = 1 + 0.25 * p
            let mid = CGPoint(x: center.x + c.x * side, y: center.y + c.y * side)
            ring.translateBy(x: mid.x, y: mid.y)
            ring.scaleBy(x: grow, y: grow)
            ring.translateBy(x: -mid.x, y: -mid.y)
            ring.opacity = 1 - p
            ring.stroke(hexPath, with: .color(skin.ink.color),
                        style: StrokeStyle(lineWidth: weights.heavy / grow, lineJoin: .miter))
        }

        drawLogo(&context, logo: logo, size: size, t: (t - Self.logoStart) / Self.logoTime, skin: skin)
    }

    /// The logo sweeping in from the right onto where it rests; `t` runs 0…1 over
    /// the sweep and holds in place after.
    private func drawLogo(_ context: inout GraphicsContext, logo: Path, size: CGSize, t: Double, skin: Skin) {
        guard t > 0 else { return }
        let travel = size.width - logo.boundingRect.minX + pt(24) // starts just off the right edge
        // Back-out: fast in, a small overshoot to the left, then settle
        let offset = { (t: Double) -> Double in
            let p = clamp(t) - 1
            let back = 1.1
            return -(1 + (back + 1) * p * p * p + back * p * p) * travel + travel
        }
        let x = reduceMotion ? 0 : offset(t)
        // A couple of trailing copies for a hint of motion blur, gone once it slows
        let speed = reduceMotion || t >= 1 ? 0 : abs(offset(t + 0.01) - x) / (0.01 * travel)
        for ghost in stride(from: 2, through: 0, by: -1) {
            let lag = Double(ghost) * min(pt(14), speed * pt(5))
            guard ghost == 0 || lag > pt(1) else { continue }
            var layer = context
            layer.opacity = ghost == 0 ? 1 : 0.1 / Double(ghost)
            layer.translateBy(x: x + lag, y: 0)
            layer.fill(logo, with: .color(skin.ink.color))
        }
    }
}

private func clamp(_ x: Double) -> Double { min(1, max(0, x)) }
private func smooth(_ x: Double) -> Double {
    let t = clamp(x)
    return t * t * (3 - 2 * t)
}
