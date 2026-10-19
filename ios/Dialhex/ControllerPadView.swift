// ControllerPadView.swift — The iPhone as a controller for Hexgen on Apple TV
//
// Pick a TV, type the code it shows, then play with two controls drawn like
// the game: the bin in miniature, where a finger puts the dial (the TV echoes
// it), and the dial itself, a hex of the six pieces under it on the TV, that
// turns as you spin it. A, B, and pause sit small beneath. Drawn in the
// current skin like the rest of the app.

#if os(iOS)
import DialhexCore
import Network
import SwiftUI

@available(iOS 26.0, *)
struct ControllerPadView: View {
    let model: AppModel
    let weights: LineWeights
    @State private var controller = PhoneController()
    /// The TV picked from the list, waiting for its code.
    @State private var chosen: Bonjour.Endpoint?
    @State private var code = ""

    var body: some View {
        let skin = model.skin
        let copy = Brand.copy.controller
        ZStack {
            skin.background.color.ignoresSafeArea()
            VStack(spacing: 16) {
                HStack {
                    Text(copy.title)
                        .font(skin.font(.display, 28))
                        .foregroundStyle(skin.ink.color)
                        .accessibilityAddTraits(.isHeader)
                    Spacer()
                    Button {
                        controller.stop()
                        model.showingController = false
                    } label: {
                        ButtonFace(skin: skin, weights: weights, width: 100, height: 40) {
                            TrackedLabel(text: copy.leave, size: 13, skin: skin)
                        }
                    }
                    .plainButton()
                }
                switch controller.status {
                case .joined(let player):
                    pad(player)
                case .connecting:
                    Spacer()
                    status(copy.connecting)
                    Spacer()
                case .searching, .lost, .rejected:
                    if case .lost = controller.status { status(copy.lost) }
                    if case .rejected(let rejection) = controller.status {
                        status(copy.rejected.replacingOccurrences(of: "%@", with: reason(rejection)))
                    }
                    if let chosen {
                        codeEntry(for: chosen)
                    } else {
                        tvList
                    }
                }
            }
            .padding(20)
        }
        .onAppear { controller.startBrowsing() }
        .onDisappear { controller.stop() }
    }

    // MARK: - Finding a TV

    private var tvList: some View {
        let skin = model.skin
        return VStack(spacing: 12) {
            status(Brand.copy.controller.searching)
            ForEach(controller.tvs) { tv in
                Button {
                    chosen = tv
                    code = ""
                } label: {
                    ButtonFace(skin: skin, weights: weights, width: 260, height: 52) {
                        TrackedLabel(text: tv.name, size: 15, skin: skin)
                    }
                }
                .plainButton()
            }
            Spacer()
        }
    }

