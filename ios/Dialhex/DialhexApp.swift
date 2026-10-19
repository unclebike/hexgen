// DialhexApp.swift — App entry and the SwiftUI screens around the SpriteKit board
//
// Everything is drawn in the current skin: one ink colour for all text and
// lines, colour only on the pieces, three line weights sized from the board.

import DialhexCore
import SpriteKit
import SwiftUI
import TipKit

// Apple TV starts from DialhexTV/TVApp.swift instead, to keep the remote for the game
#if os(iOS)
@main
struct DialhexApp: App {
    @State private var model = AppModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView(model: model)
                .statusBarHidden()
                .persistentSystemOverlays(.hidden)
                .preferredColorScheme(.dark)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { model.pauseIfPlaying() }
            if phase == .background { Lessons.sceneChanged(toBackground: true) }
            if phase == .active { Lessons.sceneChanged(toBackground: false) }
        }
    }
}
#endif

/// Apple TV: no touch screen, so no on-screen controls; the remote and gamepads play.
#if os(tvOS)
private let isTV = true
#else
private let isTV = false
#endif

extension Color {
    init(rgb: UInt32, opacity: Double = 1) {
        self.init(.sRGB,
                  red: Double((rgb >> 16) & 0xFF) / 255,
                  green: Double((rgb >> 8) & 0xFF) / 255,
                  blue: Double(rgb & 0xFF) / 255,
                  opacity: opacity)
    }
}

/// Extra letter spacing on one-word uppercase labels, in ems.
let labelTracking: CGFloat = 0.08
/// Opacity of secondary text; still the one ink colour.
let secondary: Double = 0.6
/// How much of the background covers the demo game behind the menu.
private let menuDim: Double = 0.5

func sharp(_ width: CGFloat) -> StrokeStyle {
    StrokeStyle(lineWidth: width, lineCap: .square, lineJoin: .miter)
}

/// Where the menu's bin (and the logo in it) is, in the root view's coordinate space.
struct MenuLogoFrame: PreferenceKey {
    static let defaultValue: CGRect? = nil
    static func reduce(value: inout CGRect?, nextValue: () -> CGRect?) { value = nextValue() ?? value }
}

struct RootView: View {
    let model: AppModel
    @State private var menuLogo: CGRect?

    /// The coordinate space the menu logo and the intro share.
    static let space = "root"

    var body: some View {
        GeometryReader { geometry in
            // Laid out at full size everywhere; Apple TV doubles fixed lengths through `pt(_:)`
            let size = geometry.size
            let weights = LineWeights(scale: GameScene.boardScale(for: size))
            ZStack {
                model.skin.background.color.ignoresSafeArea()
                // One board for both screens: the player's game, or the demo behind the menu
                SpriteView(scene: model.scene, preferredFramesPerSecond: 120, options: [.ignoresSiblingOrder])
                    .accessibilityHidden(model.screen == .menu)
                layer(screens(size: size, weights: weights), size: size)
                SkinOverlay(skin: model.skin, flashCount: model.flashCount)
                if model.showingIntro {
                    layer(IntroView(model: model, target: menuLogo), size: size)
                        .transition(.identity)
                }
            }
            // Cross-fade the menu and the HUD while the bin glides between them
            .animation(.easeInOut(duration: 0.25), value: model.screen)
            .onPreferenceChange(MenuLogoFrame.self) { menuLogo = $0 }
            .tipViewStyle(SkinTipStyle(skin: model.skin, weights: weights))
            .tipBackground(model.skin.empty.color)
            .environment(\.touchModel, model)
            .onChange(of: GameScene.isLandscape(size), initial: true) { _, landscape in
                // The corner tip is about touch zones a TV doesn't have
                TipState.isLandscape = landscape && !isTV
            }
        }
    }

    @ViewBuilder
    private func screens(size: CGSize, weights: LineWeights) -> some View {
        switch model.screen {
        case .menu:
            // Knock the demo back so the menu reads over it
            model.skin.background.color.opacity(menuDim).ignoresSafeArea()
                .allowsHitTesting(false)
            if model.showingHowTo {
                HowToView(model: model, weights: weights)
            } else if model.showingConnect && !model.showingController {
                ConnectView(model: model, weights: weights)
                    .transition(.opacity)
            } else if !model.showingController {
                MenuView(model: model, weights: weights)
                    .transition(.opacity)
            }
            #if os(iOS)
            if model.showingController, #available(iOS 26.0, *) {
                ControllerPadView(model: model, weights: weights)
                    .transition(.opacity)
            }
            #endif
        case .playing:
            HUDView(model: model, weights: weights, landscape: GameScene.isLandscape(size),
                    bin: GameScene.binFrame(for: size, spinnerOnLeft: model.leftHanded))
                .transition(.opacity)
        case .lobby:
            LobbyView(model: model, weights: weights)
                .transition(.opacity)
        case .versus:
            VersusHUDView(model: model, weights: weights, size: size)
                .transition(.opacity)
        }
    }

    /// One layer over the board, in the coordinate space the menu logo and the intro share.
    private func layer(_ content: some View, size: CGSize) -> some View {
        ZStack { content }
            .coordinateSpace(name: Self.space)
            .frame(width: size.width, height: size.height)
    }
}

// MARK: - Shared pieces

/// A one-word uppercase label in the display font, lightly tracked.
struct TrackedLabel: View {
    let text: String
    let size: CGFloat
    let skin: Skin

    var body: some View {
        Text(text)
            .font(skin.font(.display, size))
            .tracking(pt(size) * labelTracking)
            .foregroundStyle(skin.ink.color)
    }
}

/// An outlined, sharp-cornered button face; the selected one takes the heavy weight.
struct ButtonFace<Content: View>: View {
    let skin: Skin
    let weights: LineWeights
    var selected = false
    var width = pt(220)
    var height = pt(52)
    @ViewBuilder let content: Content

    @Environment(\.buttonFill) private var fill

    var body: some View {
        content
            .frame(width: width, height: height)
            .background(skin.empty.color.opacity(fill))
            .overlay(Rectangle().strokeBorder(skin.ink.color, style: sharp(selected ? weights.heavy : weights.line)))
    }
}

extension EnvironmentValues {
    /// How solid button faces are; the menu lets the demo game show through a little.
    @Entry var buttonFill: Double = 1
    /// Told when a button is pressed by touch (see `TouchButtonStyle`).
    @Entry var touchModel: AppModel? = nil
}

/// Fades and lifts a menu element into place once the menu is revealed, staggered by `order`.
private struct Reveal: ViewModifier {
    let shown: Bool
    let order: Int

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : pt(14))
            .animation(.spring(duration: 0.32, bounce: 0.2).delay(shown ? Double(order) * 0.035 : 0), value: shown)
    }
}

extension View {
    fileprivate func reveal(_ shown: Bool, order: Int) -> some View {
        modifier(Reveal(shown: shown, order: order))
    }

