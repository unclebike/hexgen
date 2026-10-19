// IconRenderer.swift — Draws the app icon from the game's own shapes and colours
//
// Built by render.sh together with the app's Marks.swift and DialhexCore's
// Grid.swift, so the triangles and their marks are exactly the ones in play.
// Colours, marks, and line weights come from skins.json (the base skin).
//
// The picture is one dial, as on the board: six triangles of different
// colours, each with its mark, held in the dial outline with its centre dot,
// over the board's faint lattice.
//
// It draws at any size, for the Apple TV's wide icons and Top Shelf images,
// and can draw just one layer of the TV's parallax icon: the background and
// lattice ("back"), or the dial alone on transparency ("front").

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

// MARK: - Stand-ins for the app types Marks.swift refers to

enum Mark: String {
    case dot, spokes, ring, frame, trio, corners, tri, target
}

/// Marks.logo() reads the logo from the brand tokens; the icon doesn't draw it.
struct StubLogo {
    let word = ""
    let lines: [String]? = nil
    let gap = 0
    let lineGap = 0
    let glyphs: [String: [String]] = [:]
}

enum Brand {
    struct Tokens { let logo = StubLogo() }
    static let tokens = Tokens()
}

// MARK: - Tokens

struct RGB {
    let r, g, b: Double

    init(_ hex: String) {
        let v = UInt32(hex.dropFirst(), radix: 16) ?? 0
        r = Double((v >> 16) & 0xFF) / 255
        g = Double((v >> 8) & 0xFF) / 255
        b = Double(v & 0xFF) / 255
    }

    var cg: CGColor { CGColor(srgbRed: r, green: g, blue: b, alpha: 1) }
    func cg(_ alpha: Double) -> CGColor { CGColor(srgbRed: r, green: g, blue: b, alpha: alpha) }

    /// WCAG relative luminance, as Brand.swift computes it.
    var luminance: Double {
        let linear = [r, g, b].map { $0 <= 0.04045 ? $0 / 12.92 : pow(($0 + 0.055) / 1.055, 2.4) }
        return 0.2126 * linear[0] + 0.7152 * linear[1] + 0.0722 * linear[2]
    }

    func contrast(with other: RGB) -> Double {
        let (a, b) = (luminance, other.luminance)
        return (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }
}

enum Layer: String {
    case all, back, front
}

let arguments = CommandLine.arguments
guard [3, 5, 6].contains(arguments.count),
      let width = Double(arguments.count > 3 ? arguments[3] : "1024"),
      let height = Double(arguments.count > 4 ? arguments[4] : "1024"),
      let layer = Layer(rawValue: arguments.count > 5 ? arguments[5] : "all") else {
    print("usage: IconRenderer <skins.json> <output.png> [width height [all|back|front]]")
    exit(1)
}
let json = try JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: arguments[1]))) as! [String: Any]
let weights = json["weights"] as! [String: Double]
let marks = (json["marks"] as! [String]).compactMap(Mark.init(rawValue:))
let skin = (json["skins"] as! [[String: Any]])[0]
let background = RGB(skin["background"] as! String)
let ink = RGB(skin["ink"] as! String)
let markInk = RGB(skin["mark"] as! String)
let pieces = (skin["pieces"] as! [String]).map(RGB.init)

/// Whichever of the skin's mark colour and ink stands out more, as in the game.
func markColor(on piece: RGB) -> RGB {
    piece.contrast(with: markInk) >= piece.contrast(with: ink) ? markInk : ink
}

// MARK: - Drawing

let center = CGPoint(x: width / 2, y: height / 2)
/// Triangle side, in pixels: the dial is 2·side tall, about two thirds of the shorter edge.
let side = 350.0 / 1024 * min(width, height)
let line = side * weights["line"]!
let heavy = side * weights["heavy"]!
/// The six colours round the dial, clockwise from the top right; warm and cool alternate.
/// Cream and grey sit out: cream reads as ink, and grey is the quiet eighth colour.
let dialColors = [0, 1, 2, 4, 6, 5]

// Only the front layer has transparency; the others are opaque, as icons must be
let context = CGContext(data: nil, width: Int(width), height: Int(height), bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: (layer == .front ? CGImageAlphaInfo.premultipliedLast : .noneSkipLast).rawValue)!
// y down, like the game
context.translateBy(x: 0, y: height)
context.scaleBy(x: 1, y: -1)

if layer != .front {
    context.setFillColor(background.cg)
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))

    // The board's lattice, at its hairline alpha: vertical lines and lines at ±30°,
    // spaced so the dial's triangles sit on it. Thicker than the game's hairline, to survive shrinking.
    let rowHeight = side * Grid.rowHeight
    let slope = tan(Double.pi / 6)
    // Enough lines to reach the edges (at least the square icon's ±8)
    let columns = max(8, Int((center.x / rowHeight).rounded(.up)))
    let rows = max(8, Int(((center.y + slope * center.x) / side).rounded(.up)))
    context.setStrokeColor(ink.cg(weights["hairlineAlpha"]!))
    context.setLineWidth(max(1, side * 3 / 350))
    for k in -columns...columns {
        let x = center.x + Double(k) * rowHeight
        context.move(to: CGPoint(x: x, y: 0))
        context.addLine(to: CGPoint(x: x, y: height))
    }
    for k in -rows...rows {
        // Lines through the dial's vertices, one triangle-side apart vertically
        let y0 = center.y + Double(k) * side
        for s in [slope, -slope] {
            context.move(to: CGPoint(x: 0, y: y0 - s * center.x))
            context.addLine(to: CGPoint(x: width, y: y0 + s * (width - center.x)))
        }
    }
    context.strokePath()
}

// The dial: pointy-top, as the board shows it
let corners = (0..<6).map { i -> CGPoint in
    let a = -Double.pi / 2 + Double(i) * .pi / 3
    return CGPoint(x: center.x + cos(a) * side, y: center.y + sin(a) * side)
}

// Knock the lattice out behind the dial, as the bin's fill does in play.
// The back layer stops here: on the TV the dial floats over it.
context.setFillColor(background.cg)
context.addPath(Marks.polygon(corners))
context.fillPath()

for i in 0..<6 where layer != .back {
    let triangle = Marks.scaled([center, corners[i], corners[(i + 1) % 6]], by: 0.9)
    let color = dialColors[i]
    let fill = pieces[color]
    context.setFillColor(fill.cg)
    context.addPath(Marks.polygon(triangle))
    context.fillPath()
    context.setFillColor(markColor(on: fill).cg)
    context.addPath(Marks.path(marks[color], corners: triangle, lineWidth: line))
    context.fillPath()
}

// The dial outline the player holds, and its centre dot
if layer != .back {
    context.setStrokeColor(ink.cg)
    context.setLineWidth(line)
    context.setLineJoin(.miter)
    context.addPath(Marks.polygon(corners))
    context.strokePath()
    context.setFillColor(ink.cg)
    context.fillEllipse(in: CGRect(x: center.x - heavy * 0.75, y: center.y - heavy * 0.75, width: heavy * 1.5, height: heavy * 1.5))
}

let image = context.makeImage()!
let url = URL(fileURLWithPath: arguments[2])
let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(destination, image, nil)
guard CGImageDestinationFinalize(destination) else {
    print("couldn't write \(url.path)")
    exit(1)
}
print("wrote \(url.path)")
