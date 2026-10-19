// PadControls.swift — The phone controller's mini bin and dial, drawn like the game
//
// Two controls stand in for a gamepad: the bin in miniature, where a finger
// puts the dial (and the TV follows), and the dial itself, six triangles showing
// the pieces under it on the TV, which turns as you spin it. On the TV's menu
// the dial turns into a pad of arrows instead.

#if os(iOS)
import DialhexCore
import SwiftUI

/// Two bars, at the line weight, as on the game's pause button.
struct PauseBars: View {
    let skin: Skin
    let weights: LineWeights

    var body: some View {
        HStack(spacing: 6) {
            Rectangle().frame(width: max(2, weights.line), height: 16)
            Rectangle().frame(width: max(2, weights.line), height: 16)
        }
        .foregroundStyle(skin.ink.color)
    }
}

/// The radius of a hex standing on a corner that fits `size` with its outline
/// (drawn at the line weight) whole: a stroke's mitred corners reach past the
/// path by about 0.58 of its width.
func hexRadius(fitting size: CGSize) -> CGFloat {
    min(size.width / 3.0.squareRoot(), size.height / 2) / (1 + CGFloat(Brand.tokens.weights.line) * 0.6)
}

/// A hex standing on a corner, as big as fits: the controls only take touches inside
/// their own hex, since the pair sits close enough for their frames to overlap.
struct CornerHex: Shape {
    func path(in rect: CGRect) -> Path {
        let r = min(rect.width / 3.0.squareRoot(), rect.height / 2)
        return Path(Marks.polygon((0..<6).map { i in
            let a = (Double(i) * 60 + 30) * .pi / 180
            return CGPoint(x: rect.midX + r * cos(a), y: rect.midY - r * sin(a))
        }))
    }
}

/// The dial as a pad for the TV's menu: the same hex, empty, with a faint
/// arrow on each of its four sides. Tap toward a side (or swipe that way) to
/// move the selection; tap the middle to choose.
struct MenuDial: View {
    let skin: Skin
    let weights: LineWeights
    let move: (Direction) -> Void
    let choose: () -> Void

    /// The arrow just used, lit for a moment.
    @State private var lit: Direction?
    @State private var chose = false

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let radius = hexRadius(fitting: size)
            Canvas { context, _ in
                draw(&context, center: center, radius: radius)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onEnded { value in ended(value, center: center, radius: radius) }
            )
        }
        .accessibilityElement()
        .accessibilityLabel("Menu pad")
        .accessibilityHint("Moves the selection on the TV")
        .accessibilityAction(named: "Up") { move(.up) }
        .accessibilityAction(named: "Down") { move(.down) }
        .accessibilityAction(named: "Left") { move(.left) }
        .accessibilityAction(named: "Right") { move(.right) }
        .accessibilityAction(named: "Choose") { choose() }
    }

    private static func direction(dx: CGFloat, dy: CGFloat) -> Direction {
        abs(dx) >= abs(dy) ? (dx >= 0 ? .right : .left) : (dy >= 0 ? .down : .up)
    }

    private func ended(_ value: DragGesture.Value, center: CGPoint, radius: CGFloat) {
        let swipe = value.translation
        if hypot(swipe.width, swipe.height) > 24 {
            // A swipe goes the way it went, wherever it started
            pressed(Self.direction(dx: swipe.width, dy: swipe.height))
            return
        }
        // A tap: the middle chooses, anywhere else moves toward that side
        let dx = value.location.x - center.x, dy = value.location.y - center.y
        if hypot(dx, dy) < radius * 0.32 {
            choose()
            flash(nil)
        } else {
            pressed(Self.direction(dx: dx, dy: dy))
        }
    }

    private func pressed(_ direction: Direction) {
        move(direction)
        flash(direction)
    }

    /// Light what was used, then let it fade.
    private func flash(_ direction: Direction?) {
        lit = direction
        chose = direction == nil
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(160))
            withAnimation(.easeOut(duration: 0.2)) {
                lit = nil
                chose = false
            }
        }
    }

    private func draw(_ context: inout GraphicsContext, center: CGPoint, radius: CGFloat) {
        func point(_ degrees: Double, _ r: CGFloat) -> CGPoint {
            let a = degrees * .pi / 180
            return CGPoint(x: center.x + r * cos(a), y: center.y - r * sin(a))
        }
        let line = LineWeights(scale: radius)
        // The six empty triangles, as the dial shows them on the board
        for k in 0..<6 {
            let mid = Double(k) * 60
            let triangle = Marks.scaled([center, point(mid - 30, radius), point(mid + 30, radius)], by: 0.9)
            let shape = Path(Marks.polygon(triangle))
            context.fill(shape, with: .color(skin.empty.color))
            context.stroke(shape, with: .color(skin.ink.color(0.15)), style: sharp(max(1, weights.hairline)))
        }
        context.stroke(Path(Marks.polygon((0..<6).map { point(Double($0) * 60 + 30, radius) })),
                       with: .color(skin.ink.color), style: sharp(line.line))
        // A faint arrow toward each side, brighter when used
        let directions: [(Direction, Double)] = [(.right, 0), (.up, 90), (.left, 180), (.down, 270)]
        for (direction, degrees) in directions {
            let tip = point(degrees, radius * 0.74)
            let base = radius * 0.56
            let arrow = Path(Marks.polygon([tip, point(degrees - 9, base), point(degrees + 9, base)]))
            context.fill(arrow, with: .color(skin.ink.color(lit == direction ? 0.9 : 0.28)))
        }
        // The middle chooses
        let r = radius * (chose ? 0.12 : 0.09)
        context.fill(Path(ellipseIn: CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2)),
                     with: .color(skin.ink.color(chose ? 1 : 0.5)))
    }
}