    /// Four digits on a keypad; the fourth connects.
    private func codeEntry(for tv: Bonjour.Endpoint) -> some View {
        let skin = model.skin
        let keys = ["1", "2", "3", "4", "5", "6", "7", "8", "9", "", "0", Self.deleteKey]
        return VStack(spacing: 14) {
            status(Brand.copy.controller.codePrompt)
            Text(tv.name).font(skin.font(.text, 13)).foregroundStyle(skin.ink.color(secondary))
            Text(String(code.padding(toLength: ControllerProtocol.joinCodeLength, withPad: "·", startingAt: 0)))
                .font(skin.font(.digits, 36))
                .tracking(10)
                .foregroundStyle(skin.ink.color)
                .accessibilityLabel(code.isEmpty ? "No digits yet" : "Code \(code)")
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(76), spacing: 10), count: 3), spacing: 10) {
                ForEach(Array(keys.enumerated()), id: \.offset) { _, key in
                    if key.isEmpty {
                        Color.clear.frame(width: 76, height: 56)
                    } else {
                        Button { press(key, tv: tv) } label: {
                            ButtonFace(skin: skin, weights: weights, width: 76, height: 56) {
                                if key == Self.deleteKey {
                                    TrackedLabel(text: key, size: 13, skin: skin)
                                } else {
                                    Text(key).font(skin.font(.digits, 22)).foregroundStyle(skin.ink.color)
                                }
                            }
                        }
                        .plainButton()
                        .accessibilityLabel(key == Self.deleteKey ? "Delete" : key)
                    }
                }
            }
            Spacer()
        }
    }

    private static let deleteKey = "DEL"

    private func press(_ key: String, tv: Bonjour.Endpoint) {
        if key == Self.deleteKey {
            if code.isEmpty { chosen = nil } else { code.removeLast() }
            return
        }
        guard code.count < ControllerProtocol.joinCodeLength else { return }
        code += key
        if code.count == ControllerProtocol.joinCodeLength {
            controller.connect(to: tv, code: code)
            chosen = nil
        }
    }

    // MARK: - Playing

    /// The mini bin and the spinning dial, side by side when the phone is turned
    /// sideways, stacked when it's upright; A, B, and pause sit small beneath.
    private func pad(_ player: PlayerID) -> some View {
        let skin = model.skin
        return VStack(spacing: 12) {
            HStack(spacing: 8) {
                Rectangle().fill(model.playerColor(player).color).frame(width: 14, height: 14)
                TrackedLabel(text: player.description, size: 22, skin: skin)
                Spacer()
                Text(screenText).font(skin.font(.text, 13)).foregroundStyle(skin.ink.color(secondary))
            }
            if steersMenu {
                // On the TV's menu (and the versus lobby) the dial becomes a pad of arrows
                MenuDial(skin: skin, weights: weights) { controller.nudge($0) } choose: { controller.send(.confirm) }
                    .aspectRatio(1, contentMode: .fit)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                GeometryReader { geometry in
                    let frames = Self.pair(in: geometry.size)
                    ZStack {
                        DialSpinner(skin: skin, weights: weights, dial: controller.dial) { controller.rotate($0) }
                            .frame(width: frames.dial.width, height: frames.dial.height)
                            .position(x: frames.dial.midX, y: frames.dial.midY)
                        BoardPad(skin: skin, weights: weights, vertex: controller.dial.vertex) { controller.place($0) }
                            .frame(width: frames.bin.width, height: frames.bin.height)
                            .position(x: frames.bin.midX, y: frames.bin.midY)
                    }
                }
            }
            HStack(spacing: 14) {
                button(label: "Confirm") { TrackedLabel(text: "A", size: 15, skin: skin) } action: { controller.send(.confirm) }
                button(label: "Back") { TrackedLabel(text: "B", size: 15, skin: skin) } action: { controller.send(.cancel) }
                button(label: "Pause") { PauseBars(skin: skin, weights: weights) } action: { controller.send(.pause) }
            }
            .foregroundStyle(skin.ink.color)
        }
    }

    /// How much bigger the mini bin is than the dial, and the gap between their
    /// facing edges, both in dial radii.
    private static let binSize: CGFloat = 1.2
    private static let gap: CGFloat = 0.12

    /// The dial and the mini bin as neighbouring hexes, sized to fill `size`. The bin
    /// sits off one of the dial's sides, so an edge of each runs parallel to the
    /// other a small gap apart, as cells do in a honeycomb: below and to the right
    /// when the phone is upright, to the left when it's sideways.
    private static func pair(in size: CGSize) -> (dial: CGRect, bin: CGRect) {
        let root3 = 3.0.squareRoot()
        // In dial radii, with the dial at the origin; both stand on a corner, so a
        // side's normal points 0°, ±60°, … and the apothem is √3/2 of the radius
        let r2 = binSize
        let apart = root3 / 2 + r2 * root3 / 2 + gap
        let wide = size.width > size.height
        let toward = wide ? CGPoint(x: -1, y: 0) : CGPoint(x: 0.5, y: root3 / 2)
        let bin = CGPoint(x: toward.x * apart, y: toward.y * apart)
        let minX = min(-root3 / 2, bin.x - r2 * root3 / 2), maxX = max(root3 / 2, bin.x + r2 * root3 / 2)
        let minY = min(-1, bin.y - r2), maxY = max(1, bin.y + r2)
        let fit = min(size.width / (maxX - minX), size.height / (maxY - minY))
        // Centre the pair, then lay each hex's square frame around its centre
        let origin = CGPoint(x: (size.width - (maxX - minX) * fit) / 2 - minX * fit,
                             y: (size.height - (maxY - minY) * fit) / 2 - minY * fit)
        func frame(_ center: CGPoint, radius: CGFloat, slack: CGFloat) -> CGRect {
            let side = 2 * radius * fit * slack
            return CGRect(x: origin.x + center.x * fit - side / 2, y: origin.y + center.y * fit - side / 2, width: side, height: side)
        }
        // The frames carry the slack each control takes back to keep its outline whole
        return (frame(.zero, radius: 1, slack: 1 + CGFloat(Brand.tokens.weights.line) * 0.6),
                frame(bin, radius: r2, slack: 1 / 0.97))
    }

    /// The TV is on its menu or the versus lobby, where the phone moves a selection.
    private var steersMenu: Bool {
        controller.screen == .menu || controller.screen == .lobby
    }

    private var screenText: String {
        let copy = Brand.copy.controller
        switch controller.screen {
        case .menu: return ""
        case .lobby: return copy.waiting
        case .playing: return ""
        case .paused: return copy.paused
        case .over(let won): return won ? copy.won : copy.over
        }
    }

    private func button(label: String, @ViewBuilder face: () -> some View, action: @escaping () -> Void) -> some View {
        let skin = model.skin
        return Button(action: action) {
            ButtonFace(skin: skin, weights: weights, width: 72, height: 44) { face() }
        }
        .plainButton()
        .accessibilityLabel(label)
    }

    // MARK: - Status

    private func status(_ text: String) -> some View {
        Text(text)
            .font(model.skin.font(.text, 13))
            .foregroundStyle(model.skin.ink.color(secondary))
            .multilineTextAlignment(.center)
    }

    private func reason(_ rejection: Rejection) -> String {
        switch rejection {
        case .wrongVersion: return "update Hexgen on both"
        case .wrongCode: return "wrong code"
        case .full: return "four players already"
        case .matchRunning: return "a match is on"
        }
    }
}

#endif
