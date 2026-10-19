// BoardNode.swift — One bin: its lattice, falling triangles, the dial, and effects
//
// The scene shows one of these for a solo game (and the demo behind the menu),
// one per player in versus, or one with both players' dials in co-op. A board is always built at the play scale; the
// scene moves and shrinks the whole node to place it. Positions follow the
// game clock every frame (so pausing freezes them); one-shot effects — clear
// flashes, confetti, shake — are SKActions.

import DialhexCore
import SpriteKit
import UIKit

/// One triangle on the board.
private final class PieceNode: SKShapeNode {
    var colorIndex = -1
    var pointsUp: Bool?
    var isClearing = false
    /// The triangle's corners about its centre, for building its mark.
    var corners: [CGPoint] = []
    let mark = SKShapeNode()
    let flash = SKShapeNode()
    let glow = SKShapeNode()   // the pulsing edge of a power piece
    let ghost = SKShapeNode()  // riso's misregistered second plate
    let bloom = SKShapeNode()  // crt's phosphor glow
}

/// What a board draws: a solo game, the demo, a versus board, or co-op.
protocol BoardState {
    var board: Board { get }
    var phase: Phase { get }
    var fallProgress: Double { get }
    /// Every turn still being animated.
    var dialTurns: [DialTurn] { get }
    /// Every dial on the board, by the player holding it.
    var dials: [PlayerID: Vertex] { get }
}

extension Game: BoardState {
    var dialTurns: [DialTurn] { dialTurn.map { [$0] } ?? [] }
    var dials: [PlayerID: Vertex] { [PlayerID(0): cursor.vertex] }
}

extension CoopGame: BoardState {
    var dials: [PlayerID: Vertex] {
        Dictionary(uniqueKeysWithValues: seatedPlayers.compactMap { player in
            cursor(for: player).map { (player, $0.vertex) }
        })
    }
}

/// One player's dial: the outline and its centre dot.
private final class DialNode: SKShapeNode {
    let dot = SKShapeNode(circleOfRadius: 1)
    /// The vertex it was last moved to.
    var vertex: Vertex?
}

final class BoardNode: SKNode {
    private static let pieceInset: CGFloat = 0.9   // keep a gap between triangles, so the board reads as tiles
    private static let emptyTime: TimeInterval = 0.35
    /// A small white triangle, tinted per burst; shared by every board.
    private static let confetti = makeConfettiTexture()

    /// The bin and everything in it; paused along with the game.
    private let content = SKNode()
    private let bin = SKShapeNode()
    private let lattice = SKShapeNode()
    /// The dial outline about the origin, at the current scale.
    private var dialPath: CGPath?
    private var dials: [PlayerID: DialNode] = [:]
    /// An assisted game's hint: a faint, pulsing dial outline where one turn finishes a hex.
    private let hintNode = SKShapeNode()
    var hint: Vertex? {
        didSet { if hint != oldValue { syncHint() } }
    }
    /// Players' colours for their dials' centre dots, when there's more than one
    /// player on the board; otherwise the dot is in ink.
    var dialTints: [PlayerID: RGB] = [:] {
        didSet { for (player, dial) in dials { styleDial(dial, for: player) } }
    }
    private var pieces: [Int: PieceNode] = [:]
    private(set) var scale: CGFloat = 30 // points per triangle side
    private var weights = LineWeights(scale: 30)
    private var skin: Skin
    /// Where the node sits when it isn't shaking, for the current layout.
    var restPosition = CGPoint.zero
    /// On the menu, pieces above this lattice x (the bottom of the logo) are hidden,
    /// so the demo's triangles seem to drop out of the letters.
    var hideAbove: Double?
    /// The demo emptying the bin: when it started, by the scene clock.
    private var emptying: TimeInterval?

