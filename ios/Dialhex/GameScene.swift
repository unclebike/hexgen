// GameScene.swift — SpriteKit host: places the bins and runs the frame clock
//
// A solo game (or the demo behind the menu) is one BoardNode that glides
// between the menu and play layouts; versus puts one BoardNode per player side
// by side, and co-op puts both players' dials on one board in the versus layout. Colours, marks, and line weights come from the model's current skin.

import DialhexCore
import SpriteKit
import UIKit

extension SKColor {
    convenience init(rgb: UInt32, alpha: CGFloat = 1) {
        self.init(red: CGFloat((rgb >> 16) & 0xFF) / 255,
                  green: CGFloat((rgb >> 8) & 0xFF) / 255,
                  blue: CGFloat(rgb & 0xFF) / 255,
                  alpha: alpha)
    }
}

/// Layout sizes are written in phone points; Apple TV doubles them (see `GameScene.uiScale`).
func pt(_ value: CGFloat) -> CGFloat { value * GameScene.uiScale }

final class GameScene: SKScene {
    weak var model: AppModel?

    /// Apple TV shows everything at double its phone size, so text and buttons
    /// read from across the room. It's laid out at full size, with every fixed
    /// length doubled through `pt(_:)` and fonts doubled by `Skin.font`, rather
    /// than laid out small and scaled up, which would blur it on a 1080p TV.
    #if os(tvOS)
    static let uiScale: CGFloat = 2
    #else
    static let uiScale: CGFloat = 1
    #endif

    /// Landscape puts the HUD in a column down each side of the board instead of above and below it.
    static func isLandscape(_ size: CGSize) -> Bool { size.width > size.height }

    /// Where the bin sits: centred for play, or smaller and out of the way on the
    /// menu (at the top in portrait, on the left in landscape) with the logo inside it.
    enum Layout { case play, menu }

    /// Height the portrait menu keeps under the bin for its tagline, buttons, scores, and hints.
    static let menuContentHeight: CGFloat = pt(500)
    /// The menu bin at most this fraction of the play bin's size, so starting a game visibly grows it.
    private static let menuShrink: CGFloat = 0.8

    /// Landscape iPhone play puts the spinner on this side of the bin (left-handed
    /// players want it on the left). The model sets it; the bin moves over to suit.
    static var spinnerOnLeft = false

    /// The part of a view of `size` the bin fits inside, in SpriteKit coordinates (y up).
    /// Portrait play leaves room for the score line above and the rotate buttons below.
    /// Landscape play leaves a column on each side: on iPhone a narrow one for the stats
    /// and a wide one for the spinner, so the bin sits off-centre and the spinner comes
    /// in toward the middle of the screen rather than hugging its edge.
    private static func boardArea(for size: CGSize, layout: Layout = .play, spinnerOnLeft: Bool = spinnerOnLeft) -> CGRect {
        let landscape = isLandscape(size)
        switch layout {
        case .play:
            #if os(iOS)
            if !landscape {
                // Exactly the bin's box, so the fit puts it where the pair has it
                let bin = portraitPlay(for: size, spinnerOnLeft: spinnerOnLeft).bin
                return CGRect(x: bin.minX, y: size.height - bin.maxY, width: bin.width, height: bin.height)
            }
            #endif
            let top = pt(landscape ? 16 : 72)
            let bottom = pt(landscape ? 16 : 100)
            var left = size.width * 0.03, right = size.width * 0.03
            if landscape {
                #if os(iOS)
                let stats = pt(120), spinner = max(pt(140), size.width * 0.32)
                (left, right) = spinnerOnLeft ? (spinner, stats) : (stats, spinner)
                #else
                (left, right) = (pt(140), pt(140))
                #endif
            }
            return CGRect(x: left, y: bottom,
                          width: max(pt(100), size.width - left - right),
                          height: max(pt(100), size.height - top - bottom))
        case .menu where landscape:
            // The left half, top to bottom; the buttons take the right
            return CGRect(x: pt(16), y: pt(12), width: max(pt(100), size.width / 2 - pt(24)), height: max(pt(100), size.height - pt(24)))
        case .menu:
            let top = pt(12)
            let height = max(pt(120), size.height - top - menuContentHeight)
            return CGRect(x: size.width * 0.06, y: size.height - top - height, width: size.width * 0.88, height: height)
        }
    }

