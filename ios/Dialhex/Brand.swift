// Brand.swift — Brand tokens and skins, read from the skins.json the web game uses too
//
// Colours, piece marks, line weights, fonts, the logo, and copy all live in
// that one file, so the two builds can't drift apart.

import CoreText
import DialhexCore
import SpriteKit
import SwiftUI
import UIKit

/// A colour written as "#RRGGBB".
struct RGB: Decodable, Equatable, Hashable {
    let value: UInt32

    init(_ value: UInt32) { self.value = value }

    init(from decoder: Decoder) throws {
        let text = try decoder.singleValueContainer().decode(String.self)
        guard text.hasPrefix("#"), let value = UInt32(text.dropFirst(), radix: 16) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Expected #RRGGBB, got \(text)"))
        }
        self.value = value
    }

    private var channels: [Double] { [Double((value >> 16) & 0xFF), Double((value >> 8) & 0xFF), Double(value & 0xFF)] }

    /// Mix toward white (amount > 0) or black (amount < 0).
    func tinted(_ amount: Double) -> RGB {
        let target = amount > 0 ? 255.0 : 0
        let c = channels.map { UInt32(max(0, min(255, ($0 + (target - $0) * abs(amount)).rounded()))) }
        return RGB(c[0] << 16 | c[1] << 8 | c[2])
    }

    /// WCAG relative luminance.
    var luminance: Double {
        let linear = channels.map { v -> Double in
            let c = v / 255
            return c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear[0] + 0.7152 * linear[1] + 0.0722 * linear[2]
    }

    func contrast(with other: RGB) -> Double {
        let (a, b) = (luminance, other.luminance)
        return (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }

    var sk: SKColor { SKColor(rgb: value) }
    func sk(_ alpha: CGFloat) -> SKColor { SKColor(rgb: value, alpha: alpha) }
    var color: Color { Color(rgb: value) }
    func color(_ opacity: Double) -> Color { Color(rgb: value, opacity: opacity) }
}

/// The small shape inset in each piece, one per colour.
enum Mark: String, Decodable {
    case dot, spokes, ring, frame, trio, corners, tri, target
}

struct BrandTokens: Decodable {
    struct Weights: Decodable {
        let hairline: Double
        let hairlineAlpha: Double
        let line: Double
        let heavy: Double
    }

    struct Logo: Decodable {
        let word: String
        let lines: [String]?
        let gap: Int
        let lineGap: Int
        /// Rows of '#' and '.', one character per column.
        let glyphs: [String: [String]]
    }

    struct ModeCopy: Decodable {
        let label: String
        let detail: String
    }

    struct HowToCopy: Decodable {
        struct Rule: Decodable, Hashable {
            /// Which drawing goes beside it (see HowToArt).
            let art: String
            let title: String
            let body: String
        }

        let label: String
        /// The menu tile's label.
        let short: String
        let detail: String
        let title: String
        let back: String
        let rules: [Rule]
    }

    /// Co-op with a Game Center friend, each on their own device.
    struct OnlineCopy: Decodable {
        let label: String
        let detail: String
        let signedOut: String
        let restricted: String
        let title: String
        let you: String
        let friend: String
        let waiting: String
        let inviteHint: String
        let hostHint: String
        let guestHint: String
        let invite: String
        let start: String
        let leave: String
        let resume: String
        let again: String
        let pausedHint: String
        let matchOver: String
        let left: String
        let hostLeft: String
        let versionMismatch: String
    }

    /// Split-screen versus and two-player co-op on Apple TV.
    struct VersusCopy: Decodable {
        let label: String
        let detail: String
        let title: String
        let join: String
        let ready: String
        let dropped: String
        let rules: [String: ModeCopy]
        /// Each co-op game, by `Mode` raw value.
        let coopModes: [String: ModeCopy]
        let lobbyHint: String
        let needTwo: String
        let coopTwoOnly: String
        let phoneHint: String
        let out: String
        let wins: String
        let tie: String
        let coopWon: String
        let coopOver: String
        let lost: String
        let lostHint: String
        let matchOver: String
        let pausedHint: String

        func rule(_ rule: Versus.Rule) -> ModeCopy {
            rules[rule.rawValue] ?? ModeCopy(label: rule.rawValue.uppercased(), detail: "")
        }

        /// The name and line for whatever the lobby will start.
        func kind(_ kind: MatchKind) -> ModeCopy {
            switch kind {
            case .versus(let rule): return self.rule(rule)
            case .coop(let mode):
                return coopModes[mode.rawValue] ?? ModeCopy(label: "CO-OP " + mode.rawValue.uppercased(), detail: "")
            }
        }
    }

    /// The iPhone app's phone-as-controller screen.
    struct ControllerCopy: Decodable {
        let label: String
        /// The menu tile's label.
        let short: String
        let detail: String
        /// The Apple TV menu's line with the code a phone enters.
        let menuHint: String
        let title: String
        let searching: String
        let codePrompt: String
        let connecting: String
        let waiting: String
        let paused: String
        let over: String
        let won: String
        let rejected: String
        let lost: String
        let leave: String
        /// The connect page: the gamepads paired with this device, and the way to the TV pad.
        let hubTitle: String
        let gamepads: String
        let noGamepads: String
        let keyboard: String
        let connected: String
        let tv: String
        let tvDetail: String
        let tvButton: String
        let tvNeedsUpdate: String
        let back: String
    }

    /// What one kind of input calls its buttons, so hints and tips match the input in hand.
    struct InputCopy: Decodable {
        let name: String
        /// The controls line; touch and keyboard use the copy's shared touchHint and keysHint.
        let hint: String?
        let confirm: String
        let cancel: String
        let resume: String
        let sides: String
        let pick: String
    }

    struct Inputs: Decodable {
        let touch: InputCopy
        let keyboard: InputCopy
        let gamepad: InputCopy
        let remote: InputCopy
        let phone: InputCopy

        subscript(kind: InputKind) -> InputCopy {
            switch kind {
            case .touch: touch
            case .keyboard: keyboard
            case .gamepad: gamepad
            case .remote: remote
            case .phone: phone
            }
        }
    }

    struct SpeedCopy: Decodable {
        let label: String
        /// Each speed's name, by `Speed` raw value.
        let levels: [String: String]
        /// What each speed does to the points, by `Speed` raw value.
        let hints: [String: String]
    }

    /// The first game's walkthrough, where the bot plays until it's cleared a few hexes.
    struct WalkthroughCopy: Decodable {
        let watch: String
        let takeOver: String
        let yourTurn: String
    }

    /// One in-play callout: its line, and what explains it the first few times.
    struct CalloutCopy: Decodable {
        let title: String
        let detail: String?
    }

    struct CalloutsCopy: Decodable {
        let rescue, levelUp, drain, swap, glow, held, danger, finale, hint: CalloutCopy

        subscript(kind: CalloutKind) -> CalloutCopy {
            switch kind {
            case .rescue: rescue
            case .hint: hint
            case .levelUp: levelUp
            case .drain: drain
            case .swap: swap
            case .glow: glow
            case .held: held
            case .danger: danger
            case .finale: finale
            }
        }
    }

    struct Copy: Decodable {
        let tagline: String
        let topScores: String
        let modes: [String: ModeCopy]
        let best: String
        let hexes: String
        let skin: String
        let speed: SpeedCopy
        let paused: String
        let resume: String
        /// The pause screen's switch for which side the landscape spinner sits.
        let leftHanded: String
        let rightHanded: String
        let menu: String
        let binFull: String
        let cleared: String
        let timeUp: String
        let newBest: String
        let unlocked: String
        let walkthrough: WalkthroughCopy
        let callouts: CalloutsCopy
        let touchHint: String
        let keysHint: String
        let inputs: Inputs
        let versus: VersusCopy
        let online: OnlineCopy
        let controller: ControllerCopy
        let howTo: HowToCopy

        /// The controls line for an input.
        func hint(for kind: InputKind) -> String {
            switch kind {
            case .touch: return touchHint
            case .keyboard: return keysHint
            default: return inputs[kind].hint ?? keysHint
            }
        }

        /// `text` with an input's button names in place of {confirm}, {cancel}, {resume}, {sides}, and {pick}.
        func fill(_ text: String, for kind: InputKind) -> String {
            let names = inputs[kind]
            return text.replacingOccurrences(of: "{confirm}", with: names.confirm)
                .replacingOccurrences(of: "{cancel}", with: names.cancel)
                .replacingOccurrences(of: "{resume}", with: names.resume)
                .replacingOccurrences(of: "{sides}", with: names.sides)
                .replacingOccurrences(of: "{pick}", with: names.pick)
        }

        func mode(_ mode: Mode) -> ModeCopy { modes[mode.rawValue] ?? ModeCopy(label: mode.rawValue.uppercased(), detail: "") }
        func unlocked(_ id: String) -> String { unlocked.replacingOccurrences(of: "%@", with: id) }
    }

    struct Unlocks: Decodable {
        let milestones: [Int]
    }

    let weights: Weights
    let marks: [Mark]
    let logo: Logo
    let copy: Copy
    let unlocks: Unlocks
    let skins: [SkinSpec]
}

struct SkinSpec: Decodable, Equatable {
    struct Fonts: Decodable, Equatable {
        let display: String
        let text: String
        let digits: String
    }

    struct Stroke: Decodable, Equatable {
        enum Weight: String, Decodable { case line, heavy }
        var outline: Weight?
        var outlineColor: RGB?
        var markScale: Double?
    }

    struct Effects: Decodable, Equatable {
        var misregister: Double?
        var grain: Double?
        var scanlines: Double?
        var glow: Double?
        var strobe: [RGB]?
        var tints: [Double]?
    }

    struct Sound: Decodable, Equatable, Hashable {
        enum Wave: String, Decodable { case sine, triangle, square, sawtooth }
        var wave: Wave
        var octave: Int
        /// Whether the music's pad plays (the web game's 40 Hz drone, in skins.json's terms).
        var drone: Bool
    }

    let id: String
    let background: RGB
    let empty: RGB
    let ink: RGB
    let mark: RGB
    let pieces: [RGB]
    let fonts: Fonts
    let fontScale: Double?
    let stroke: Stroke
    let effects: Effects
    let sound: Sound
}

enum Brand {
    /// skins.json from the app bundle. It's copied in at build time, so a
    /// missing or broken file is a build problem, caught on first launch.
    static let tokens: BrandTokens = {
        registerFonts()
        do {
            guard let url = Bundle.main.url(forResource: "skins", withExtension: "json") else {
                fatalError("skins.json is missing from the app bundle")
            }
            return try JSONDecoder().decode(BrandTokens.self, from: Data(contentsOf: url))
        } catch {
            fatalError("skins.json didn't decode: \(error)")
        }
    }()

    /// Make the bundled fonts available by PostScript name.
    private static func registerFonts() {
        for url in Bundle.main.urls(forResourcesWithExtension: "ttf", subdirectory: nil) ?? [] {
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }

    static var copy: BrandTokens.Copy { tokens.copy }
}

/// The three line weights, sized from the board scale (points per triangle side).
struct LineWeights {
    let hairline: CGFloat
    let hairlineAlpha: CGFloat
    let line: CGFloat
    let heavy: CGFloat

    init(scale: CGFloat) {
        let w = Brand.tokens.weights
        hairline = pt(w.hairline) // a fixed width, not a share of the board scale
        hairlineAlpha = w.hairlineAlpha
        line = scale * w.line
        heavy = scale * w.heavy
    }
}

/// The active skin, with its strobe applied.
struct Skin: Equatable {
    enum FontRole { case display, text, digits }

    let spec: SkinSpec
    /// Single-hue skins step through their strobe colours on every clear.
    private(set) var strobeIndex = 0

    init(_ spec: SkinSpec) { self.spec = spec }

    var id: String { spec.id }
    var background: RGB { spec.background }
    var empty: RGB { spec.empty }
    var hardCuts: Bool { spec.effects.strobe != nil }

    var ink: RGB {
        guard let strobe = spec.effects.strobe, !strobe.isEmpty else { return spec.ink }
        return strobe[strobeIndex % strobe.count]
    }

    var pieces: [RGB] {
        guard spec.effects.strobe != nil, let tints = spec.effects.tints else { return spec.pieces }
        let hue = ink
        return tints.map { hue.tinted($0) }
    }

    func piece(_ color: Int) -> RGB {
        let all = pieces
        return all.indices.contains(color) ? all[color] : ink
    }

    /// Whichever of the skin's mark colour and ink stands out more on a piece.
    func markColor(on piece: RGB) -> RGB {
        piece.contrast(with: spec.mark) >= piece.contrast(with: ink) ? spec.mark : ink
    }

    mutating func advanceStrobe() { strobeIndex += 1 }
    mutating func resetStrobe() { strobeIndex = 0 }

    private func fontName(_ role: FontRole) -> String {
        switch role {
        case .display: spec.fonts.display
        case .text: spec.fonts.text
        case .digits: spec.fonts.digits
        }
    }

    func font(_ role: FontRole, _ size: CGFloat) -> Font {
        // Sizes are in phone points; Apple TV doubles them (see `pt(_:)`)
        .custom(fontName(role), fixedSize: pt(size) * CGFloat(spec.fontScale ?? 1))
    }

    /// How wide `text` sets in `font(role, size)`, with `tracking` ems of letter spacing.
    func width(of text: String, _ role: FontRole, _ size: CGFloat, tracking: CGFloat = 0) -> CGFloat {
        guard let font = UIFont(name: fontName(role), size: pt(size) * CGFloat(spec.fontScale ?? 1)) else { return 0 }
        return (text as NSString).size(withAttributes: [.font: font, .kern: pt(size) * tracking]).width
    }
}
