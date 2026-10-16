// DialhexApp.swift — App entry and the SwiftUI screens around the SpriteKit board

import DialhexCore
import SpriteKit
import SwiftUI

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
        }
    }
}

extension Color {
    init(rgb: UInt32, opacity: Double = 1) {
        self.init(.sRGB,
                  red: Double((rgb >> 16) & 0xFF) / 255,
                  green: Double((rgb >> 8) & 0xFF) / 255,
                  blue: Double(rgb & 0xFF) / 255,
                  opacity: opacity)
    }
}

extension Font {
    static func mono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}

struct RootView: View {
    let model: AppModel

    var body: some View {
        ZStack {
            Color(rgb: Palette.background).ignoresSafeArea()
            switch model.screen {
            case .menu:
                MenuView(model: model)
            case .playing:
                SpriteView(scene: model.scene, preferredFramesPerSecond: 120, options: [.ignoresSiblingOrder])
                HUDView(model: model)
            }
        }
    }
}

// MARK: - Menu

struct MenuView: View {
    let model: AppModel

    private static let descriptions: [Mode: (label: String, detail: String)] = [
        .main: ("MAIN", "Clear all 8 colors"),
        .endless: ("ENDLESS", "Play forever"),
        .sprint: ("SPRINT", "3 minutes, max score"),
    ]

    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            Text("DIALHEX")
                .font(.mono(48, weight: .bold))
                .foregroundStyle(.white)
            Text("a hexagonal puzzle")
                .font(.mono(14))
                .foregroundStyle(.white.opacity(0.4))
            Spacer().frame(height: 24)

            ForEach(Array(AppModel.modes.enumerated()), id: \.element) { index, mode in
                modeButton(mode, selected: index == model.menuSelection)
            }

            Spacer()
            VStack(spacing: 6) {
                Text(model.controllerConnected
                     ? "d-pad move · A/Y/R turn · X/L turn back · ≡ pause"
                     : "tap a spot to grab it, tap again to turn")
                Text("keys: WASD move · Q/E turn · 1/2/3 start")
            }
            .font(.mono(11))
            .foregroundStyle(.white.opacity(0.3))
            Spacer().frame(height: 24)
        }
        .padding(.horizontal, 16)
    }

    private func modeButton(_ mode: Mode, selected: Bool) -> some View {
        let text = Self.descriptions[mode]!
        let best = model.highScores.best(for: mode)
        return Button {
            model.start(mode)
        } label: {
            VStack(spacing: 4) {
                Text(text.label).font(.mono(18, weight: .bold)).foregroundStyle(.white)
                Text(text.detail).font(.mono(10)).foregroundStyle(.white.opacity(0.5))
            }
            .frame(width: 200, height: 50)
            .background(.white.opacity(selected ? 0.15 : 0.05))
            .overlay(alignment: .topTrailing) {
                if best > 0 {
                    Text("best: \(best)")
                        .font(.mono(10))
                        .foregroundStyle(Color(rgb: 0xFFD700))
                        .padding(.top, 6)
                        .padding(.trailing, 8)
                }
            }
            .overlay(Rectangle().stroke(.white.opacity(selected ? 0.6 : 0.2), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .onHover { hovering in if hovering { model.menuSelection = AppModel.modes.firstIndex(of: mode)! } }
    }
}

// MARK: - In-game overlay

struct HUDView: View {
    let model: AppModel

    var body: some View {
        let hud = model.hud
        ZStack {
            VStack {
                topBar(hud)
                Spacer()
                if hud.phase == .playing { rotateButtons }
            }
            .padding(20)

            switch hud.phase {
            case .paused: pauseOverlay
            case .gameOver: gameOverOverlay(hud)
            case .playing: EmptyView()
            }
        }
    }

    private func topBar(_ hud: HUDState) -> some View {
        HStack(alignment: .top) {
            Text("\(hud.score)")
                .font(.mono(24, weight: .bold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, alignment: .leading)

            VStack(spacing: 4) {
                Text(hud.mode.rawValue.uppercased())
                    .font(.mono(14))
                    .foregroundStyle(.white.opacity(0.5))
                if let seconds = hud.sprintSeconds {
                    Text(String(format: "%d:%02d", seconds / 60, seconds % 60))
                        .font(.mono(18, weight: .bold))
                        .foregroundStyle(seconds <= 30 ? Color(rgb: 0xF44336) : .white)
                        .monospacedDigit()
                }
            }

            VStack(alignment: .trailing, spacing: 8) {
                HStack(spacing: 4) {
                    ForEach(hud.activeColors, id: \.self) { color in
                        Circle()
                            .fill(Color(rgb: Palette.colors[color]))
                            .overlay(Circle().stroke(.white.opacity(0.3), lineWidth: 1))
                            .frame(width: 16, height: 16)
                    }
                }
                Text("hexes: \(hud.hexesCleared)")
                    .font(.mono(12))
                    .foregroundStyle(.white.opacity(0.4))
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        // Taps on the HUD text fall through to the board
        .allowsHitTesting(false)
    }

    private var rotateButtons: some View {
        HStack {
            rotateButton("arrow.counterclockwise", .counterClockwise)
            Spacer()
            Button { model.togglePause() } label: {
                Image(systemName: "pause.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(.white.opacity(0.4))
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("Pause")
            Spacer()
            rotateButton("arrow.clockwise", .clockwise)
        }
    }

    private func rotateButton(_ symbol: String, _ direction: RotationDirection) -> some View {
        Button { model.rotate(direction) } label: {
            Image(systemName: symbol)
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(.white.opacity(0.6))
                .frame(width: 64, height: 64)
                .background(Circle().fill(.white.opacity(0.1)))
                .overlay(Circle().stroke(.white.opacity(0.3), lineWidth: 2))
        }
        .accessibilityLabel(direction == .clockwise ? "Turn clockwise" : "Turn counter-clockwise")
    }

    private var pauseOverlay: some View {
        ZStack {
            Color.black.opacity(0.5).ignoresSafeArea()
            VStack(spacing: 24) {
                Text("PAUSED").font(.mono(32, weight: .bold)).foregroundStyle(.white)
                overlayButton("RESUME") { model.togglePause() }
                overlayButton("MENU") { model.toMenu() }
            }
        }
    }

    private func gameOverOverlay(_ hud: HUDState) -> some View {
        ZStack {
            Color.black.opacity(0.7).ignoresSafeArea()
            VStack(spacing: 16) {
                Text(hud.won ? "YOU WIN" : "GAME OVER").font(.mono(36, weight: .bold)).foregroundStyle(.white)
                Text("\(hud.score)").font(.mono(28, weight: .bold)).foregroundStyle(Color(rgb: 0xFFD700))
                if hud.isNewHighScore {
                    Text("NEW HIGH SCORE!").font(.mono(16)).foregroundStyle(Color(rgb: 0xFFD700))
                }
                overlayButton("MENU") { model.toMenu() }.padding(.top, 16)
            }
        }
    }

    private func overlayButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.mono(16, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 160, height: 44)
                .background(.white.opacity(0.08))
                .overlay(Rectangle().stroke(.white.opacity(0.4), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}