/// The player's dial as a hex of six triangles, showing the pieces under it on
/// the TV. Drag around it to turn: it follows the finger and sends a turn for
/// every 60°, either way. A tap turns it forward (clockwise), like A.
struct DialSpinner: View {
    let skin: Skin
    let weights: LineWeights
    let dial: DialPieces
    /// Co-op: the player's colour, filling the centre dot as it does on their dial on the board.
    var tint: RGB? = nil
    let turn: (RotationDirection) -> Void

    /// How far the finger has turned past the last whole step, in radians (clockwise positive).
    @State private var spin: Double = 0
    /// The finger's angle at the last step, and whether it has moved enough to be a drag.
    @State private var anchor: Double?
    @State private var dragged = false

    private static let step = Double.pi / 3

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let radius = hexRadius(fitting: size)
            Canvas { context, _ in
                draw(&context, center: center, radius: radius)
            }
            .rotationEffect(.radians(spin))
            .contentShape(CornerHex())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in changed(value.location, start: value.startLocation, center: center, radius: radius) }
                    .onEnded { _ in ended() }
            )
        }
        .accessibilityElement()
        .accessibilityLabel("Dial")
        .accessibilityHint("Swipe up or down to turn it")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: turn(.clockwise)
            case .decrement: turn(.counterClockwise)
            @unknown default: break
            }
        }
    }

    /// The finger's angle around the centre, clockwise on screen.
    private static func angle(_ point: CGPoint, _ center: CGPoint) -> Double {
        atan2(Double(point.y - center.y), Double(point.x - center.x))
    }

    private func changed(_ location: CGPoint, start: CGPoint, center: CGPoint, radius: CGFloat) {
        // Near the centre the angle jumps about, so only a finger out toward the edge turns it
        let reach = hypot(location.x - center.x, location.y - center.y)
        if hypot(location.x - start.x, location.y - start.y) > 8 { dragged = true }
        guard dragged, reach > radius * 0.2 else { return }
        let now = Self.angle(location, center)
        guard let last = anchor else {
            anchor = now
            return
        }
        var delta = now - last
        if delta > .pi { delta -= 2 * .pi }
        if delta < -.pi { delta += 2 * .pi }
        anchor = now
        spin += delta
        // A whole step: send it, and take it off the spin (the pieces themselves move a slot)
        while spin >= Self.step {
            spin -= Self.step
            turn(.clockwise)
        }
        while spin <= -Self.step {
            spin += Self.step
            turn(.counterClockwise)
        }
    }

    private func ended() {
        if !dragged { turn(.clockwise) }
        anchor = nil
        dragged = false
        withAnimation(.spring(duration: 0.2, bounce: 0.2)) { spin = 0 }
    }

    private func draw(_ context: inout GraphicsContext, center: CGPoint, radius: CGFloat) {
        // Slot k's triangle points out at k·60° counter-clockwise from the right (y up on
        // the TV); SwiftUI's y runs down, so flip it
        func corner(_ degrees: Double) -> CGPoint {
            let a = degrees * .pi / 180
            return CGPoint(x: center.x + radius * cos(a), y: center.y - radius * sin(a))
        }
        let side = radius
        let line = LineWeights(scale: side)
        let marks = Brand.tokens.marks
        for (k, color) in dial.colors.enumerated() {
            let mid = Double(k) * 60
            let corners = [center, corner(mid - 30), corner(mid + 30)]
            let inset = Marks.scaled(corners, by: 0.9)
            let shape = Path(Marks.polygon(inset))
            guard let color else {
                context.fill(shape, with: .color(skin.empty.color))
                context.stroke(shape, with: .color(skin.ink.color(0.15)), style: sharp(max(1, weights.hairline)))
                continue
            }
            let fill = skin.piece(color)
            context.fill(shape, with: .color(fill.color))
            if let outline = skin.spec.stroke.outline, let outlineColor = skin.spec.stroke.outlineColor {
                context.stroke(shape, with: .color(outlineColor.color), style: sharp(outline == .heavy ? line.heavy : line.line))
            }
            if marks.indices.contains(color) {
                let mark = Marks.path(marks[color], corners: inset, lineWidth: line.line,
                                      scale: CGFloat(skin.spec.stroke.markScale ?? 1))
                context.fill(Path(mark), with: .color(skin.markColor(on: fill).color))
            }
        }
        // The dial's own outline and centre dot, as on the board
        let outline = Path(Marks.polygon((0..<6).map { corner(Double($0) * 60 + 30) }))
        context.stroke(outline, with: .color(skin.ink.color), style: sharp(line.line))
        if let tint {
            // A bigger dot in the player's colour, ringed in ink, as on the co-op board
            let dot = max(5, line.line * 3)
            let ring = Path(ellipseIn: CGRect(x: center.x - dot, y: center.y - dot, width: dot * 2, height: dot * 2))
            context.fill(ring, with: .color(tint.color))
            context.stroke(ring, with: .color(skin.ink.color), style: StrokeStyle(lineWidth: line.line))
        } else {
            let dot = max(3, line.line)
            context.fill(Path(ellipseIn: CGRect(x: center.x - dot, y: center.y - dot, width: dot * 2, height: dot * 2)),
                         with: .color(skin.ink.color))
        }
    }
}