    #if os(iOS)
    /// The spinner's size against the bin's, and the gap between their facing edges,
    /// both in bin radii (corner to centre).
    private static let spinnerSize: CGFloat = 0.55
    private static let spinnerGap: CGFloat = 0.06

    /// Portrait iPhone play: the bin and the spinner as neighbouring hexes, as on the
    /// phone controller. Both stand on a corner; the spinner sits off the bin's lower
    /// side toward the player's hand (right, or left for the left-handed), an edge of
    /// each parallel to the other, and the pair fills the width under the score line,
    /// centred in the height left over.
    /// Both frames are the hexes' bounding boxes, in view coordinates (y down).
    /// `lift` is extra room kept clear under the pair, which raises it: the HUD's stats
    /// stay on the baseline of the unlifted pair (`lift: 0`), so the bin and dial sit
    /// up and away from the bottom edge while the score holds the bottom.
    /// `top` is the band kept clear above the pair (online co-op keeps its taller player line there).
    static func portraitPlay(for size: CGSize, spinnerOnLeft: Bool = spinnerOnLeft, lift: CGFloat = pt(80),
                             top: CGFloat = pt(44)) -> (bin: CGRect, spinner: CGRect) {
        let root3 = 3.0.squareRoot()
        // Under the top corners' mode and pause; the stats live in the pocket under the bin
        let room = CGRect(x: pt(8), y: top, width: max(pt(100), size.width - pt(16)), height: max(pt(100), size.height - top - pt(12) - lift))
        // In bin radii, with the bin at the origin
        let k = spinnerSize
        let apart = root3 / 2 * (1 + k) + spinnerGap
        let side: CGFloat = spinnerOnLeft ? -1 : 1
        let spinner = CGPoint(x: side * apart / 2, y: apart * root3 / 2)
        let minX = min(-root3 / 2, spinner.x - k * root3 / 2), maxX = max(root3 / 2, spinner.x + k * root3 / 2)
        let minY = -1.0, maxY = max(1, spinner.y + k)
        let fit = min(room.width / (maxX - minX), room.height / (maxY - minY))
        // Centred both ways in the room under the score line, so the spare height splits
        // above and below rather than all piling up at one end
        let origin = CGPoint(x: room.midX - (minX + maxX) / 2 * fit, y: room.midY - (minY + maxY) / 2 * fit)
        func box(_ center: CGPoint, _ radius: CGFloat) -> CGRect {
            CGRect(x: origin.x + (center.x - radius * root3 / 2) * fit, y: origin.y + (center.y - radius) * fit,
                   width: radius * root3 * fit, height: 2 * radius * fit)
        }
        return (box(.zero, 1), box(spinner, k))
    }
    #endif

    /// Points per triangle side for a view of `size`. The HUD and menu size
    /// their line weights from the play scale.
    static func boardScale(for size: CGSize, layout: Layout = .play) -> CGFloat {
        let n = CGFloat(Grid.size)
        let area = boardArea(for: size, layout: layout)
        let fit = min(area.width / (2 * n * Grid.rowHeight), area.height / (2 * n))
        guard layout == .menu else { return fit }
        return min(fit, boardScale(for: size) * menuShrink)
    }

    /// The bin's bounding box in a view of `size`, in view coordinates (y down),
    /// so the HUD can sit controls right up against it and the menu can lay out around it.
    /// SwiftUI callers pass `spinnerOnLeft` from the model, so a switch of hands redraws them.
    static func binFrame(for size: CGSize, layout: Layout = .play, spinnerOnLeft: Bool = spinnerOnLeft) -> CGRect {
        let n = CGFloat(Grid.size)
        let area = boardArea(for: size, layout: layout, spinnerOnLeft: spinnerOnLeft)
        let scale = boardScale(for: size, layout: layout)
        let width = 2 * n * Grid.rowHeight * scale
        let height = 2 * n * scale
        // The menu bin hugs the top of its area in portrait; everything else is centred
        let midY = layout == .menu && !isLandscape(size) ? area.maxY - height / 2 : area.midY
        return CGRect(x: area.midX - width / 2, y: size.height - midY - height / 2, width: width, height: height)
    }

