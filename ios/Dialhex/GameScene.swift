// GameScene.swift — SpriteKit drawing: the bin, falling triangles, the dial, and effects
//
// Positions follow the game clock every frame (so pausing freezes them);
// one-shot effects — clear flashes, confetti, shake — are SKActions.

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

/// One triangle on the board.
private final class PieceNode: SKShapeNode {
    var colorIndex = -1
    var pointsUp: Bool?
    var isClearing = false
    let flash = SKShapeNode()
    let glow = SKShapeNode()
}

final class GameScene: SKScene {
    weak var model: AppModel?

    private static let topMargin: CGFloat = 72     // room for the score line
    private static let bottomMargin: CGFloat = 100 // room for the rotate buttons
    private static let pieceInset: CGFloat = 0.9   // leave a hairline gap between triangles

    /// Holds everything that shakes; centred on the bin.
    private let world = SKNode()
    private let board = SKNode()
    private let bin = SKShapeNode()
    private let lattice = SKShapeNode()
    private let cursor = SKShapeNode()
    private var pieces: [Int: PieceNode] = [:]
    private var scale: CGFloat = 30 // points per triangle side
    private var lastUpdate: TimeInterval = 0
    private var cursorVertex: Vertex?
    /// Where `world` sits when it isn't shaking.
    private var restPosition = CGPoint.zero
    private weak var gestureView: SKView?
    private lazy var confetti = makeConfettiTexture()

    override init() {
        super.init(size: CGSize(width: 390, height: 844))
        scaleMode = .resizeFill
        backgroundColor = SKColor(rgb: Palette.background)
        anchorPoint = .zero

        addChild(world)
        world.addChild(board)
        bin.fillColor = SKColor(rgb: Palette.empty)
        bin.strokeColor = .clear
        board.addChild(bin)
        lattice.strokeColor = SKColor(white: 1, alpha: 0.06)
        lattice.lineWidth = 1
        board.addChild(lattice)
        cursor.zPosition = 10
        cursor.fillColor = SKColor(white: 1, alpha: 0.08)
        cursor.strokeColor = SKColor(white: 1, alpha: 0.85)
        cursor.lineWidth = 2.5
        cursor.lineJoin = .round
        let dot = SKShapeNode(circleOfRadius: 1)
        dot.name = "dot"
        dot.fillColor = .white
        dot.strokeColor = .clear
        cursor.addChild(dot)
        board.addChild(cursor)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    // MARK: - Layout

    /// Lattice x runs down the screen and lattice y runs right to left.
    private func point(_ p: LatticePoint) -> CGPoint {
        CGPoint(x: -p.y * scale, y: -p.x * scale)
    }

    private func path(_ points: [LatticePoint]) -> CGPath {
        let path = CGMutablePath()
        path.addLines(between: points.map(point))
        path.closeSubpath()
        return path
    }

    override func didChangeSize(_ oldSize: CGSize) {
        super.didChangeSize(oldSize)
        // The bin stands on a vertex: it is 2·size·rowHeight wide and 2·size tall on screen
        let n = CGFloat(Grid.size)
        let availableHeight = max(100, size.height - Self.topMargin - Self.bottomMargin)
        scale = min(size.width * 0.94 / (2 * n * Grid.rowHeight), availableHeight / (2 * n))
        restPosition = CGPoint(x: size.width / 2, y: Self.bottomMargin + availableHeight / 2)
        world.removeAction(forKey: "shake")
        world.position = restPosition

        bin.path = path(Grid.binOutline)
        let grid = CGMutablePath()
        for cell in Grid.cells { grid.addPath(path(Grid.vertices(of: cell))) }
        lattice.path = grid

        // The dial outline is the same around every vertex, so draw it about the origin
        let origin = Grid.position(of: Grid.dials[0])
        cursor.path = path(Grid.dialOutline(Grid.dials[0]).map { $0 - origin })
        cursor.childNode(withName: "dot")?.setScale(max(2.5, scale * 0.08))
        cursorVertex = nil

        // Piece shapes depend on the scale; rebuild them on the next frame
        for node in pieces.values { node.pointsUp = nil }
    }

    // MARK: - Input

    override func didMove(to view: SKView) {
        super.didMove(to: view)
        guard gestureView !== view else { return }
        gestureView = view
        view.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(tapped)))
        let twist = UIRotationGestureRecognizer(target: self, action: #selector(twisted))
        view.addGestureRecognizer(twist)
    }

    /// Board point under a view location, in lattice units.
    private func latticePoint(fromView location: CGPoint) -> LatticePoint {
        let p = convertPoint(fromView: location)
        let local = board.convert(p, from: self)
        return LatticePoint(-local.y / scale, -local.x / scale)
    }

    @objc private func tapped(_ recognizer: UITapGestureRecognizer) {
        guard let view = recognizer.view else { return }
        let point = latticePoint(fromView: recognizer.location(in: view))
        MainActor.assumeIsolated { model?.tap(at: point) }
    }

    /// Two-finger twist turns the dial, one step per 30°.
    @objc private func twisted(_ recognizer: UIRotationGestureRecognizer) {
        guard recognizer.state == .changed, abs(recognizer.rotation) > .pi / 6 else { return }
        let direction: RotationDirection = recognizer.rotation > 0 ? .clockwise : .counterClockwise
        recognizer.rotation = 0
        MainActor.assumeIsolated { model?.rotate(direction) }
    }

    // MARK: - Frame