    /// An unstyled button. On Apple TV it also never takes focus: the remote drives
    /// the menu through the model (the selected button takes the heavy outline), so
    /// the focus engine must find nothing to land on when the system has the remote.
    @ViewBuilder
    func plainButton() -> some View {
        #if os(tvOS)
        buttonStyle(BareButtonStyle()).disabled(true)
        #else
        buttonStyle(TouchButtonStyle())
        #endif
    }

    /// Point-to-select for a pointer, where there is one.
    @ViewBuilder
    func onHoverSelect(_ select: @escaping () -> Void) -> some View {
        #if os(tvOS)
        self
        #else
        onHover { hovering in if hovering { select() } }
        #endif
    }
}

#if os(tvOS)
/// Just the label: no focus lift, and no dimming while disabled.
private struct BareButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
    }
}
#else
/// A plain button that tells the model a finger (or pointer) pressed it, so the
/// hints switch back to touch. Controllers drive the menu through the model, never these.
private struct TouchButtonStyle: PrimitiveButtonStyle {
    @Environment(\.touchModel) private var model

    func makeBody(configuration: Configuration) -> some View {
        Button {
            model?.used(.touch)
            configuration.trigger()
        } label: {
            configuration.label
        }
        .buttonStyle(.plain)
    }
}
#endif

/// Tips in the skin: display-font title, one ink colour, a drawn close mark.
private struct SkinTipStyle: TipViewStyle {
    let skin: Skin
    let weights: LineWeights

    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .top, spacing: pt(12)) {
            VStack(alignment: .leading, spacing: pt(6)) {
                configuration.title?
                    .font(skin.font(.display, 15))
                    .foregroundStyle(skin.ink.color)
                configuration.message?
                    .font(skin.font(.text, 12))
                    .foregroundStyle(skin.ink.color(secondary))
                    .fixedSize(horizontal: false, vertical: true)
                ForEach(configuration.actions) { action in
                    Button(action: action.handler) {
                        action.label()
                            .font(skin.font(.display, 13))
                            .foregroundStyle(skin.ink.color)
                            .underline()
                    }
                    .plainButton()
                    .padding(.top, pt(4))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button { configuration.tip.invalidate(reason: .tipClosed) } label: {
                CloseMark().stroke(skin.ink.color, style: sharp(max(pt(1.5), weights.line)))
                    .frame(width: pt(10), height: pt(10))
                    .frame(width: pt(32), height: pt(32))
                    .contentShape(Rectangle())
            }
            .plainButton()
            .accessibilityLabel("Close tip")
        }
        .padding(.leading, pt(14))
        .padding(.vertical, pt(8))
        .frame(maxWidth: pt(340))
    }
}

/// An X, for closing a tip.
private struct CloseMark: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.move(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        return path
    }
}

/// An inline spot for tips: shows the first eligible one in an outlined box, or nothing.
private struct TipSlot: View {
    let skin: Skin
    let weights: LineWeights
    @State private var queue: TipQueue

    init(_ tips: [any Tip], skin: Skin, weights: LineWeights) {
        self.skin = skin
        self.weights = weights
        _queue = State(initialValue: TipQueue(tips))
    }

    var body: some View {
        ZStack {
            // Keeps the slot in the hierarchy (so the task runs) while no tip shows
            Color.clear.frame(width: 0, height: 0)
            if let tip = queue.current {
                Self.tipView(tip)
                    .id(tip.id)
                    .overlay(Rectangle().strokeBorder(skin.ink.color, style: sharp(weights.line)))
            }
        }
        .padding(.horizontal, pt(24))
        .task { await queue.watch() }
    }

    private static func tipView(_ tip: any Tip) -> AnyView {
        if #available(iOS 26, tvOS 26, *) { return AnyView(TipView(tip)) }
        return concreteTipView(tip)
    }

    /// Before iOS 26, TipView wants a concrete tip type, so open the existential.
    private static func concreteTipView<T: Tip>(_ tip: T) -> AnyView {
        AnyView(TipView(tip, arrowEdge: nil))
    }
}

extension View {
    /// A popover tip that works back to iOS 17, where the modifier wants a
    /// concrete, non-optional tip. None on Apple TV: a popover there needs
    /// focus to close, and the remote never gives the menu focus.
    @ViewBuilder
    fileprivate func skinPopoverTip<T: Tip>(_ tip: T?, arrowEdge: Edge,
                                            action: @escaping @MainActor @Sendable (Tips.Action) -> Void = { _ in }) -> some View {
        #if os(tvOS)
        self
        #else
        if #available(iOS 26, *) {
            popoverTip(tip, arrowEdge: arrowEdge, action: action)
        } else if let tip {
            popoverTip(tip, arrowEdge: arrowEdge, action: action)
        } else {
            self
        }
        #endif
    }
}

/// HEXGEN in ink on the menu bin's own lattice (laid over the bin, so its frame is
/// the bin's frame), built from the game's triangles. Each letter keeps one to
/// three of its triangles lit as pieces of the current skin (colour, mark,
/// outline), and keeps swapping which ones: a lit piece fades in, holds, fades
/// out, and another takes its turn. Hard-cut skins switch them without fading.
private struct LiveLogo: View {
    let skin: Skin
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Lit slots per letter. Slot 0 is always on, so a letter shows one to three pieces;
    /// each slot draws from its own third of the letter, so two never land on one triangle.
    private static let slots = 3
    private static let fadeTime = 0.35

    var body: some View {
        // Reduce Motion: a fixed handful stays lit
        TimelineView(.animation(minimumInterval: 1.0 / 60, paused: reduceMotion)) { timeline in
            let t = reduceMotion ? 0 : timeline.date.timeIntervalSinceReferenceDate
            Canvas { context, size in
                draw(&context, size: size, t: t)
            }
        }
    }

    /// What one slot shows at time `t`: which of its triangles, which colour, and how far in (0…1).
    private func slot(letter: Int, slot: Int, t: Double) -> (pick: UInt64, color: UInt64, amount: Double)? {
        let seed = UInt64(letter * Self.slots + slot)
        // Each piece holds about five seconds (a little more or less per slot, so they don't
        // all swap together). Slot 0 runs back to back; the others rest a while between pieces.
        let lit = 4.5 + unit(mix(seed, 1))
        let period = slot == 0 ? lit : lit + 2 + unit(mix(seed, 2)) * 3
        let shifted = t + unit(mix(seed, 3)) * period
        let cycle = (shifted / period).rounded(.down)
        let s = shifted - cycle * period
        guard s < lit else { return nil }
        let amount = skin.hardCuts ? 1 : min(1, s / Self.fadeTime, (lit - s) / Self.fadeTime)
        let n = UInt64(bitPattern: Int64(cycle))
        return (mix(seed, 10 &+ n), mix(seed, 20 &+ n), amount)
    }