    // MARK: - Versus layout

    /// Room above the bins for the match line (rule, clock), and above each bin for its player line.
    static let versusTopBand = pt(40)
    static let versusLabelBand = pt(34)
    private static let versusMargin = pt(16)

    /// Each player's bin, side by side in equal columns, in view coordinates (y down).
    static func versusFrames(for size: CGSize, players count: Int) -> [CGRect] {
        guard count > 0 else { return [] }
        let n = CGFloat(Grid.size)
        let columns = CGFloat(count)
        let top = versusTopBand + versusLabelBand
        let column = (size.width - versusMargin * (columns + 1)) / columns
        let height = max(pt(100), size.height - top - versusMargin)
        let scale = min(column / (2 * n * Grid.rowHeight), height / (2 * n))
        let binWidth = 2 * n * Grid.rowHeight * scale
        let binHeight = 2 * n * scale
        return (0..<count).map { i in
            let midX = versusMargin + (column + versusMargin) * CGFloat(i) + column / 2
            return CGRect(x: midX - binWidth / 2, y: top + (height - binHeight) / 2, width: binWidth, height: binHeight)
        }
    }

    /// Co-op's shared bin, and in online co-op on iPhone and iPad the local player's
    /// spinner beside it, placed as in a solo game: off the bin's lower corner in
    /// portrait, in a wide column on the hand side in landscape. Without the spinner
    /// (local co-op, Apple TV) the bin takes the whole width, like a one-player versus.
    /// Both frames are in view coordinates (y down), under the co-op player line.
    static func coopFrames(for size: CGSize, spinner: Bool,
                           spinnerOnLeft: Bool = spinnerOnLeft) -> (bin: CGRect, spinner: CGRect?) {
        let whole = versusFrames(for: size, players: 1).first ?? .zero
        #if os(iOS)
        guard spinner else { return (whole, nil) }
        let top = versusTopBand + versusLabelBand
        if !isLandscape(size) {
            // Clear of the home indicator, where a drag on the spinner would fight the swipe up
            let pair = portraitPlay(for: size, spinnerOnLeft: spinnerOnLeft, lift: pt(40), top: top)
            return (pair.bin, pair.spinner)
        }
        let column = max(pt(140), size.width * 0.32)
        let area = CGRect(x: spinnerOnLeft ? column : versusMargin, y: top,
                          width: max(pt(100), size.width - column - versusMargin),
                          height: max(pt(100), size.height - top - versusMargin))
        let n = CGFloat(Grid.size)
        let fit = min(area.width / (2 * n * Grid.rowHeight), area.height / (2 * n))
        let bin = CGRect(x: area.midX - n * Grid.rowHeight * fit, y: area.midY - n * fit,
                         width: 2 * n * Grid.rowHeight * fit, height: 2 * n * fit)
        // As in solo play: close against the bin, below its middle, never reaching into it
        let gap = pt(14)
        let spinTop = bin.midY - bin.height * 0.1
        let room = spinnerOnLeft ? bin.minX : size.width - bin.maxX
        let side = max(0, min(room - 2 * gap, size.height - spinTop - gap))
        let x = spinnerOnLeft ? bin.minX - gap - side : bin.maxX + gap
        let y = spinTop + (size.height - spinTop - gap - side) / 2
        return (bin, CGRect(x: x, y: y, width: side, height: side))
        #else
        return (whole, nil)
        #endif
    }

    // MARK: - Boards

    /// The solo game's board, or the demo's behind the menu.
    private let main: BoardNode
    /// One board per player while a versus match is on screen.
    private var versusBoards: [PlayerID: BoardNode] = [:]
    /// The shared board while a co-op game is on screen.
    private var coopBoard: BoardNode?
    /// Whether the co-op bin leaves room for the local player's spinner (online co-op).
    private var coopSpinner = false
    private var scale: CGFloat = 30 // points per triangle side, at the play layout
    private var lastUpdate: TimeInterval = 0
    private(set) var layout = Layout.menu
    /// Seconds the bin takes to glide between the menu and play.
    static let glideTime: TimeInterval = 0.45
    private weak var gestureView: SKView?
    private var skin = Skin(Brand.tokens.skins[0])

