// Tips.swift — TipKit lessons and pointers
//
// Tips never cover a falling board: in-game tips sit in the pause and
// game-over overlays, and menu tips point at menu buttons. Four gameplay
// lessons (hold → twist → powers → combos) run in order, one per session,
// and most of them trigger on how the player actually plays. What happens
// mid-game (a power firing, a level-up) is said as it happens by the HUD's
// callouts instead (Callouts.swift).

import SwiftUI
import TipKit

// MARK: - State the rules read

/// Everything the tip rules read. The model flushes per-run tallies into these
/// at pause and game over rather than on every move, so the tip datastore
/// isn't written every frame.
enum TipState {
    /// The lesson this session may teach, as a `Lesson` raw value. Set at the start of each session.
    @Parameter(.transient) static var lesson: Int = -1
    /// Dial turns made by touch (buttons, corner zones, tapping the dial), across runs.
    @Parameter static var touchTurns: Int = 0
    /// Clears that finished exactly one hex, across runs.
    @Parameter static var singleClears: Int = 0
    /// Finished MAIN games; a win counts as three.
    @Parameter static var mainGames: Int = 0
    /// The mode of the latest personal best, as a `Mode` raw value; empty until there is one.
    @Parameter static var bestMode: String = ""
    @Parameter(.transient) static var isLandscape: Bool = false
    /// The input last used, as an `InputKind` raw value; tips name its buttons.
    @Parameter(.transient) static var inputKind: String = InputKind.initial.rawValue
    @Parameter(.transient) static var gameCenterSignedIn: Bool = false

    /// The input last used, for tip text.
    static var input: InputKind { InputKind(rawValue: inputKind) ?? .touch }

    /// A tip's text with the current input's button names filled in.
    static func text(_ template: String) -> Text { Text(Brand.copy.fill(template, for: input)) }

    /// A bin-full loss with fewer than `shortRunHexes` hexes.
    static let shortRun = Tips.Event(id: "shortRun")
    static let glowSeen = Tips.Event(id: "glowSeen")
    static let skinUnlocked = Tips.Event(id: "skinUnlocked")

    /// A run that ends with fewer hexes than this counts as short.
    static let shortRunHexes = 6
    /// A run that reaches this many hexes shows the player can already hold pieces.
    static let holdLearnedHexes = 12
    /// Turns before the twist lesson is worth showing.
    static let twistAfterTurns = 20
}

// MARK: - Lessons

/// The four gameplay lessons, taught in this order, one per session.
enum Lesson: Int, CaseIterable {
    case hold, twist, powers, combos

    var tip: any Tip {
        switch self {
        case .hold: HoldTip()
        case .twist: TwistTip()
        case .powers: GlowTip()
        case .combos: CombosTip()
        }
    }
}

/// Runs the lesson order. TipGroup needs iOS 18, so on iOS 17 each lesson's
/// rules wait for `TipState.lesson`, which only moves on at a session start.
@MainActor
enum Lessons {
    private static let learnedKey = "dialhex_lessons_learned"
    /// Coming back after this long in the background counts as a new session.
    private static let sessionGap: TimeInterval = 60 * 60
    private static var backgroundedAt: Date?

    private static var learned: Set<Int> {
        Set(UserDefaults.standard.array(forKey: learnedKey) as? [Int] ?? [])
    }

    /// Configure TipKit, open this session's lesson, and start watching lessons end.
    static func start() {
        try? Tips.configure([.displayFrequency(.hourly)])
        beginSession()
        Task { await watch() }
    }

    /// Track backgrounding, so a long time away starts a new session.
    static func sceneChanged(toBackground: Bool) {
        if toBackground {
            backgroundedAt = Date()
        } else if let backgroundedAt {
            if Date().timeIntervalSince(backgroundedAt) >= sessionGap { beginSession() }
            self.backgroundedAt = nil
        }
    }

    /// Offer the first lesson not yet learned (or none once they're all done).
    private static func beginSession() {
        let done = learned
        TipState.lesson = Lesson.allCases.first { !done.contains($0.rawValue) }?.rawValue ?? Lesson.allCases.count
    }

    /// However a lesson tip ends (learned in play, or closed), the lesson is done.
    /// The next one waits for the next session.
    private static func watch() async {
        await withTaskGroup(of: Void.self) { group in
            for lesson in Lesson.allCases {
                group.addTask { @MainActor in
                    for await status in lesson.tip.statusUpdates {
                        guard case .invalidated = status else { continue }
                        var done = learned
                        done.insert(lesson.rawValue)
                        UserDefaults.standard.set(Array(done), forKey: learnedKey)
                        break
                    }
                }
            }
        }
    }
}

/// Lesson 1, on the game-over screen after two short losses: gravity pauses under the dial.
struct HoldTip: Tip {
    var title: Text { Text("the dial holds pieces.") }
    var message: Text? {
        Text("gravity stops in the six cells under the dial. park a piece there and build the rest of the hex around it.")
    }