    private func draw(_ context: inout GraphicsContext, size: CGSize, t: Double) {
        let layout = Marks.logoInBin(center: CGPoint(x: size.width / 2, y: size.height / 2),
                                     boardSide: size.height / CGFloat(2 * Grid.size))
        let weights = LineWeights(scale: layout.side)
        // Colours that would vanish against the ink sit out
        let ink = skin.ink
        let colors = skin.pieces.indices.filter { skin.pieces[$0].contrast(with: ink) >= 1.6 }

        // How lit each triangle is, keyed by its index in the layout
        var lit: [Int: (color: Int, amount: Double)] = [:]
        if !colors.isEmpty {
            let letters = Dictionary(grouping: layout.cells.indices, by: { layout.cells[$0].letter })
            for (letter, cells) in letters {
                for slot in 0..<Self.slots {
                    let choices = cells.enumerated().filter { $0.offset % Self.slots == slot }.map(\.element)
                    guard !choices.isEmpty, let shown = self.slot(letter: letter, slot: slot, t: t) else { continue }
                    let cell = choices[Int(shown.pick % UInt64(choices.count))]
                    lit[cell] = (colors[Int(shown.color % UInt64(colors.count))], shown.amount)
                }
            }
        }

        let plain = Path { path in
            for (i, cell) in layout.cells.enumerated() where lit[i] == nil {
                path.addPath(Path(Marks.polygon(Marks.scaled(cell.corners, by: 0.9))))
            }
        }
        context.fill(plain, with: .color(ink.color))

        let marks = Brand.tokens.marks
        for (i, state) in lit {
            let corners = Marks.scaled(layout.cells[i].corners, by: 0.9)
            let shape = Path(Marks.polygon(corners))
            // The ink triangle gives way as the piece grows into its place
            context.fill(shape, with: .color(ink.color(1 - state.amount)))
            let grown = Marks.scaled(corners, by: 0.8 + 0.2 * state.amount)
            var piece = context
            piece.opacity = state.amount
            let fill = skin.piece(state.color)
            piece.fill(Path(Marks.polygon(grown)), with: .color(fill.color))
            if let outline = skin.spec.stroke.outline, let outlineColor = skin.spec.stroke.outlineColor {
                piece.stroke(Path(Marks.polygon(grown)), with: .color(outlineColor.color),
                             style: sharp(outline == .heavy ? weights.heavy : weights.line))
            }
            if marks.indices.contains(state.color) {
                let mark = Marks.path(marks[state.color], corners: grown, lineWidth: weights.line,
                                      scale: CGFloat(skin.spec.stroke.markScale ?? 1))
                piece.fill(Path(mark), with: .color(skin.markColor(on: fill).color))
            }
        }
    }
}

/// A well-scrambled 64-bit value from two inputs (SplitMix64), so the logo's
/// pieces look random but are the same on every frame.
private func mix(_ a: UInt64, _ b: UInt64) -> UInt64 {
    var z = a &* 0x9E37_79B9_7F4A_7C15 &+ b &+ 0x6A09_E667_F3BC_C909
    z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
    z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
    return z ^ (z >> 31)
}

/// A hash as a number in 0..<1.
private func unit(_ hash: UInt64) -> Double { Double(hash >> 11) / Double(1 << 53) }

/// The HUD's progress by colour: a small hex for each colour, standing on a
/// corner like the dial. It fills a triangle, in that colour and with its mark,
/// for every hex of the colour cleared this game; past six it shows the count.
/// Colours not yet in play are faint outlines, so the row also shows what's to come.
private struct ColorHexes: View {
    let counts: [Int]
    let active: [Int]
    let skin: Skin
    /// Each hex's width (flat side to flat side).
    let side: CGFloat
    let columns: Int