    override init() {
        main = BoardNode(skin: skin)
        super.init(size: CGSize(width: 390, height: 844))
        scaleMode = .resizeFill
        anchorPoint = .zero
        addChild(main)
        backgroundColor = skin.background.sk
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func didChangeSize(_ oldSize: CGSize) {
        super.didChangeSize(oldSize)
        // The bin stands on a vertex: it is 2·size·rowHeight wide and 2·size tall on screen.
        // It's always built at the play scale; the menu just shrinks and moves it.
        scale = Self.boardScale(for: size)
        main.build(scale: scale)
        setLayout(layout, animated: false)
        for board in versusBoards.values { board.build(scale: scale) }
        coopBoard?.build(scale: scale)
        placeVersusBoards()
    }

    /// The spinner changed sides: rebuild at the new scale and glide the bin over.
    func spinnerSideChanged() {
        scale = Self.boardScale(for: size)
        main.build(scale: scale)
        setLayout(layout, animated: true)
        placeVersusBoards()
    }

    // MARK: - Layout

    /// Where the main board sits and how much it's shrunk for a layout, at the current size.
    private func placement(_ layout: Layout) -> (position: CGPoint, scale: CGFloat) {
        place(Self.binFrame(for: size, layout: layout), boardScale: Self.boardScale(for: size, layout: layout))
    }

    /// A node position and scale that put a bin built at `scale` into `frame` (view coordinates).
    private func place(_ frame: CGRect, boardScale: CGFloat) -> (position: CGPoint, scale: CGFloat) {
        // Frames are y-down; the scene is y-up
        (CGPoint(x: frame.midX, y: size.height - frame.midY), boardScale / scale)
    }

    /// Move the bin to a layout, gliding (and growing or shrinking) if `animated`.
    func setLayout(_ next: Layout, animated: Bool) {
        layout = next
        main.hideAbove = next == .menu ? Marks.logoBottomInBin : nil
        let target = placement(next)
        main.restPosition = target.position
        main.removeAction(forKey: "shake")
        main.removeAction(forKey: "glide")
        guard animated else {
            main.position = target.position
            main.setScale(target.scale)
            return
        }
        let glide = SKAction.group([.move(to: target.position, duration: Self.glideTime),
                                    .scale(to: target.scale, duration: Self.glideTime)])
        glide.timingMode = .easeInEaseOut
        main.run(glide, withKey: "glide")
    }

    /// Show one board per player (versus), or go back to the single board (nil).
    func showVersus(_ players: [PlayerID]?) {
        for board in versusBoards.values { board.removeFromParent() }
        versusBoards = [:]
        main.isHidden = players != nil
        for player in players ?? [] {
            let board = BoardNode(skin: skin)
            board.build(scale: scale)
            addChild(board)
            versusBoards[player] = board
        }
        placeVersusBoards()
    }

    /// Show the shared co-op board with a dial for each player, tinted in their colours,
    /// or go back to the single board (nil). `spinner` leaves room beside the bin for
    /// the local player's spinner, for online co-op.
    func showCoop(_ tints: [PlayerID: RGB]?, spinner: Bool = false) {
        coopBoard?.removeFromParent()
        coopBoard = nil
        coopSpinner = spinner
        main.isHidden = tints != nil
        guard let tints else { return }
        let board = BoardNode(skin: skin)
        board.build(scale: scale)
        board.dialTints = tints
        addChild(board)
        coopBoard = board
        placeVersusBoards()
    }

    private func placeVersusBoards() {
        let players = versusBoards.keys.sorted()
        let frames = Self.versusFrames(for: size, players: players.count)
        for (player, frame) in zip(players, frames) {
            guard let board = versusBoards[player] else { continue }
            place(board, in: frame)
        }
        // Co-op's one bin: the whole width, or beside the spinner online
        if let coopBoard {
            place(coopBoard, in: Self.coopFrames(for: size, spinner: coopSpinner).bin)
        }
    }

    private func place(_ board: BoardNode, in frame: CGRect) {
        let target = place(frame, boardScale: frame.height / (2 * CGFloat(Grid.size)))
        board.restPosition = target.position
        board.position = target.position
        board.setScale(target.scale)
    }

    /// Fade every piece out, for the demo emptying the bin before it starts again.
    func emptyBoard() {
        main.emptyBoard(at: lastUpdate)
    }

    // MARK: - Skin

    /// Pick up a new skin (or the next strobe colour) on the next frame.
    private func syncSkin(_ next: Skin) {
        guard next != skin else { return }
        skin = next
        backgroundColor = skin.background.sk
        main.setSkin(next)
        for board in versusBoards.values { board.setSkin(next) }
        coopBoard?.setSkin(next)
    }

    // MARK: - Input

    override func didMove(to view: SKView) {
        super.didMove(to: view)
        // Apple TV has no touch screen; the remote plays through ControllerInput
        #if os(iOS)
        guard gestureView !== view else { return }
        gestureView = view
        view.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(tapped)))
        let twist = UIRotationGestureRecognizer(target: self, action: #selector(twisted))
        view.addGestureRecognizer(twist)
        let drag = UIPanGestureRecognizer(target: self, action: #selector(dragged))
        drag.maximumNumberOfTouches = 1
        view.addGestureRecognizer(drag)
        #endif
    }

    @objc private func tapped(_ recognizer: UITapGestureRecognizer) {
        guard let view = recognizer.view else { return }
        // In co-op the shared board is the one being played
        let point = board(for: nil).latticePoint(convertPoint(fromView: recognizer.location(in: view)), from: self)
        MainActor.assumeIsolated { model?.tap(at: point) }
    }

    #if os(iOS)
    /// One finger dragged across the board carries the dial with it.
    @objc private func dragged(_ recognizer: UIPanGestureRecognizer) {
        guard let view = recognizer.view, recognizer.state == .began || recognizer.state == .changed else { return }
        let point = board(for: nil).latticePoint(convertPoint(fromView: recognizer.location(in: view)), from: self)
        MainActor.assumeIsolated { model?.drag(to: point) }
    }

    /// Two-finger twist turns the dial, one step per 30°.
    @objc private func twisted(_ recognizer: UIRotationGestureRecognizer) {
        guard recognizer.state == .changed, abs(recognizer.rotation) > .pi / 6 else { return }
        let direction: RotationDirection = recognizer.rotation > 0 ? .clockwise : .counterClockwise
        recognizer.rotation = 0
        MainActor.assumeIsolated { model?.rotate(direction, from: .twist) }
    }
    #endif

    // MARK: - Frame

    override func update(_ currentTime: TimeInterval) {
        let dt = lastUpdate > 0 ? min(currentTime - lastUpdate, 0.05) : 1.0 / 60
        lastUpdate = currentTime
        MainActor.assumeIsolated {
            guard let model else { return }
            model.tick(dt)
            syncSkin(model.skin)
            if let match = model.versus {
                for (player, board) in versusBoards {
                    guard let game = match.boards[player] else { continue }
                    board.sync(game, clock: currentTime)
                    // A knocked-out bin fades back
                    board.alpha = match.eliminated.contains(player) ? 0.35 : 1
                }
            } else if let coop = model.coop {
                coopBoard?.sync(coop, clock: currentTime)
            } else if let game = model.boardGame {
                main.sync(game, clock: currentTime)
                main.hint = model.hint
            }
        }
    }

    /// Clear every piece and effect, for a new game or the menu.
    func reset() {
        main.reset()
        for board in versusBoards.values { board.reset() }
        coopBoard?.reset()
    }

    // MARK: - Effects

    /// The board a player's effects play on: the shared one in co-op, theirs in
    /// versus, otherwise the main one.
    private func board(for player: PlayerID?) -> BoardNode {
        coopBoard ?? player.flatMap { versusBoards[$0] } ?? main
    }

    /// Burst of triangle confetti from each cleared hex, and a little shake.
    func showClear(_ hexes: [Hex], for player: PlayerID? = nil) {
        board(for: player).showClear(hexes)
    }

    /// Jiggle a board, fading out over `duration` seconds.
    func shake(duration: TimeInterval, intensity: CGFloat, for player: PlayerID? = nil) {
        board(for: player).shake(duration: duration, intensity: pt(intensity))
    }
}