    override func update(_ currentTime: TimeInterval) {
        let dt = lastUpdate > 0 ? min(currentTime - lastUpdate, 0.05) : 1.0 / 60
        lastUpdate = currentTime
        MainActor.assumeIsolated {
            guard let model else { return }
            model.tick(dt)
            guard let game = model.game else { return }
            board.isPaused = game.phase != .playing
            if !board.isPaused { syncPieces(game) }
            syncCursor(game)
        }
    }

    /// Clear every piece and effect, for a new game or the menu.
    func reset() {
        for node in pieces.values { node.removeFromParent() }
        pieces.removeAll()
        board.children.filter { $0 is SKEmitterNode }.forEach { $0.removeFromParent() }
        world.removeAllActions()
        world.position = restPosition
        board.isPaused = false
        cursorVertex = nil
        lastUpdate = 0
    }

    private func syncPieces(_ game: Game) {
        let fall = game.fallProgress

        // The board already holds the turned dial; draw those six triangles
        // rotated back by the part of the 60° turn that hasn't played yet.
        var turning: Set<Cell> = []
        var pivot = CGPoint.zero
        var angle: CGFloat = 0
        if let turn = game.dialTurn {
            turning = Set(Grid.dialCells(turn.vertex))
            pivot = point(Grid.position(of: turn.vertex))
            let t = min(1, turn.elapsed / Game.rotateTime)
            let easeOut = 1 - (1 - t) * (1 - t)
            // SpriteKit angles are counter-clockwise; undo a clockwise turn
            angle = CGFloat(turn.direction.rawValue) * .pi / 3 * (1 - easeOut)
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
            if turning.contains(cell) {
                let offset = CGPoint(x: position.x - pivot.x, y: position.y - pivot.y)
                    .applying(CGAffineTransform(rotationAngle: angle))
                position = CGPoint(x: pivot.x + offset.x, y: pivot.y + offset.y)
                node.zRotation = angle
            }
            node.position = position
        }

        for (id, node) in pieces where !seen.contains(id) {
            node.removeFromParent()
            pieces[id] = nil
        }
    }

    private func addPiece(_ piece: Piece) -> PieceNode {
        let node = PieceNode()
        node.strokeColor = .clear
        node.flash.fillColor = .white
        node.flash.strokeColor = .clear
        node.flash.alpha = 0
        node.addChild(node.flash)
        node.glow.fillColor = .clear
        node.glow.strokeColor = .white
        node.glow.lineWidth = 2.5
        node.glow.lineJoin = .round
        node.glow.isHidden = true
        node.addChild(node.glow)
        board.addChild(node)
        pieces[piece.id] = node
        return node
    }

    /// Match a node's shape, colour, and power glow to its piece.
    private func update(_ node: PieceNode, _ piece: Piece, at cell: Cell) {
        let up = Grid.isUp(cell)
        if node.pointsUp != up {
            node.pointsUp = up
            let center = Grid.center(of: cell)
            let shape = path(Grid.vertices(of: cell).map { ($0 - center) * Double(Self.pieceInset) })
            node.path = shape
            node.flash.path = shape
            node.glow.path = shape
        }
        if node.colorIndex != piece.color {
            node.colorIndex = piece.color
            node.fillColor = SKColor(rgb: Palette.colors[piece.color])
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
            // Flash white, then shrink away over the clear time
            node.isClearing = true
            let flashTime = Game.clearTime * 0.3
            node.flash.run(.sequence([.fadeAlpha(to: 1, duration: 0), .fadeAlpha(to: 0.6, duration: flashTime)]))
            node.run(.sequence([.wait(forDuration: flashTime), .scale(to: 0, duration: Game.clearTime - flashTime)]))
        }
    }

    private func syncCursor(_ game: Game) {
        let vertex = game.cursor.vertex
        guard vertex != cursorVertex else { return }
        let target = point(Grid.position(of: vertex))
        if cursorVertex == nil {
            cursor.position = target
        } else {
            cursor.removeAction(forKey: "move")
            let move = SKAction.move(to: target, duration: 0.06)
            move.timingMode = .easeOut
            cursor.run(move, withKey: "move")
        }
        cursorVertex = vertex
    }

    // MARK: - Effects

    /// Burst of triangle confetti from each cleared hex, and a little shake.
    func showClear(_ hexes: [Hex]) {
        for hex in hexes {
            let emitter = SKEmitterNode()
            emitter.particleTexture = confetti
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
            emitter.particleColor = SKColor(rgb: Palette.colors[hex.color])
            emitter.particleColorBlendFactor = 1
            emitter.position = point(Grid.position(of: hex.center))
            emitter.zPosition = 20
            board.addChild(emitter)
            emitter.run(.sequence([.wait(forDuration: 1), .removeFromParent()]))
        }
        shake(duration: 0.2, intensity: 2)
    }

    /// Jiggle the whole board, fading out over `duration` seconds.
    func shake(duration: TimeInterval, intensity: CGFloat) {
        let rest = restPosition
        let jiggle = SKAction.customAction(withDuration: duration) { node, elapsed in
            let falloff = intensity * (1 - elapsed / CGFloat(duration))
            node.position = CGPoint(x: rest.x + .random(in: -falloff...falloff),
                                    y: rest.y + .random(in: -falloff...falloff))
        }
        world.removeAction(forKey: "shake")
        world.run(.sequence([jiggle, .move(to: rest, duration: 0)]), withKey: "shake")
    }

    /// A small white triangle, tinted per burst.
    private func makeConfettiTexture() -> SKTexture {
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