    var body: some View {
        let colors = Array(counts.indices)
        let rows = stride(from: 0, to: colors.count, by: columns).map { Array(colors[$0..<min($0 + columns, colors.count)]) }
        VStack(spacing: side * 0.12) {
            ForEach(rows, id: \.self) { row in
                HStack(spacing: side * 0.14) {
                    ForEach(row, id: \.self) { color in
                        ColorHex(color: color, count: counts[color], inPlay: active.contains(color), skin: skin)
                            .frame(width: side, height: side * 2 / 3.0.squareRoot())
                    }
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(colors.filter { active.contains($0) }.map { "colour \($0 + 1): \(counts[$0]) hexes" }.joined(separator: ", "))
    }
}

/// One colour's hex for `ColorHexes` (and the callouts).
struct ColorHex: View {
    let color: Int
    let count: Int
    let inPlay: Bool
    let skin: Skin

    var body: some View {
        Canvas { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            // Pulled in a little so the outline's corners aren't clipped
            let radius = min(size.width / 3.0.squareRoot(), size.height / 2) / (1 + CGFloat(Brand.tokens.weights.line) * 0.6)
            func corner(_ degrees: Double) -> CGPoint {
                let a = degrees * .pi / 180
                return CGPoint(x: center.x + radius * cos(a), y: center.y - radius * sin(a))
            }
            let line = LineWeights(scale: radius)
            let fill = skin.piece(color)
            let marks = Brand.tokens.marks
            // Triangles fill clockwise from the top
            for k in 0..<6 {
                let mid = 60.0 - Double(k) * 60
                let triangle = Marks.scaled([center, corner(mid + 30), corner(mid - 30)], by: 0.86)
                let shape = Path(Marks.polygon(triangle))
                if inPlay && k < count {
                    context.fill(shape, with: .color(fill.color))
                    if marks.indices.contains(color) {
                        let mark = Marks.path(marks[color], corners: triangle, lineWidth: line.line,
                                              scale: CGFloat(skin.spec.stroke.markScale ?? 1))
                        context.fill(Path(mark), with: .color(skin.markColor(on: fill).color))
                    }
                } else if inPlay {
                    context.fill(shape, with: .color(skin.empty.color))
                }
            }
            let outline = Path(Marks.polygon((0..<6).map { corner(Double($0) * 60 + 30) }))
            // In play: ringed in its own colour; still to come: only a faint hairline
            if inPlay {
                context.stroke(outline, with: .color(fill.color), style: sharp(line.line))
            } else {
                context.stroke(outline, with: .color(skin.ink.color(0.14)), style: sharp(max(1, Brand.tokens.weights.hairline)))
            }
        }
        .overlay {
            if inPlay && count > 6 {
                Text("\(count)")
                    .font(skin.font(.digits, 10))
                    .foregroundStyle(skin.ink.color)
                    .padding(.horizontal, pt(3))
                    .background(skin.background.color.opacity(0.85))
            }
        }
    }
}

/// Skin effects that sit over everything: riso grain, crt scanlines, acid's hard-cut flash.
private struct SkinOverlay: View {
    let skin: Skin
    let flashCount: Int
    @State private var flashing = false

    private static let grain: UIImage = UIGraphicsImageRenderer(size: CGSize(width: 128, height: 128)).image { context in
        for x in 0..<128 {
            for y in 0..<128 {
                let white: CGFloat = Bool.random() ? 1 : 0
                context.cgContext.setFillColor(UIColor(white: white, alpha: .random(in: 0...1)).cgColor)
                context.cgContext.fill(CGRect(x: x, y: y, width: 1, height: 1))
            }
        }
    }

    var body: some View {
        ZStack {
            if let grain = skin.spec.effects.grain {
                Image(uiImage: Self.grain)
                    .resizable(resizingMode: .tile)
                    .opacity(grain)
            }
            if let scanlines = skin.spec.effects.scanlines {
                Canvas { context, size in
                    var y: CGFloat = 0
                    while y < size.height {
                        context.fill(Path(CGRect(x: 0, y: y, width: size.width, height: 1)), with: .color(.black.opacity(scanlines)))
                        y += 3
                    }
                }
            }
            if flashing {
                skin.ink.color
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .onChange(of: flashCount) {
            flashing = true
            Task {
                try? await Task.sleep(for: .milliseconds(50))
                flashing = false
            }
        }
    }
}

// MARK: - Menu

struct MenuView: View {
    let model: AppModel
    let weights: LineWeights
    /// The menu's popover tips, one at a time, most timely first.
    @State private var tips = TipQueue([GameCenterTip(), SkinTip(), SprintTip()])

    /// The logo shows once the bin has glided back from play (straight away at launch).
    @State private var logoShown = false

    var body: some View {
        GeometryReader { geometry in
            let bin = GameScene.binFrame(for: geometry.size, layout: .menu)
            ZStack(alignment: .topLeading) {
                logo
                    .frame(width: bin.width, height: bin.height)
                    .position(x: bin.midX, y: bin.midY)
                if GameScene.isLandscape(geometry.size) {
                    // The bin takes the left half; everything else stacks on the right
                    VStack(spacing: pt(10)) {
                        Spacer(minLength: pt(8))
                        buttons
                        // Hints only where there's room for them
                        ViewThatFits(in: .vertical) {
                            hints.reveal(shown, order: 7)
                            Color.clear.frame(height: 0)
                        }
                        TipSlot([CornerTip()], skin: model.skin, weights: weights)
                        Spacer(minLength: pt(8))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.leading, bin.maxX + pt(16))
                    .padding(.trailing, pt(16))
                } else {
                    // The bin sits at the top with the logo inside; the rest stacks below it
                    VStack(spacing: pt(10)) {
                        Spacer().frame(height: bin.maxY + pt(18))
                        buttons
                        Spacer(minLength: pt(8))
                        hints
                            .reveal(shown, order: 7)
                        Spacer().frame(height: pt(12))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, pt(16))
                }
            }
        }
        // The demo shows faintly through the buttons
        .environment(\.buttonFill, 0.82)
        .task { await tips.watch() }
        .onAppear {
            // At launch the intro hands its logo straight to this one; coming back
            // from a game, wait for the bin to glide home first
            if model.menuRevealed {
                withAnimation(.easeOut(duration: 0.25).delay(GameScene.glideTime * 0.8)) { logoShown = true }
            } else {
                logoShown = true
            }
        }
    }

    /// The live logo, laid over the menu bin; tapping it counts toward the hidden unlock.
    private var logo: some View {
        LiveLogo(skin: model.skin)
            .opacity(logoShown ? 1 : 0)
            .contentShape(Rectangle())
            .onTapGesture { model.logoTapped() }
            .accessibilityHidden(true)
            // The intro lands its logo on this one
            .background(GeometryReader { proxy in
                Color.clear.preference(key: MenuLogoFrame.self, value: proxy.frame(in: .named(RootView.space)))
            })
    }

    /// Whether the menu has built in; the intro reveals it as it fades.
    private var shown: Bool { model.menuRevealed }

    /// How wide every row of the menu runs, and the gap between tiles in a row.
    private static let rowWidth = pt(300)
    private static let gap = pt(8)

    @ViewBuilder private var buttons: some View {
        modeRow
        if let row = AppModel.versusRow {
            versusButton(selected: model.menuSelection == row)
                .reveal(shown, order: 4)
        }
        onlineButton(selected: model.menuSelection == AppModel.onlineRow)
            .reveal(shown, order: 4)
        settingsRow
            .padding(.top, pt(8))
            .reveal(shown, order: 5)
    }

    /// The solo modes side by side, each a drawn symbol over its name and best.
    private var modeRow: some View {
        let count = CGFloat(AppModel.modes.count)
        let width = (Self.rowWidth - Self.gap * (count - 1)) / count
        // One size for all three names: the largest the longest fits at, in this skin's font
        let room = width - Self.modeInset * 2
        let widest = AppModel.modes.map {
            model.skin.width(of: Brand.copy.mode($0).label, .display, Self.modeLabel, tracking: labelTracking)
        }.max() ?? 0
        let size = widest > room ? (Self.modeLabel * room / widest * 2).rounded(.down) / 2 : Self.modeLabel
        return HStack(spacing: Self.gap) {
            ForEach(Array(AppModel.modes.enumerated()), id: \.element) { index, mode in
                modeButton(mode, width: width, labelSize: size, selected: index == model.menuSelection)
                    .reveal(shown, order: 1 + index)
            }
        }
    }

    /// Skin, speed, connect, and how to play, side by side as symbol tiles.
    private var settingsRow: some View {
        let count = CGFloat(AppModel.connectRow == nil ? 3 : 4)
        // Together the tiles span the row
        let width = (Self.rowWidth - Self.gap * (count - 1)) / count
        return HStack(spacing: Self.gap) {
            skinTile(width: width)
            speedTile(width: width)
            if AppModel.connectRow != nil { connectTile(width: width) }
            howToTile(width: width)
        }
    }

    /// A square-ish tile: a symbol over a short label.
    private func tile(width: CGFloat, selected: Bool, label: String,
                      @ViewBuilder symbol: () -> some View) -> some View {
        let skin = model.skin
        return ButtonFace(skin: skin, weights: weights, selected: selected, width: width, height: pt(56)) {
            VStack(spacing: pt(5)) {
                symbol()
                    .font(.system(size: pt(20), weight: .regular))
                    .foregroundStyle(skin.ink.color)
                    .frame(height: pt(22))
                Text(label)
                    .font(skin.font(.display, 9))
                    .tracking(pt(9) * labelTracking)
                    .foregroundStyle(skin.ink.color)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            .padding(.horizontal, pt(4))
        }
    }

    /// A full-width button: a drawn symbol beside a name and a line about it.
    private func wideButton(selected: Bool, icon: MenuIcon.Kind, label: String, detail: String,
                            action: @escaping () -> Void) -> some View {
        let skin = model.skin
        return Button(action: action) {
            ButtonFace(skin: skin, weights: weights, selected: selected, width: Self.rowWidth, height: pt(52)) {
                HStack(spacing: pt(12)) {
                    MenuIcon(kind: icon, skin: skin)
                        .frame(width: pt(38), height: pt(26))
                    VStack(alignment: .leading, spacing: pt(3)) {
                        TrackedLabel(text: label, size: 15, skin: skin)
                        Text(detail)
                            .font(skin.font(.text, 10))
                            .foregroundStyle(skin.ink.color(secondary))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, pt(14))
            }
        }
        .plainButton()
    }

    /// Split-screen versus for 2–4 players (Apple TV).
    private func versusButton(selected: Bool) -> some View {
        let copy = Brand.copy.versus
        return wideButton(selected: selected, icon: .versus, label: copy.label, detail: copy.detail) {
            model.openLobby(joining: .keyboard)
        }
        .onHoverSelect { if let row = AppModel.versusRow { model.menuSelection = row } }
    }

    /// Co-op with a Game Center friend. Dimmed, saying why, when the player isn't
    /// signed in or their account doesn't allow multiplayer.
    private func onlineButton(selected: Bool) -> some View {
        let copy = Brand.copy.online
        let availability = model.onlineAvailability
        let detail = switch availability {
        case .available: copy.detail
        case .signedOut: copy.signedOut
        case .restricted: copy.restricted
        }
        return wideButton(selected: selected, icon: .online, label: copy.label, detail: detail) {
            model.openOnline(from: .keyboard)
        }
        .opacity(availability == .available ? 1 : 0.5)
        .accessibilityHint(availability == .available ? "" : detail)
        .onHoverSelect { model.menuSelection = AppModel.onlineRow }
    }

    /// The controls for whatever the player last used.
    private var hints: some View {
        VStack(spacing: pt(6)) {
            Text(Brand.copy.hint(for: model.inputKind))
            // Why online co-op just ended, until the next try
            if let notice = model.onlineNoticeText {
                Text(notice)
            }
            // Apple TV: the code a phone enters to play as a controller
            if let code = model.joinCode {
                Text(Brand.copy.controller.menuHint.replacingOccurrences(of: "%@", with: code))
            }
        }
        .font(model.skin.font(.text, 11))
        .foregroundStyle(model.skin.ink.color(secondary))
        .multilineTextAlignment(.center)
    }

    /// A mode name's size when it fits, and the clear space either side of it.
    private static let modeLabel: CGFloat = 13
    private static let modeInset = pt(9)

    private func modeButton(_ mode: Mode, width: CGFloat, labelSize: CGFloat, selected: Bool) -> some View {
        let skin = model.skin
        let text = Brand.copy.mode(mode)
        let best = model.scores.best(for: mode)
        return Button {
            model.start(mode)
        } label: {
            ButtonFace(skin: skin, weights: weights, selected: selected, width: width, height: pt(108)) {
                VStack(spacing: pt(4)) {
                    MenuIcon(kind: .mode(mode), skin: skin)
                        .frame(width: pt(60), height: pt(34))
                        .padding(.bottom, pt(4))
                    Text(text.label)
                        .font(skin.font(.display, labelSize))
                        .tracking(pt(labelSize) * labelTracking)
                        .foregroundStyle(skin.ink.color)
                        .lineLimit(1)
                        .fixedSize()
                    Text(text.detail)
                        .font(skin.font(.text, 9))
                        .foregroundStyle(skin.ink.color(secondary))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    // Held open before the first score, so the three tiles line up
                    Text(best > 0 ? "\(best)" : " ")
                        .font(skin.font(.digits, 10))
                        .foregroundStyle(skin.ink.color)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .skinPopoverTip(tips.isCurrent(GameCenterTip()) && TipState.bestMode == mode.rawValue && best > 0 ? GameCenterTip() : nil,
                                        arrowEdge: .bottom) { action in
                            if action.id == GameCenterTip.leaderboardAction { model.showLeaderboard(for: mode) }
                        }
                }
                .padding(.horizontal, Self.modeInset)
            }
        }
        .plainButton()
        .accessibilityLabel(text.label)
        .accessibilityValue(best > 0 ? "\(Brand.copy.best) \(best)" : "")
        .accessibilityHint(text.detail)
        .skinPopoverTip(tips.isCurrent(SprintTip()) && mode == .sprint ? SprintTip() : nil, arrowEdge: .bottom)
        .onHoverSelect { model.menuSelection = AppModel.modes.firstIndex(of: mode)! }
    }

    /// The current skin's name; the palette bounces as it changes.
    private func skinTile(width: CGFloat) -> some View {
        let skin = model.skin
        return Button {
            model.cycleSkin()
        } label: {
            tile(width: width, selected: model.menuSelection == AppModel.skinRow, label: skin.id.uppercased()) {
                Image(systemName: "paintpalette")
                    .symbolEffect(.bounce, value: skin.id)
            }
        }
        .plainButton()
        .accessibilityLabel(Brand.copy.skin)
        .accessibilityValue("\(skin.id), \(model.unlockedSkins.count) of \(Brand.tokens.skins.count) unlocked")
        .skinPopoverTip(tips.isCurrent(SkinTip()) ? SkinTip() : nil, arrowEdge: .top)
        .onHoverSelect { model.menuSelection = AppModel.skinRow }
    }

    /// The current speed; the gauge's needle swings to match.
    private func speedTile(width: CGFloat) -> some View {
        let copy = Brand.copy.speed
        let speed = model.speed
        let gauge = switch speed {
        case .slow: "gauge.with.dots.needle.0percent"
        case .normal: "gauge.with.dots.needle.50percent"
        case .fast: "gauge.with.dots.needle.100percent"
        }
        return Button {
            model.cycleSpeed()
        } label: {
            tile(width: width, selected: model.menuSelection == AppModel.speedRow,
                 label: copy.levels[speed.rawValue] ?? speed.rawValue) {
                Image(systemName: gauge)
                    .contentTransition(.symbolEffect(.replace))
            }
        }
        .plainButton()
        .accessibilityLabel(copy.label)
        .accessibilityValue(copy.levels[speed.rawValue] ?? speed.rawValue)
        .accessibilityHint(copy.hints[speed.rawValue] ?? "")
        .onHoverSelect { model.menuSelection = AppModel.speedRow }
    }

    /// Pair a gamepad, or use this phone as the controller for Hexgen on an Apple TV.
    /// The symbol fills in while a gamepad is connected.
    private func connectTile(width: CGFloat) -> some View {
        let copy = Brand.copy.controller
        return Button {
            model.showConnect()
        } label: {
            tile(width: width, selected: model.menuSelection == AppModel.connectRow, label: copy.short) {
                Image(systemName: model.controllerConnected ? "gamecontroller.fill" : "gamecontroller")
                    .contentTransition(.symbolEffect(.replace))
            }
        }
        .plainButton()
        .accessibilityLabel(copy.label)
        .accessibilityHint(copy.detail)
        .onHoverSelect { if let row = AppModel.connectRow { model.menuSelection = row } }
    }

    private func howToTile(width: CGFloat) -> some View {
        let copy = Brand.copy.howTo
        return Button {
            model.showHowTo()
        } label: {
            tile(width: width, selected: model.menuSelection == AppModel.howToRow, label: copy.short) {
                Image(systemName: "questionmark")
            }
        }
        .plainButton()
        .accessibilityLabel(copy.label)
        .accessibilityHint(copy.detail)
        .onHoverSelect { model.menuSelection = AppModel.howToRow }
    }
}

/// The menu's drawn symbols, in the board's own terms: pieces, hexes, and dials.
struct MenuIcon: View {
    enum Kind {
        case mode(Mode)
        case online
        case versus
    }

    let kind: Kind
    let skin: Skin

    private static let root3 = 3.0.squareRoot()

    var body: some View {
        Canvas { context, size in
            switch kind {
            case .mode(.main): spectrum(&context, size)
            case .mode(.endless): endless(&context, size)
            case .mode(.sprint): sprint(&context, size)
            case .online: pair(&context, size, split: false)
            case .versus: pair(&context, size, split: true)
            }
        }
        .accessibilityHidden(true)
    }

    // MARK: Shapes

    /// A hex standing on a corner, like a dial on the board, as its six corners.
    private static func corners(_ center: CGPoint, _ radius: CGFloat) -> [CGPoint] {
        (0..<6).map { k in
            let a = (30 + Double(k) * 60) * .pi / 180
            return CGPoint(x: center.x + radius * cos(a), y: center.y - radius * sin(a))
        }
    }

    /// The hex's six triangles, clockwise from the top, drawn apart like pieces.
    private static func triangles(_ center: CGPoint, _ radius: CGFloat) -> [[CGPoint]] {
        (0..<6).map { k in
            let mid = (60.0 - Double(k) * 60) * .pi / 180
            func corner(_ a: Double) -> CGPoint { CGPoint(x: center.x + radius * cos(a), y: center.y - radius * sin(a)) }
            return Marks.scaled([center, corner(mid + .pi / 6), corner(mid - .pi / 6)], by: 0.86)
        }
    }

    /// The largest radius that fits `across` hex widths and `down` hex heights in `size`,
    /// pulled in so the outline's corners aren't clipped.
    private static func radius(in size: CGSize, across: CGFloat = 1, down: CGFloat = 1) -> CGFloat {
        min(size.width / (root3 * across), size.height / (2 * down)) / (1 + CGFloat(Brand.tokens.weights.line) * 0.6)
    }

    private func outline(_ context: inout GraphicsContext, _ center: CGPoint, _ radius: CGFloat, _ color: Color) {
        let line = LineWeights(scale: radius)
        context.stroke(Path(Marks.polygon(Self.corners(center, radius))), with: .color(color), style: sharp(line.line))
    }

    /// A piece: its colour, and its mark on top.
    private func piece(_ context: inout GraphicsContext, _ triangle: [CGPoint], color: Int, radius: CGFloat, opacity: Double = 1) {
        let fill = skin.piece(color)
        context.fill(Path(Marks.polygon(triangle)), with: .color(fill.color(opacity)))
        let marks = Brand.tokens.marks
        guard marks.indices.contains(color) else { return }
        let mark = Marks.path(marks[color], corners: triangle, lineWidth: LineWeights(scale: radius).line,
                              scale: CGFloat(skin.spec.stroke.markScale ?? 1))
        context.fill(Path(mark), with: .color(skin.markColor(on: fill).color(opacity)))
    }

    // MARK: Symbols

    /// SPECTRUM: one hex of six different colours.
    private func spectrum(_ context: inout GraphicsContext, _ size: CGSize) {
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let r = Self.radius(in: size)
        for (k, triangle) in Self.triangles(center, r).enumerated() {
            piece(&context, triangle, color: k, radius: r)
        }
    }

    /// ENDLESS: a row of cleared hexes running on out of the frame, fading as they go.
    private func endless(_ context: inout GraphicsContext, _ size: CGSize) {
        let r = Self.radius(in: size, across: 2.75)
        let step = Self.root3 * r * 1.08
        let fades = [1.0, 0.5, 0.2]
        for (i, fade) in fades.enumerated() {
            let center = CGPoint(x: Self.root3 / 2 * r + CGFloat(i) * step, y: size.height / 2)
            for triangle in Self.triangles(center, r) {
                piece(&context, triangle, color: i, radius: r, opacity: fade)
            }
        }
    }

    /// SPRINT: a hex of one colour at speed, trailing lines behind it.
    private func sprint(_ context: inout GraphicsContext, _ size: CGSize) {
        let r = Self.radius(in: size)
        let center = CGPoint(x: size.width - Self.root3 / 2 * r * 1.06, y: size.height / 2)
        for triangle in Self.triangles(center, r) {
            piece(&context, triangle, color: 3, radius: r)
        }
        let line = LineWeights(scale: r).heavy
        let trail = center.x - Self.root3 / 2 * r - line * 1.5
        for (dy, length) in [(-0.5, 0.55), (0.0, 0.85), (0.5, 0.55)] as [(CGFloat, CGFloat)] {
            let y = center.y + dy * r
            let streak = Path { path in
                path.move(to: CGPoint(x: trail - length * r * 1.4, y: y))
                path.addLine(to: CGPoint(x: trail, y: y))
            }
            context.stroke(streak, with: .color(skin.ink.color), style: sharp(line))
        }
    }

    /// ONLINE and VERSUS: two dials side by side, one per player; versus splits them.
    private func pair(_ context: inout GraphicsContext, _ size: CGSize, split: Bool) {
        let r = Self.radius(in: size, across: 2.25)
        let apart = Self.root3 * r * 1.25
        let mid = CGPoint(x: size.width / 2, y: size.height / 2)
        for (i, dx) in [-apart / 2, apart / 2].enumerated() {
            let center = CGPoint(x: mid.x + dx, y: mid.y)
            for (k, triangle) in Self.triangles(center, r).enumerated() where k % 2 == i {
                piece(&context, triangle, color: i, radius: r)
            }
            outline(&context, center, r, skin.ink.color)
            let dot = r * 0.16
            context.fill(Path(ellipseIn: CGRect(x: center.x - dot, y: center.y - dot, width: dot * 2, height: dot * 2)),
                         with: .color(skin.ink.color))
        }
        if split {
            let line = Path { path in
                path.move(to: CGPoint(x: mid.x, y: mid.y - r))
                path.addLine(to: CGPoint(x: mid.x, y: mid.y + r))
            }
            context.stroke(line, with: .color(skin.ink.color(secondary)), style: sharp(LineWeights(scale: r).line))
        }
    }
}

// MARK: - How to play

/// The rules, over the menu's demo game, with the controls at the bottom.
struct HowToView: View {
    let model: AppModel
    let weights: LineWeights

    var body: some View {
        let skin = model.skin
        let copy = Brand.copy
        ZStack {
            skin.background.color.opacity(0.75).ignoresSafeArea()
            // A controller scrolls the page a line at a time (on Apple TV there's no other way)
            ScrollViewReader { scroller in
                ScrollView {
                    VStack(alignment: .leading, spacing: pt(18)) {
                        Text(copy.howTo.title)
                            .font(skin.font(.display, 32))
                            .foregroundStyle(skin.ink.color)
                            .accessibilityAddTraits(.isHeader)
                            .padding(.bottom, pt(6))
                        ForEach(Array(model.howToRules.enumerated()), id: \.element) { line, rule in
                            HStack(alignment: .top, spacing: pt(16)) {
                                HowToArt(art: rule.art, skin: skin)
                                VStack(alignment: .leading, spacing: pt(4)) {
                                    Text(rule.title)
                                        .font(skin.font(.display, 15))
                                        .foregroundStyle(skin.ink.color)
                                    Text(rule.body)
                                        .font(skin.font(.text, 13))
                                        .foregroundStyle(skin.ink.color(secondary))
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .accessibilityElement(children: .combine)
                            .id(line)
                        }
                        Text(copy.hint(for: model.inputKind))
                        .font(skin.font(.text, 11))
                        .foregroundStyle(skin.ink.color(secondary))
                        .padding(.top, pt(6))
                        Button { model.hideHowTo() } label: {
                            ButtonFace(skin: skin, weights: weights, selected: true, width: pt(160), height: pt(44)) {
                                TrackedLabel(text: copy.howTo.back, size: 15, skin: skin)
                            }
                        }
                        .plainButton()
                        .frame(maxWidth: .infinity)
                        .padding(.top, pt(12))
                        .id(model.howToRules.count)
                    }
                    .frame(maxWidth: pt(420), alignment: .leading)
                    .padding(.horizontal, pt(28))
                    .padding(.vertical, pt(40))
                    .frame(maxWidth: .infinity)
                }
                .scrollIndicators(.hidden)
                .onChange(of: model.howToLine) { _, line in
                    withAnimation(.easeOut(duration: 0.2)) { scroller.scrollTo(line, anchor: .center) }
                }
            }
        }
    }
}

// MARK: - In-game overlay

struct HUDView: View {
    let model: AppModel
    let weights: LineWeights
    var landscape = false
    /// The bin's bounding box in this view, for lining the landscape rotate buttons up against it.
    var bin: CGRect = .zero

    var body: some View {
        let hud = model.hud
        ZStack {
            Group {
                if landscape {
                    sideColumns(hud)
                } else {
                    portraitHUD(hud)
                }
            }
            .padding(pt(20))

            if hud.phase == .playing && !isTV { landscape ? AnyView(rotateZones) : AnyView(portraitSpinner) }

            switch hud.phase {
            case .paused: pauseOverlay
            case .gameOver: gameOverOverlay(hud)
            case .playing: EmptyView()
            }
        }
    }

    private var skin: Skin { model.skin }

    /// Portrait, in order of weight: the board and the dial carry the screen; the
    /// score is the one big number, in the pocket under the bin away from the dial,
    /// with the colour progress beneath it; the mode and pause sit quietly in the top
    /// corners beside the bin's top, and any walkthrough or callout line between them.
    /// The stats take the side the spinner leaves free, so they swap with the hand.
    private func portraitHUD(_ hud: HUDState) -> some View {
        let statsLeft = isTV || !model.leftHanded
        let edge: HorizontalAlignment = statsLeft ? .leading : .trailing
        let corner: Alignment = statsLeft ? .leading : .trailing
        return GeometryReader { geometry in
            // The stats share the dial's baseline (this view sits inside the HUD's padding)
            let padding = pt(20)
            let full = CGSize(width: geometry.size.width + 2 * padding, height: geometry.size.height + 2 * padding)
            #if os(iOS)
            let play = GameScene.portraitPlay(for: full, spinnerOnLeft: model.leftHanded)
            // The stats hold the unlifted pair's baseline; the bin and dial sit higher
            let resting = GameScene.portraitPlay(for: full, spinnerOnLeft: model.leftHanded, lift: 0)
            let baseline = max(0, full.height - resting.spinner.maxY - padding)
            // The top line may come down to just short of the bin's top corner, and no further
            let headroom = max(0, play.bin.minY - padding - pt(8))
            #else
            let baseline: CGFloat = 0
            let headroom = CGFloat.infinity
            #endif
            VStack(spacing: 0) {
                ZStack(alignment: .top) {
                    HStack(alignment: .top) {
                        if statsLeft { quietMode(hud, alignment: .leading) } else { portraitPause(hud) }
                        Spacer()
                        if statsLeft { portraitPause(hud) } else { quietMode(hud, alignment: .trailing) }
                    }
                    // Centred between the corners, clear of both (the widest mode label, and pause)
                    VStack(spacing: pt(6)) {
                        guideBanner(hud, alignment: .center, spaced: false)
                        calloutLine(hud, alignment: .center)
                    }
                    .padding(.horizontal, pt(84))
                    .frame(maxWidth: .infinity, maxHeight: headroom, alignment: .top)
                    .allowsHitTesting(false)
                }
                Spacer(minLength: 0)
                VStack(alignment: edge, spacing: pt(10)) {
                    Text("\(hud.score)")
                        .font(skin.font(.digits, 44))
                        .foregroundStyle(skin.ink.color)
                    colorHexes(hud, columns: 4, side: pt(28))
                }
                // No wider than the pocket beside the dial
                .frame(maxWidth: geometry.size.width * 0.45, alignment: corner)
                .frame(maxWidth: .infinity, alignment: corner)
                .padding(.bottom, baseline)
                .allowsHitTesting(false)
            }
        }
    }

    /// The mode (and a sprint's clock), small and quiet: it rarely changes mid-game.
    private func quietMode(_ hud: HUDState, alignment: HorizontalAlignment) -> some View {
        modeLabel(hud, alignment: alignment)
            .opacity(secondary)
            .allowsHitTesting(false)
    }

    @ViewBuilder private func portraitPause(_ hud: HUDState) -> some View {
        if hud.phase == .playing && !isTV { pauseButton }
    }

    /// Landscape: the board takes the middle and the stats run down either side.
    private func sideColumns(_ hud: HUDState) -> some View {
        // The colours go in the stats column, the one the spinner (iPhone) leaves free
        let coloursLeft = isTV || !model.leftHanded
        return HStack {
            VStack(alignment: .leading, spacing: pt(8)) {
                scoreText(hud)
                modeLabel(hud, alignment: .leading)
                guideBanner(hud, alignment: .leading)
                if coloursLeft { colorHexes(hud, columns: 4, side: pt(22)).padding(.top, pt(4)) }
                calloutLine(hud, alignment: .leading)
                    .frame(maxWidth: pt(isTV ? 140 : 120), alignment: .leading)
                    .padding(.top, pt(4))
                Spacer()
            }
            .allowsHitTesting(false)
            Spacer()
            VStack(alignment: .trailing, spacing: pt(12)) {
                if hud.phase == .playing && !isTV { pauseButton }
                if !coloursLeft { colorHexes(hud, columns: 4, side: pt(22)).allowsHitTesting(false) }
                Spacer()
            }
        }
    }

    /// Landscape: the dial itself, as on the phone controller, in the wide column
    /// beside the bin (right, or left for the left-handed), close against the bin
    /// and below the stats: it shows the six pieces under the dial, and turns as
    /// it's spun (either way) or tapped (forward). The board moves the dial.
    @ViewBuilder private var rotateZones: some View {
        #if os(iOS)
        GeometryReader { geometry in
            let gap = pt(14) // never reach into the bin
            let onLeft = model.leftHanded
            let top = bin.midY - bin.height * 0.1
            let column = onLeft ? bin.minX : geometry.size.width - bin.maxX
            let side = max(0, min(column - 2 * gap, geometry.size.height - top - gap))
            DialSpinner(skin: skin, weights: weights, dial: model.hud.dial) { model.rotate($0, from: .corner) }
                .frame(width: side, height: side)
                .position(x: onLeft ? bin.minX - gap - side / 2 : bin.maxX + gap + side / 2,
                          y: top + (geometry.size.height - top - gap) / 2)
        }
        #endif
    }

    /// Portrait: the dial beside the bin's lower corner, on the player's hand side,
    /// placed where `GameScene.portraitPlay` keeps room for it.
    @ViewBuilder private var portraitSpinner: some View {
        #if os(iOS)
        GeometryReader { geometry in
            let frame = GameScene.portraitPlay(for: geometry.size, spinnerOnLeft: model.leftHanded).spinner
            // The spinner pulls its drawing in to keep its outline whole; give it that back
            let side = frame.height * (1 + CGFloat(Brand.tokens.weights.line) * 0.6)
            DialSpinner(skin: skin, weights: weights, dial: model.hud.dial) { model.rotate($0, from: .corner) }
                .frame(width: side, height: side)
                .position(x: frame.midX, y: frame.midY)
        }
        #endif
    }

    /// The first game's walkthrough: what the bot is showing and how to take over,
    /// then "your turn" once it has handed the game over. With little height to
    /// spare, the watch line goes before the take-over line would crowd the bin.
    /// `spaced` sets it off from the stats above it.
    @ViewBuilder private func guideBanner(_ hud: HUDState, alignment: HorizontalAlignment, spaced: Bool = true) -> some View {
        let copy = Brand.copy.walkthrough
        if hud.phase == .playing, let stage = hud.guide {
            let textAlignment: TextAlignment = alignment == .leading ? .leading : .center
            let takeOver = Text(Brand.copy.fill(copy.takeOver, for: model.inputKind))
                .font(skin.font(.text, 12))
                .foregroundStyle(skin.ink.color(secondary))
            Group {
                switch stage {
                case .watching:
                    ViewThatFits(in: .vertical) {
                        VStack(alignment: alignment, spacing: pt(4)) {
                            Text(copy.watch)
                                .font(skin.font(.text, 15))
                                .foregroundStyle(skin.ink.color)
                            takeOver
                        }
                        takeOver
                    }
                case .yourTurn:
                    Text(copy.yourTurn)
                        .font(skin.font(.display, 22))
                        .foregroundStyle(skin.ink.color)
                }
            }
            .multilineTextAlignment(textAlignment)
            .padding(.top, spaced ? pt(10) : 0)
            .transition(.opacity)
            .allowsHitTesting(false)
            .accessibilityElement(children: .combine)
        }
    }

    /// What just shifted in play, faded in and out beside the bin. Reserves no
    /// room when empty, so the stats don't shuffle as callouts come and go.
    @ViewBuilder private func calloutLine(_ hud: HUDState, alignment: HorizontalAlignment) -> some View {
        ZStack {
            if let callout = hud.callout {
                CalloutView(callout: callout, skin: skin, alignment: alignment)
                    .id(callout.id)
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.25), value: hud.callout?.id)
        .allowsHitTesting(false)
    }

    /// Fixed-width digits, so the score doesn't jitter as it climbs.
    private func scoreText(_ hud: HUDState) -> some View {
        Text("\(hud.score)")
            .font(skin.font(.digits, 24))
            .foregroundStyle(skin.ink.color)
    }

    private func modeLabel(_ hud: HUDState, alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: pt(4)) {
            TrackedLabel(text: Brand.copy.mode(hud.mode).label, size: 13, skin: skin)
            if let seconds = hud.sprintSeconds {
                Text(String(format: "%d:%02d", seconds / 60, seconds % 60))
                    .font(skin.font(.digits, 18))
                    .foregroundStyle(skin.ink.color)
            }
        }
    }

    private func colorHexes(_ hud: HUDState, columns: Int, side: CGFloat) -> some View {
        ColorHexes(counts: hud.colorHexes, active: hud.activeColors, skin: skin, side: side, columns: columns)
    }

    private var pauseButton: some View {
        Button { model.togglePause() } label: {
            // Two bars, at the line weight
            HStack(spacing: pt(6)) {
                Rectangle().frame(width: max(pt(2), weights.line), height: pt(16))
                Rectangle().frame(width: max(pt(2), weights.line), height: pt(16))
            }
            .foregroundStyle(skin.ink.color(secondary))
            .frame(width: pt(44), height: pt(44))
            .contentShape(Rectangle())
        }
        .accessibilityLabel("Pause")
    }

    private func dim(_ opacity: Double) -> some View {
        skin.background.color.opacity(opacity).ignoresSafeArea()
    }

    private var pauseOverlay: some View {
        ZStack {
            dim(0.75)
            VStack(spacing: pt(24)) {
                Text(Brand.copy.paused).font(skin.font(.display, 32)).foregroundStyle(skin.ink.color)
                overlayButton(Brand.copy.resume) { model.togglePause() }
                overlayButton(Brand.copy.menu) { model.toMenu() }
                // Which side the landscape spinner sits on; tapping swaps it
                if !isTV {
                    overlayButton(model.leftHanded ? Brand.copy.leftHanded : Brand.copy.rightHanded) { model.toggleHand() }
                }
                // What just fired comes first; then this session's lesson; then controls
                TipSlot([TwistTip(), GlowTip(), CornerTip(), ControlsTip()],
                        skin: skin, weights: weights)
                    .padding(.top, pt(8))
            }
        }
    }

    private func gameOverOverlay(_ hud: HUDState) -> some View {
        let copy = Brand.copy
        let headline = hud.won ? copy.cleared : hud.sprintSeconds == 0 ? copy.timeUp : copy.binFull
        return ZStack {
            dim(0.88)
            VStack(spacing: pt(16)) {
                Text(headline).font(skin.font(.display, 36)).foregroundStyle(skin.ink.color)
                Text("\(hud.score)").font(skin.font(.digits, 28)).foregroundStyle(skin.ink.color)
                if hud.isNewHighScore {
                    Text(copy.newBest).font(skin.font(.text, 16)).foregroundStyle(skin.ink.color)
                }
                ForEach(hud.unlocked, id: \.self) { id in
                    Text(copy.unlocked(id)).font(skin.font(.text, 16)).foregroundStyle(skin.ink.color)
                }
                overlayButton(copy.menu) { model.toMenu() }.padding(.top, pt(16))
                // Learn from losing: the lesson this run could have used
                TipSlot([HoldTip(), TwistTip(), GlowTip(), CombosTip()],
                        skin: skin, weights: weights)
                    .padding(.top, pt(8))
            }
        }
    }

    private func overlayButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            ButtonFace(skin: skin, weights: weights, width: pt(160), height: pt(44)) {
                TrackedLabel(text: title, size: 15, skin: skin)
            }
        }
        .plainButton()
    }
}