    init(skin: Skin) {
        self.skin = skin
        super.init()
        addChild(content)
        bin.strokeColor = .clear
        content.addChild(bin)
        content.addChild(lattice)
        hintNode.fillColor = .clear
        hintNode.lineJoin = .miter
        hintNode.zPosition = 9 // under the player's dial, over the pieces
        hintNode.isHidden = true
        content.addChild(hintNode)
        applySkinColors()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    // MARK: - Geometry

    /// Lattice x runs down the screen and lattice y runs right to left.
    private func point(_ p: LatticePoint) -> CGPoint {
        CGPoint(x: -p.y * scale, y: -p.x * scale)
    }

    private func path(_ points: [LatticePoint]) -> CGPath {
        Marks.polygon(points.map(point))
    }

    /// (Re)build the bin at `scale` points per triangle side.
    func build(scale: CGFloat) {
        self.scale = scale
        weights = LineWeights(scale: scale)
        bin.path = path(Grid.binOutline)
        let grid = CGMutablePath()
        for cell in Grid.cells { grid.addPath(path(Grid.vertices(of: cell))) }
        lattice.path = grid
        lattice.lineWidth = weights.hairline
        lattice.strokeColor = skin.ink.sk(weights.hairlineAlpha)

        // The dial outline is the same around every vertex, so draw it about the origin
        let origin = Grid.position(of: Grid.dials[0])
        dialPath = path(Grid.dialOutline(Grid.dials[0]).map { $0 - origin })
        for (player, dial) in dials {
            styleDial(dial, for: player)
            dial.vertex = nil
        }
        styleHint()
        syncHint()

        // Piece shapes depend on the scale; rebuild them on the next frame
        for node in pieces.values { node.pointsUp = nil }
    }

    /// Board point under a point in `node`'s coordinates, in lattice units.
    func latticePoint(_ p: CGPoint, from node: SKNode) -> LatticePoint {
        let local = content.convert(p, from: node)
        return LatticePoint(-local.y / scale, -local.x / scale)
    }

    // MARK: - Skin

    /// Pick up a new skin (or the next strobe colour).
    func setSkin(_ next: Skin) {
        guard next != skin else { return }
        let shapesChanged = next.spec != skin.spec
        skin = next
        applySkinColors()
        for node in pieces.values {
            node.colorIndex = -1
            if shapesChanged { node.pointsUp = nil }
        }
    }

    private func applySkinColors() {
        bin.fillColor = skin.empty.sk
        lattice.strokeColor = skin.ink.sk(weights.hairlineAlpha)
        for (player, dial) in dials { styleDial(dial, for: player) }
        styleHint()
    }

    // MARK: - Frame

    /// Follow a game for one frame; `clock` is the scene's time.
    func sync(_ game: some BoardState, clock: TimeInterval) {
        content.isPaused = game.phase != .playing
        if !content.isPaused { syncPieces(game, clock: clock) }
        syncDials(game)
    }

    /// Clear every piece and effect, for a new game or the menu.
    func reset() {
        for node in pieces.values { node.removeFromParent() }
        pieces.removeAll()
        content.children.filter { $0 is SKEmitterNode }.forEach { $0.removeFromParent() }
        removeAction(forKey: "shake")
        if action(forKey: "glide") == nil { position = restPosition }
        content.isPaused = false
        for dial in dials.values { dial.vertex = nil }
        hint = nil
        emptying = nil
    }

    /// Fade every piece out, for the demo emptying the bin before it starts again.
    func emptyBoard(at clock: TimeInterval) {
        emptying = clock
    }

    private func syncPieces(_ game: some BoardState, clock: TimeInterval) {
        let fall = game.fallProgress
        // The demo emptying the bin fades everything together
        let fade = emptying.map { max(0, 1 - (clock - $0) / Self.emptyTime) } ?? 1

        // The board already holds each turned dial; draw those six triangles
        // rotated back by the part of the 60° turn that hasn't played yet.
        // Dials never overlap, so a piece is in at most one turn.
        var turning: [Int: (pivot: CGPoint, angle: CGFloat)] = [:]
        for turn in game.dialTurns {
            let pivot = point(Grid.position(of: turn.vertex))
            let t = min(1, turn.elapsed / Game.rotateTime)
            let easeOut = 1 - (1 - t) * (1 - t)
            // SpriteKit angles are counter-clockwise; undo a clockwise turn
            let angle = CGFloat(turn.direction.rawValue) * .pi / 3 * (1 - easeOut)
            for id in turn.pieceIDs { turning[id] = (pivot, angle) }
        }

        var seen = Set<Int>()
        for (cell, piece) in game.board {
            seen.insert(piece.id)
            let node = pieces[piece.id] ?? addPiece(piece)
            update(node, piece, at: cell)

            var center = Grid.center(of: cell)
            if let from = piece.from {
                // Slide in from the cell it left at the last fall step
                center += (Grid.center(of: from) - center) * (1 - fall)
            }
            var position = point(center)
            node.zRotation = 0
            if let (pivot, angle) = turning[piece.id] {
                let offset = CGPoint(x: position.x - pivot.x, y: position.y - pivot.y)
                    .applying(CGAffineTransform(rotationAngle: angle))
                position = CGPoint(x: pivot.x + offset.x, y: pivot.y + offset.y)
                node.zRotation = angle
            }
            node.position = position
            // On the menu, a piece shows only once it's fallen clear of the logo
            var alpha = fade
            if let hideAbove { alpha *= min(1, max(0, (center.x - hideAbove) / 0.5)) }
            node.alpha = alpha
        }

        for (id, node) in pieces where !seen.contains(id) {
            node.removeFromParent()
            pieces[id] = nil
        }
    }

    private func addPiece(_ piece: Piece) -> PieceNode {
        let node = PieceNode()
        node.lineJoin = .miter
        for child in [node.bloom, node.ghost] {
            child.strokeColor = .clear
            child.zPosition = -1
            node.addChild(child)
        }
        node.mark.strokeColor = .clear
        node.addChild(node.mark)
        node.flash.strokeColor = .clear
        node.flash.alpha = 0
        node.addChild(node.flash)
        node.glow.strokeColor = .clear
        node.glow.isHidden = true
        node.addChild(node.glow)
        content.addChild(node)
        pieces[piece.id] = node
        return node
    }

    /// Match a node's shape, colour, mark, and power glow to its piece.
    private func update(_ node: PieceNode, _ piece: Piece, at cell: Cell) {
        let up = Grid.isUp(cell)
        if node.pointsUp != up {
            node.pointsUp = up
            node.colorIndex = -1 // the mark's shape depends on the colour too
            let center = Grid.center(of: cell)
            let corners = Grid.vertices(of: cell).map { point(($0 - center) * Double(Self.pieceInset)) }
            node.corners = corners
            let shape = Marks.polygon(corners)
            node.path = shape
            node.flash.path = shape
            node.bloom.path = Marks.polygon(Marks.scaled(corners, by: 1.2))
            let offset = CGFloat(skin.spec.effects.misregister ?? 0) * scale
            node.ghost.path = shape
            node.ghost.position = CGPoint(x: -offset, y: -offset * 0.6)
            // Heavy edge kept inside the triangle, so it never touches a neighbour: a filled band
            // between the piece and a copy pulled in by the heavy weight (exact at the corners,
            // which a stroke isn't)
            let inradius = hypot(corners[0].x, corners[0].y) / 2
            let band = CGMutablePath()
            band.addLines(between: corners)
            band.closeSubpath()
            band.addLines(between: Marks.scaled(corners, by: max(0, 1 - weights.heavy / inradius)).reversed())
            band.closeSubpath()
            node.glow.path = band
            node.lineWidth = skin.spec.stroke.outline.map { $0 == .heavy ? weights.heavy : weights.line } ?? 0
        }
        if node.colorIndex != piece.color {
            node.colorIndex = piece.color
            let fill = skin.piece(piece.color)
            node.fillColor = fill.sk
            node.strokeColor = skin.spec.stroke.outlineColor?.sk ?? .clear
            node.flash.fillColor = skin.ink.sk
            node.bloom.fillColor = fill.sk(CGFloat(skin.spec.effects.glow ?? 0))
            node.bloom.isHidden = skin.spec.effects.glow == nil
            node.ghost.fillColor = fill.sk(0.35)
            node.ghost.isHidden = skin.spec.effects.misregister == nil
            let markColor = skin.markColor(on: fill)
            node.mark.fillColor = markColor.sk
            node.glow.fillColor = markColor.sk
            let marks = Brand.tokens.marks
            if marks.indices.contains(piece.color) {
                node.mark.path = Marks.path(marks[piece.color], corners: node.corners,
                                            lineWidth: weights.line, scale: CGFloat(skin.spec.stroke.markScale ?? 1))
            }
        }
        if (piece.power != nil) == node.glow.isHidden {
            node.glow.isHidden = piece.power == nil
            node.glow.removeAllActions()
            if piece.power != nil {
                let pulse = SKAction.sequence([.fadeAlpha(to: 0.9, duration: 0.39), .fadeAlpha(to: 0.1, duration: 0.39)])
                pulse.timingMode = .easeInEaseOut
                node.glow.run(.repeatForever(pulse))
            }
        }
        if piece.isClearing && !node.isClearing {
            node.isClearing = true
            if skin.hardCuts {
                // Gone on the frame it clears
                node.isHidden = true
                return
            }
            // Flash, then shrink away over the clear time
            let flashTime = Game.clearTime * 0.3
            node.flash.run(.sequence([.fadeAlpha(to: 1, duration: 0), .fadeAlpha(to: 0.6, duration: flashTime)]))
            node.run(.sequence([.wait(forDuration: flashTime), .scale(to: 0, duration: Game.clearTime - flashTime)]))
        }
    }

    private func syncDials(_ game: some BoardState) {
        let vertices = game.dials
        for (player, dial) in dials where vertices[player] == nil {
            dial.removeFromParent()
            dials[player] = nil
        }
        for (player, vertex) in vertices {
            let dial = dials[player] ?? addDial(for: player)
            // On the menu, a dial reaching up into the logo stays out of sight
            dial.isHidden = hideAbove.map { Grid.position(of: vertex).x - 1 < $0 } ?? false
            guard vertex != dial.vertex else { continue }
            let target = point(Grid.position(of: vertex))
            if dial.vertex == nil {
                dial.position = target
            } else {
                dial.removeAction(forKey: "move")
                let move = SKAction.move(to: target, duration: 0.06)
                move.timingMode = .easeOut
                dial.run(move, withKey: "move")
            }
            dial.vertex = vertex
        }
    }

    private func addDial(for player: PlayerID) -> DialNode {
        let dial = DialNode()
        dial.zPosition = 10
        dial.fillColor = .clear
        dial.lineJoin = .miter
        dial.dot.strokeColor = .clear
        dial.addChild(dial.dot)
        styleDial(dial, for: player)
        content.addChild(dial)
        dials[player] = dial
        return dial
    }

    /// Ink outline; the dot is ink too, or a larger dot in the player's colour
    /// (ringed in ink, so it shows on triangles of the same colour).
    private func styleDial(_ dial: DialNode, for player: PlayerID) {
        dial.path = dialPath
        dial.lineWidth = weights.line
        dial.strokeColor = skin.ink.sk
        if let tint = dialTints[player] {
            dial.dot.fillColor = tint.sk
            dial.dot.strokeColor = skin.ink.sk
            dial.dot.setScale(max(pt(5), weights.line * 3))
            // The dot is a unit circle scaled up; keep its ring at the line weight
            dial.dot.lineWidth = weights.line / dial.dot.xScale
        } else {
            dial.dot.fillColor = skin.ink.sk
            dial.dot.strokeColor = .clear
            dial.dot.setScale(max(pt(2), weights.line))
        }
    }

    /// The hint is the dial's outline in ink, at the dial's weight but faint, so it
    /// reads as "a dial could go here" rather than a second dial.
    private func styleHint() {
        hintNode.path = dialPath
        hintNode.lineWidth = weights.line
        hintNode.strokeColor = skin.ink.sk
    }

    /// Show, move, or hide the hint, pulsing gently while it's up.
    private func syncHint() {
        hintNode.removeAllActions()
        guard let hint else {
            hintNode.isHidden = true
            return
        }
        hintNode.position = point(Grid.position(of: hint))
        hintNode.isHidden = false
        hintNode.alpha = 0
        let pulse = SKAction.sequence([.fadeAlpha(to: 0.7, duration: 0.6), .fadeAlpha(to: 0.2, duration: 0.6)])
        pulse.timingMode = .easeInEaseOut
        hintNode.run(.repeatForever(pulse))
    }

    // MARK: - Effects

    /// Burst of triangle confetti from each cleared hex, and a little shake.
    func showClear(_ hexes: [Hex]) {
        for hex in hexes {
            let emitter = SKEmitterNode()
            emitter.particleTexture = Self.confetti
            emitter.particleBirthRate = 2000
            emitter.numParticlesToEmit = 12
            emitter.particleLifetime = 0.5
            emitter.particleSpeed = 175
            emitter.particleSpeedRange = 150
            emitter.emissionAngleRange = 2 * .pi
            emitter.yAcceleration = -200
            emitter.particleScale = 0.55
            emitter.particleScaleRange = 0.4
            emitter.particleScaleSpeed = -1
            emitter.particleAlphaSpeed = -2
            emitter.particleRotationRange = 2 * .pi
            emitter.particleColor = skin.piece(hex.color).sk
            emitter.particleColorBlendFactor = 1
            emitter.position = point(Grid.position(of: hex.center))
            emitter.zPosition = 20
            // Its speeds and sizes are in phone points; Apple TV doubles them
            emitter.setScale(GameScene.uiScale)
            content.addChild(emitter)
            emitter.run(.sequence([.wait(forDuration: 1), .removeFromParent()]))
        }
        shake(duration: 0.2, intensity: pt(2))
    }

    /// Jiggle the whole board, fading out over `duration` seconds.
    func shake(duration: TimeInterval, intensity: CGFloat) {
        let rest = restPosition
        let jiggle = SKAction.customAction(withDuration: duration) { node, elapsed in
            // `elapsed` comes from a Float and can overshoot `duration` slightly,
            // which would make the range below invalid; clamp at zero.
            let falloff = max(0, intensity * (1 - elapsed / CGFloat(duration)))
            node.position = CGPoint(x: rest.x + .random(in: -falloff...falloff),
                                    y: rest.y + .random(in: -falloff...falloff))
        }
        // Never fight the glide between layouts
        guard action(forKey: "glide") == nil else { return }
        removeAction(forKey: "shake")
        run(.sequence([jiggle, .move(to: rest, duration: 0)]), withKey: "shake")
    }

    private static func makeConfettiTexture() -> SKTexture {
        let size = CGSize(width: 16, height: 16)
        let image = UIGraphicsImageRenderer(size: size).image { context in
            context.cgContext.setFillColor(UIColor.white.cgColor)
            context.cgContext.move(to: CGPoint(x: 8, y: 1))
            context.cgContext.addLine(to: CGPoint(x: 15, y: 14))
            context.cgContext.addLine(to: CGPoint(x: 1, y: 14))
            context.cgContext.closePath()
            context.cgContext.fillPath()
        }
        return SKTexture(image: image)
    }
}
