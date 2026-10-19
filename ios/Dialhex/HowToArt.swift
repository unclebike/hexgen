// HowToArt.swift — The small looping drawings beside each how-to-play rule
//
// Each rule in skins.json names its drawing with `art`:
//   bin     triangles fall in and stack until one more has nowhere to go
//   dial    six triangles turning a step at a time under the dial's outline
//   hex     the sixth triangle lands, the hex flashes and clears for points
//   levels  six hexes tick by, then a new colour joins the row
//   glow    a glowing triangle pulses, then clears with a burst
//   modes   a timer sweeping round, for SPRINT's three minutes
//   touch   a tap grabs the dial, the next taps turn it
//
// Drawn in the skin like the board: piece colours, marks, ink lines.
// With Reduce Motion each holds one telling frame. The drawings work in phone
// points on a 64-point square; on Apple TV the context is scaled up to match.

import DialhexCore
import SwiftUI

struct HowToArt: View {
    let art: String
    let skin: Skin
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static let side: CGFloat = 64
    /// View points per drawing point. Line weights' hairline and skin fonts are
    /// already in view points, so they're divided by this before drawing.
    private static let unit = pt(1)

    var body: some View {
        TimelineView(.animation(paused: reduceMotion)) { timeline in
            let loop = Self.loop(art)
            let p = reduceMotion ? Self.still(art)
                : timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: loop)
            Canvas { context, size in
                context.scaleBy(x: Self.unit, y: Self.unit)
                draw(&context, size: CGSize(width: size.width / Self.unit, height: size.height / Self.unit), p: p)
            }
        }
        .frame(width: pt(Self.side), height: pt(Self.side))
        .accessibilityHidden(true)
    }

    /// Seconds per loop.
    private static func loop(_ art: String) -> Double {
        switch art {
        case "bin": 4.8
        case "dial": 4.8
        case "levels": 4.2
        case "touch": 4.0
        case "modes": 3.4
        default: 3.0
        }
    }

    /// The moment shown when motion is reduced.
    private static func still(_ art: String) -> Double {
        switch art {
        case "bin": 3.0       // full, with one more waiting
        case "dial": 0.5      // mid-turn
        case "hex": 0.5       // the last triangle on its way in
        case "levels": 2.0    // a few colours in, hexes counting
        case "glow": 0.4      // glowing
        case "modes": 1.8     // part way round
        case "touch": 0.7     // grabbed
        default: 0
        }
    }

    private func draw(_ context: inout GraphicsContext, size: CGSize, p: Double) {
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        switch art {
        case "bin": drawBin(&context, size: size, p: p)
        case "dial": drawDial(&context, center: center, p: p)
        case "hex": drawHex(&context, center: center, p: p)
        case "levels": drawLevels(&context, center: center, p: p)
        case "glow": drawGlow(&context, center: center, p: p)
        case "modes": drawTimer(&context, center: center, p: p)
        case "touch": drawTouch(&context, center: center, p: p)
        default: break
        }
    }

    // MARK: - The drawings

    /// Nine triangles drop into the bin, bottom row first; a tenth waits above, blinking.
    private func drawBin(_ context: inout GraphicsContext, size: CGSize, p: Double) {
        let s: CGFloat = 14
        let h = s * root3 / 2
        // The bin is three rows deep, with one row of room above it for the one that won't fit
        let top = (size.height - 4 * h) / 2 + h
        let cx = size.width / 2
        let weights = LineWeights(scale: s)
        var layer = context
        layer.opacity = 1 - smooth((p - 4.2) / 0.4)

        // Slots, bottom row first, then left to right
        var slots: [[CGPoint]] = []
        for row in (0..<3).reversed() {
            let y0 = top + CGFloat(row) * h
            let left = cx - 1.5 * s + CGFloat(row) * s / 2
            for j in 0..<(2 * (2 - row) + 1) {
                let x = left + CGFloat(j / 2) * s
                slots.append(j % 2 == 0
                    ? [CGPoint(x: x, y: y0), CGPoint(x: x + s, y: y0), CGPoint(x: x + s / 2, y: y0 + h)]
                    : [CGPoint(x: x + s, y: y0), CGPoint(x: x + s * 1.5, y: y0 + h), CGPoint(x: x + s / 2, y: y0 + h)])
            }
        }
        let colors = [0, 1, 1, 0, 2, 0, 2, 1, 0]
        for (i, slot) in slots.enumerated() {
            let fall = clamp((p - 0.15 - Double(i) * 0.24) / 0.3)
            guard fall > 0 else { continue }
            // Accelerate down from just above the bin
            let drop = (1 - fall * fall) * (slot[0].y - (top - h))
            piece(&layer, slot.map { CGPoint(x: $0.x, y: $0.y - drop) }, color: colors[i], side: s)
        }

        // No room: the next one hangs over the full bin, and the bin's edge goes heavy
        let full = p >= 2.5
        if full {
            var waiting = layer
            waiting.opacity = 0.35 + 0.65 * (0.5 + 0.5 * cos(2 * .pi * (p - 2.5) / 0.5))
            piece(&waiting, [CGPoint(x: cx, y: top - h - 1), CGPoint(x: cx + s / 2, y: top - 1),
                             CGPoint(x: cx - s / 2, y: top - 1)], color: 2, side: s)
        }
        let bin = Path(Marks.polygon([CGPoint(x: cx - 1.5 * s, y: top), CGPoint(x: cx + 1.5 * s, y: top),
                                      CGPoint(x: cx, y: top + 3 * h)]))
        layer.stroke(bin, with: .color(skin.ink.color), style: sharp(full ? weights.heavy : weights.line))
    }

    /// A hex of mixed colours turning a sixth at a time; six steps make a full, seamless loop.
    private func drawDial(_ context: inout GraphicsContext, center: CGPoint, p: Double) {
        let r: CGFloat = 22
        let step = 0.8
        let turns = floor(p / step) + smooth(p.truncatingRemainder(dividingBy: step) / 0.3)
        var layer = context
        layer.translateBy(x: center.x, y: center.y)
        layer.rotate(by: .radians(turns * .pi / 3))
        for (i, triangle) in hexTriangles(.zero, r).enumerated() {
            piece(&layer, triangle, color: [0, 1, 2, 0, 1, 2][i], side: r)
        }
        context.stroke(Path(Marks.polygon(hexCorners(center, r))), with: .color(skin.ink.color),
                       style: sharp(LineWeights(scale: r).heavy))
    }

    /// Five of a colour wait; the sixth drops in, the hex flashes and clears, and its points float up.
    private func drawHex(_ context: inout GraphicsContext, center: CGPoint, p: Double) {
        let r: CGFloat = 20
        let weights = LineWeights(scale: r)
        let hexPath = Path(Marks.polygon(hexCorners(center, r)))
        let landed = 0.75
        let cleared = 0.85
        context.stroke(hexPath, with: .color(skin.ink.color(weights.hairlineAlpha)), style: sharp(weights.hairline / Self.unit))

        if p < cleared || p > 2.0 {
            var pieces = context
            pieces.opacity = p > 2.0 ? smooth((p - 2.0) / 0.4) : 1
            let triangles = hexTriangles(center, r)
            for triangle in triangles.dropLast() { piece(&pieces, triangle, color: 0, side: r) }
            // The last one, upper left, falls in from above
            let fall = clamp((p - 0.3) / (landed - 0.3))
            if p < cleared && fall > 0 {
                let drop = (1 - fall * fall) * 30
                piece(&pieces, triangles[5].map { CGPoint(x: $0.x, y: $0.y - drop) }, color: 0, side: r)
            }
        }
        burst(&context, hexPath, center: center, p: p - landed, weights: weights)

        // The points, rising and fading
        let rise = clamp((p - cleared) / 1.0)
        if rise > 0 && rise < 1 {
            var text = context
            text.opacity = 1 - rise * rise
            text.draw(Text("+100").font(skin.font(.digits, 12 / Self.unit)).foregroundColor(skin.ink.color),
                      at: CGPoint(x: center.x, y: center.y - 10 * rise))
        }
    }

    /// The row of colours in play: six hexes tick by, and a new colour pops in. Three times.
    private func drawLevels(_ context: inout GraphicsContext, center: CGPoint, p: Double) {
        let s: CGFloat = 18
        let h = s * root3 / 2
        let period = 0.9
        let arrivals = 3
        var layer = context
        layer.opacity = 1 - smooth((p - 3.6) / 0.4)

        // Colours, alternating point up and down so they tile, like the HUD
        let rowY = center.y - 6
        let left = center.x - 1.5 * s
        for k in 0..<(2 + arrivals) {
            let arrived = k < 2 ? 0 : Double(k - 1) * period
            let pop = clamp((p - arrived) / 0.3)
            guard pop > 0 else { continue }
            let x = left + CGFloat(k) * s / 2
            let corners = k % 2 == 0
                ? [CGPoint(x: x + s / 2, y: rowY - h / 2), CGPoint(x: x + s, y: rowY + h / 2), CGPoint(x: x, y: rowY + h / 2)]
                : [CGPoint(x: x, y: rowY - h / 2), CGPoint(x: x + s, y: rowY - h / 2), CGPoint(x: x + s / 2, y: rowY + h / 2)]
            // Back-out pop: overshoot a touch, then settle
            let q = pop - 1
            let scale = k < 2 ? 1 : 1 + 2.2 * q * q * q + 1.2 * q * q
            piece(&layer, Marks.scaled(corners, by: scale), color: k, side: s)
        }

        // Six marks under the row fill one per hex, and empty when the colour arrives
        let level = Int(p / period)
        let ticks = level < arrivals ? min(6, Int(p.truncatingRemainder(dividingBy: period) / period * 7)) : 0
        let tick: CGFloat = 4
        let gap: CGFloat = 3
        let start = center.x - (6 * tick + 5 * gap) / 2
        for i in 0..<6 {
            let rect = CGRect(x: start + CGFloat(i) * (tick + gap), y: rowY + h / 2 + 10, width: tick, height: tick)
            if i < ticks {
                layer.fill(Path(rect), with: .color(skin.ink.color))
            } else {
                layer.stroke(Path(rect.insetBy(dx: 0.5, dy: 0.5)), with: .color(skin.ink.color(0.5)), style: sharp(1))
            }
        }
    }

    /// A hex with one glowing triangle; it clears with a bigger burst than a plain hex.
    private func drawGlow(_ context: inout GraphicsContext, center: CGPoint, p: Double) {
        let r: CGFloat = 20
        let weights = LineWeights(scale: r)
        let hexPath = Path(Marks.polygon(hexCorners(center, r)))
        let fire = 1.6
        context.stroke(hexPath, with: .color(skin.ink.color(weights.hairlineAlpha)), style: sharp(weights.hairline / Self.unit))
        if p < fire + 0.1 || p > 2.3 {
            var pieces = context
            pieces.opacity = p > 2.3 ? smooth((p - 2.3) / 0.4) : 1
            let pulse = 0.5 - 0.4 * cos(2 * .pi * p / 0.78)
            for (i, triangle) in hexTriangles(center, r).enumerated() {
                piece(&pieces, triangle, color: 4, side: r, glow: i == 3 ? pulse : nil)
            }
        }
        burst(&context, hexPath, center: center, p: p - fire, weights: weights)
        // A second, wider ring for the power going off
        let q = (p - fire - 0.05) / 0.5
        if q >= 0 && q < 1 {
            var ring = context
            let grow = 1 + 0.6 * q
            ring.opacity = 1 - q
            ring.translateBy(x: center.x, y: center.y)
            ring.scaleBy(x: grow, y: grow)
            ring.translateBy(x: -center.x, y: -center.y)
            ring.stroke(hexPath, with: .color(skin.ink.color), style: sharp(weights.line / grow))
        }
    }

    /// A clock face sweeping round once, for SPRINT.
    private func drawTimer(_ context: inout GraphicsContext, center: CGPoint, p: Double) {
        let r: CGFloat = 24
        let weights = LineWeights(scale: r)
        let sweep = clamp(p / 2.8)
        let end = -Double.pi / 2 + sweep * 2 * .pi
        var layer = context
        layer.opacity = 1 - smooth((p - 3.0) / 0.4)

        var pie = Path()
        pie.move(to: center)
        pie.addArc(center: center, radius: r, startAngle: .radians(-.pi / 2), endAngle: .radians(end), clockwise: false)
        pie.closeSubpath()
        layer.fill(pie, with: .color(skin.piece(1).color))

        for i in 0..<12 {
            let a = Double(i) * .pi / 6
            var tick = Path()
            tick.move(to: CGPoint(x: center.x + cos(a) * r * 0.8, y: center.y + sin(a) * r * 0.8))
            tick.addLine(to: CGPoint(x: center.x + cos(a) * r, y: center.y + sin(a) * r))
            layer.stroke(tick, with: .color(skin.ink.color), style: sharp(weights.hairline / Self.unit))
        }
        var hand = Path()
        hand.move(to: center)
        hand.addLine(to: CGPoint(x: center.x + cos(end) * r, y: center.y + sin(end) * r))
        layer.stroke(hand, with: .color(skin.ink.color), style: sharp(weights.line))
        layer.stroke(Path(ellipseIn: CGRect(x: center.x - r, y: center.y - r, width: 2 * r, height: 2 * r)),
                     with: .color(skin.ink.color), style: sharp(weights.line))
    }

    /// A tap grabs the dial (its outline appears); two more taps each turn it a step.
    private func drawTouch(_ context: inout GraphicsContext, center: CGPoint, p: Double) {
        let r: CGFloat = 20
        let weights = LineWeights(scale: r)
        let taps = [0.4, 1.6, 2.8]
        // Two steps return the alternating colours to where they started, so the loop is seamless
        let turns = smooth((p - 1.7) / 0.25) + smooth((p - 2.9) / 0.25)
        var layer = context
        layer.translateBy(x: center.x, y: center.y)
        layer.rotate(by: .radians(turns * .pi / 3))
        for (i, triangle) in hexTriangles(.zero, r).enumerated() {
            piece(&layer, triangle, color: i % 2, side: r)
        }

        // The dial, from the first tap until the loop winds down
        let held = smooth((p - taps[0]) / 0.15) * (1 - smooth((p - 3.6) / 0.3))
        if held > 0 {
            var outline = context
            outline.opacity = held
            outline.stroke(Path(Marks.polygon(hexCorners(center, r))), with: .color(skin.ink.color),
                           style: sharp(weights.heavy))
        }

        // Each tap: a fingertip, and a ring spreading from it
        for tap in taps {
            let q = (p - tap) / 0.45
            guard q >= 0 && q < 1 else { continue }
            var touch = context
            touch.opacity = 1 - q
            let dot: CGFloat = 5
            touch.fill(Path(ellipseIn: CGRect(x: center.x - dot, y: center.y - dot, width: 2 * dot, height: 2 * dot)),
                       with: .color(skin.ink.color))
            let ring = dot + 16 * q
            touch.stroke(Path(ellipseIn: CGRect(x: center.x - ring, y: center.y - ring, width: 2 * ring, height: 2 * ring)),
                         with: .color(skin.ink.color), style: sharp(weights.line))
        }
    }

    // MARK: - Pieces

    /// One triangle the way the board draws it: inset, filled, outlined if the skin does, with its mark.
    /// `glow` (0…1) adds the pulsing inner edge of a power piece.
    private func piece(_ context: inout GraphicsContext, _ corners: [CGPoint], color: Int, side: CGFloat,
                       glow: Double? = nil) {
        let inset = Marks.scaled(corners, by: 0.9)
        let shape = Path(Marks.polygon(inset))
        let fill = skin.piece(color)
        let weights = LineWeights(scale: side)
        let markColor = skin.markColor(on: fill)
        context.fill(shape, with: .color(fill.color))
        if let outline = skin.spec.stroke.outline, let outlineColor = skin.spec.stroke.outlineColor {
            context.stroke(shape, with: .color(outlineColor.color),
                           style: sharp(outline == .heavy ? weights.heavy : weights.line))
        }
        let marks = Brand.tokens.marks
        if marks.indices.contains(color) {
            let mark = Marks.path(marks[color], corners: inset, lineWidth: weights.line,
                                  scale: CGFloat(skin.spec.stroke.markScale ?? 1))
            context.fill(Path(mark), with: .color(markColor.color))
        }
        if let glow {
            // A band inside the edge, as on the board
            let mid = Marks.centroid(inset)
            let inradius = hypot(inset[0].x - mid.x, inset[0].y - mid.y) / 2
            var band = Path(Marks.polygon(inset))
            band.addPath(Path(Marks.polygon(Marks.scaled(inset, by: max(0, 1 - weights.heavy / inradius)).reversed())))
            context.fill(band, with: .color(markColor.color(glow)))
        }
    }

    /// The hex flashing in ink as it completes, its outline ringing out; `p` is seconds since it formed.
    private func burst(_ context: inout GraphicsContext, _ hexPath: Path, center: CGPoint, p: Double,
                       weights: LineWeights) {
        let q = p / 0.3
        guard q >= 0 && q < 1 else { return }
        var flash = context
        flash.opacity = 0.7 * (1 - q)
        flash.fill(hexPath, with: .color(skin.ink.color))
        var ring = context
        let grow = 1 + 0.3 * q
        ring.opacity = 1 - q
        ring.translateBy(x: center.x, y: center.y)
        ring.scaleBy(x: grow, y: grow)
        ring.translateBy(x: -center.x, y: -center.y)
        ring.stroke(hexPath, with: .color(skin.ink.color), style: sharp(weights.heavy / grow))
    }

    /// Corners of a pointy-top hex, like the dials on the board, clockwise from the top.
    private func hexCorners(_ c: CGPoint, _ r: CGFloat) -> [CGPoint] {
        (0..<6).map { i in
            let a = -Double.pi / 2 + Double(i) * .pi / 3
            return CGPoint(x: c.x + cos(a) * r, y: c.y + sin(a) * r)
        }
    }

    /// The hex's six triangles, clockwise from the upper right.
    private func hexTriangles(_ c: CGPoint, _ r: CGFloat) -> [[CGPoint]] {
        let corners = hexCorners(c, r)
        return (0..<6).map { [c, corners[$0], corners[($0 + 1) % 6]] }
    }
}

private let root3 = CGFloat(3).squareRoot()

private func clamp(_ x: Double) -> Double { min(1, max(0, x)) }

private func smooth(_ x: Double) -> Double {
    let t = clamp(x)
    return t * t * (3 - 2 * t)
}