/// The bin in miniature, one triangle for every triangle on the TV, empty: put a
/// finger down and the dial jumps to the matching spot on the TV, then follows
/// as it slides. The dial's outline shows where it really is, echoed from the TV.
struct BoardPad: View {
    let skin: Skin
    let weights: LineWeights
    /// Where the dial is on the TV.
    let vertex: Vertex?
    let place: (Vertex) -> Void

    /// Where the finger last put it, shown until the TV's word catches up.
    @State private var target: Vertex?

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            let n = CGFloat(Grid.size)
            // Pulled in a touch so the outline's corners aren't clipped
            let scale = min(size.width / (2 * n * Grid.rowHeight), size.height / (2 * n)) * 0.97
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            Canvas { context, _ in
                draw(&context, center: center, scale: scale)
            }
            .contentShape(CornerHex())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in touched(value.location, center: center, scale: scale) }
                    .onEnded { _ in target = nil }
            )
        }
        .accessibilityElement()
        .accessibilityLabel("Board")
        .accessibilityHint("Touch where the dial should go")
    }

    /// The lattice turned as on the TV: lattice x runs down the screen and lattice y right to left.
    private static func screen(_ p: LatticePoint, center: CGPoint, scale: CGFloat) -> CGPoint {
        CGPoint(x: center.x - CGFloat(p.y) * scale, y: center.y + CGFloat(p.x) * scale)
    }

    private func touched(_ location: CGPoint, center: CGPoint, scale: CGFloat) {
        let point = LatticePoint(Double((location.y - center.y) / scale), Double((center.x - location.x) / scale))
        guard let dial = Grid.nearestDial(to: point) else { return }
        target = dial
        place(dial)
    }

    private func draw(_ context: inout GraphicsContext, center: CGPoint, scale: CGFloat) {
        func path(_ points: [LatticePoint]) -> Path {
            Path(Marks.polygon(points.map { Self.screen($0, center: center, scale: scale) }))
        }
        let bin = path(Grid.binOutline)
        context.fill(bin, with: .color(skin.empty.color))
        // Every triangle of the bin, as faint as the board's own lattice
        var lattice = Path()
        for cell in Grid.cells { lattice.addPath(path(Grid.vertices(of: cell))) }
        context.stroke(lattice, with: .color(skin.ink.color(Brand.tokens.weights.hairlineAlpha * 2)),
                       style: sharp(max(1, weights.hairline)))
        let line = LineWeights(scale: scale)
        context.stroke(bin, with: .color(skin.ink.color(secondary)), style: sharp(line.line))

        // Where the finger is taking it, faintly, then the dial where the TV has it
        if let target, target != vertex {
            context.stroke(path(Grid.dialOutline(target)), with: .color(skin.ink.color(secondary)), style: sharp(line.line))
        }
        if let vertex {
            context.stroke(path(Grid.dialOutline(vertex)), with: .color(skin.ink.color), style: sharp(line.heavy))
            let dot = Self.screen(Grid.position(of: vertex), center: center, scale: scale)
            let r = max(2, line.line)
            context.fill(Path(ellipseIn: CGRect(x: dot.x - r, y: dot.y - r, width: r * 2, height: r * 2)),
                         with: .color(skin.ink.color))
        }
    }
}

#Preview("Controls") {
    let skin = Skin(Brand.tokens.skins[0])
    let weights = LineWeights(scale: 30)
    VStack(spacing: 24) {
        DialSpinner(skin: skin, weights: weights, dial: DialPieces(colors: [0, 1, nil, 2, 2, 5])) { _ in }
            .frame(width: 240, height: 240)
        BoardPad(skin: skin, weights: weights, vertex: Vertex(k: 6, j: 0)) { _ in }
            .frame(width: 300, height: 300)
        MenuDial(skin: skin, weights: weights) { _ in } choose: {}
            .frame(width: 240, height: 240)
        HStack(spacing: 14) {
            ButtonFace(skin: skin, weights: weights, width: 72, height: 44) { TrackedLabel(text: "A", size: 15, skin: skin) }
            ButtonFace(skin: skin, weights: weights, width: 72, height: 44) { PauseBars(skin: skin, weights: weights) }
        }
    }
    .padding()
    .background(skin.background.color)
}
#endif