    var rules: [Rule] {
        #Rule(TipState.$lesson) { $0 == 0 }
        #Rule(TipState.shortRun) { $0.donations.count >= 2 }
    }
}

/// Lesson 2, after plenty of button turns and no twists.
struct TwistTip: Tip {
    var title: Text { Text("twist to turn.") }
    var message: Text? {
        Text("put two fingers on the board and twist. every 30° turns the dial one step, either way.")
    }

    var rules: [Rule] {
        #Rule(TipState.$lesson) { $0 == 1 }
        #Rule(TipState.$touchTurns) { $0 >= 20 }
        #Rule(TipState.$inputKind) { $0 == "touch" }
    }
}

/// Lesson 3, once a glowing piece has appeared but none has fired yet.
struct GlowTip: Tip {
    var title: Text { Text("glowing pieces have powers.") }
    var message: Text? {
        Text("clear a glowing piece in a hex to fire it. drain empties the bottom two rows; swap turns one colour into another.")
    }

    var rules: [Rule] {
        #Rule(TipState.$lesson) { $0 == 2 }
        #Rule(TipState.glowSeen) { $0.donations.count >= 1 }
    }
}

/// Lesson 4, after many single clears and no doubles. Scoring is per hex, so
/// this sells space and pace, not bonus points.
struct CombosTip: Tip {
    var title: Text { Text("finish two at once.") }
    var message: Text? {
        Text("line up two hexes so one turn completes both: it clears space twice as fast. every hex scores 100 × your level.")
    }

    var rules: [Rule] {
        #Rule(TipState.$lesson) { $0 == 3 }
        #Rule(TipState.$singleClears) { $0 >= 15 }
    }
}

// MARK: - Controls

/// The lower corners in landscape are invisible turn buttons.
struct CornerTip: Tip {
    var title: Text { Text("the hex turns the dial.") }
    var message: Text? {
        Text("spin the hex beside the bin either way, or tap it to turn forward. drag on the board to move the dial.")
    }

    var rules: [Rule] {
        #Rule(TipState.$inputKind) { $0 == "touch" }
    }
}

/// Pause-screen buttons for whatever isn't touch (which has RESUME and MENU on
/// screen); the menu already lists the in-game ones.
struct ControlsTip: Tip {
    var title: Text { Text(Brand.copy.inputs[TipState.input].name + ".") }
    var message: Text? { TipState.text("{resume} resumes. {cancel} goes to the menu.") }

    var rules: [Rule] {
        #Rule(TipState.$inputKind) { $0 != "touch" }
    }

    var options: [any Option] {
        IgnoresDisplayFrequency(true)
        MaxDisplayCount(2)
    }
}

// MARK: - Menu

/// On the skin button after a game opens a new skin.
struct SkinTip: Tip {
    var title: Text { Text("new skin.") }
    var message: Text? { TipState.text("{pick} the skin button to wear it. every SPECTRUM win and hex milestone opens another.") }

    var rules: [Rule] {
        #Rule(TipState.skinUnlocked) { $0.donations.count >= 1 }
    }
}

/// On the SPRINT button after a MAIN win or three MAIN games.
struct SprintTip: Tip {
    var title: Text { Text("try sprint.") }
    var message: Text? { Text("three minutes. as many hexes as you can.") }

    var rules: [Rule] {
        #Rule(TipState.$mainGames) { $0 >= 3 }
    }
}

/// On the mode button of a new personal best, when signed in to Game Center.
struct GameCenterTip: Tip {
    static let leaderboardAction = "leaderboard"

    var title: Text { Text("new best.") }
    var message: Text? { Text("it's on the Game Center leaderboard. see where you rank.") }

    var actions: [Action] {
        Action(id: Self.leaderboardAction, title: "leaderboard")
    }

    var rules: [Rule] {
        #Rule(TipState.$gameCenterSignedIn) { $0 == true }
        #Rule(TipState.$bestMode) { $0 != "" }
    }
}

// MARK: - One at a time

/// Watches a list of tips in priority order and offers the first eligible one,
/// so an overlay or the menu never shows two tips at once.
@Observable @MainActor
final class TipQueue {
    @ObservationIgnored let tips: [any Tip]
    private var eligible: Set<String> = []

    init(_ tips: [any Tip]) {
        self.tips = tips
    }

    var current: (any Tip)? { tips.first { eligible.contains($0.id) } }

    /// Whether `tip` is the one to show now.
    func isCurrent(_ tip: any Tip) -> Bool { current?.id == tip.id }

    /// Follow each tip's eligibility; runs until the calling view's task is cancelled.
    func watch() async {
        await withTaskGroup(of: Void.self) { group in
            for tip in tips {
                group.addTask { @MainActor [weak self] in
                    for await shows in tip.shouldDisplayUpdates {
                        if shows { self?.eligible.insert(tip.id) } else { self?.eligible.remove(tip.id) }
                    }
                }
            }
        }
    }
}
