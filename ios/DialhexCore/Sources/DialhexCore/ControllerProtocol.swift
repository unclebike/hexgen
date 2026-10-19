// ControllerProtocol.swift — Messages between a phone used as a controller and the Apple TV
//
// The TV is the only authority: a phone sends what its player pressed, and the
// TV sends back only what the phone needs for its own screen and haptics, plus
// the six pieces under its player's dial (so the phone's spinner looks like
// the board), never the rest of the board. Both ends send these as JSON
// messages over one TCP connection, found through Bonjour.

public enum ControllerProtocol {
    /// Bumped whenever a message changes shape; the TV turns away other versions.
    public static let version = 2
    public static let serviceType = "_dialhex._tcp"
    /// Each end pings this often, and gives up on the other after `timeout` of silence.
    public static let heartbeatInterval: Duration = .seconds(1)
    public static let timeout: Duration = .seconds(3)
    public static let joinCodeLength = 4

    /// A fresh code for the TV to show, e.g. "0427".
    public static func makeJoinCode(using rng: inout some RandomNumberGenerator) -> String {
        String((0..<joinCodeLength).map { _ in Character(String(Int.random(in: 0...9, using: &rng))) })
    }

    /// Whether the TV lets a phone in, or why not.
    public static func admit(_ hello: Hello, joinCode: String) -> Rejection? {
        if hello.version != version { return .wrongVersion }
        if hello.joinCode != joinCode { return .wrongCode }
        return nil
    }
}

/// The phone introducing itself; always its first message.
public struct Hello: Codable, Sendable, Equatable {
    public var version: Int
    /// Random per launch, so a phone that reconnects can be told apart from a new one.
    public var peer: String
    /// Shown in the TV's lobby.
    public var name: String
    public var joinCode: String

    public init(version: Int = ControllerProtocol.version, peer: String, name: String, joinCode: String) {
        self.version = version
        self.peer = peer
        self.name = name
        self.joinCode = joinCode
    }
}

/// Phone to TV.
public enum PhoneMessage: Codable, Sendable, Equatable {
    case hello(Hello)
    /// A direction went down or came up. The TV runs the auto-repeat, the same as for gamepads.
    case direction(Direction, pressed: Bool)
    /// Put the dial on a vertex: the phone's mini bin, dragged across.
    case place(Vertex)
    case rotate(RotationDirection)
    case confirm
    case cancel
    case pause
    case ping(UInt64)
    case bye
}

/// TV to phone.
public enum TVMessage: Codable, Sendable, Equatable {
    case welcome(PlayerID)
    case rejected(Rejection)
    case screen(RemoteScreen)
    case haptic(RemoteHaptic)
    /// Where this phone's player's dial is and what's under it; sent whenever either changes.
    case dial(DialPieces)
    case pong(UInt64)
}

/// A dial as the player sees it on the TV: where it is, and the six triangles under it.
public struct DialPieces: Codable, Sendable, Equatable {
    /// Where the dial is; nil when there's no board (the lobby).
    public var vertex: Vertex?
    /// Each triangle's piece colour (nil: empty), counter-clockwise on screen
    /// starting with the one to the right of the dial's centre. On screen the dial
    /// stands on a corner, so these sit at 0°, 60°, … 300°.
    public var colors: [Int?]

    public init(vertex: Vertex? = nil, colors: [Int?]) {
        self.vertex = vertex
        self.colors = colors
    }

    public static let empty = DialPieces(colors: Array(repeating: nil, count: 6))

    /// The dial's cells in that order. Screen x is −(lattice y) and screen y (up) is −(lattice x).
    public static func screenOrder(_ vertex: Vertex) -> [Cell] {
        let center = Grid.position(of: vertex)
        // Each triangle's centre lies exactly toward one of the six slots; take the closest
        let h = 3.0.squareRoot() / 2
        let slots: [(x: Double, y: Double)] = [(1, 0), (0.5, h), (-0.5, h), (-1, 0), (-0.5, -h), (0.5, -h)]
        func slot(_ cell: Cell) -> Int {
            let d = Grid.center(of: cell) - center
            let (x, y) = (-d.y, -d.x)
            return slots.indices.max { slots[$0].x * x + slots[$0].y * y < slots[$1].x * x + slots[$1].y * y }!
        }
        return Grid.dialCells(vertex).sorted { slot($0) < slot($1) }
    }

    /// What's under the dial at `vertex`. Pieces on their way out count as empty.
    public static func at(_ vertex: Vertex, on board: Board) -> DialPieces {
        DialPieces(vertex: vertex, colors: screenOrder(vertex).map { cell in
            board[cell].flatMap { $0.isClearing ? nil : $0.color }
        })
    }

    /// The same pieces after a turn, for the phone to show it before the TV's word arrives.
    public func turned(_ direction: RotationDirection) -> DialPieces {
        let n = colors.count
        guard n > 0 else { return self }
        // Clockwise on screen moves each piece one slot down the counter-clockwise order
        let step = direction == .clockwise ? 1 : n - 1
        return DialPieces(vertex: vertex, colors: (0..<n).map { colors[($0 + step) % n] })
    }
}

public enum Rejection: String, Codable, Sendable, Equatable, Error {
    case wrongVersion, wrongCode, full, matchRunning
}

/// What the phone's controller screen should show.
public enum RemoteScreen: Codable, Sendable, Equatable {
    /// The TV's main menu: the phone steers it like a remote.
    case menu
    case lobby
    case playing
    case paused
    case over(won: Bool)
}

/// The haptics a phone plays for its own player's events.
public enum RemoteHaptic: Codable, Sendable, Equatable {
    case rotate
    case clear(hexes: Int)
    case power
    case levelUp
    case gameOver
}

// Direction is declared without a raw value, so it's coded by hand here (by name).
extension Direction: Codable {
    public init(from decoder: any Decoder) throws {
        let name = try decoder.singleValueContainer().decode(String.self)
        switch name {
        case "up": self = .up
        case "down": self = .down
        case "left": self = .left
        case "right": self = .right
        default:
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "unknown direction \(name)"))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .up: try container.encode("up")
        case .down: try container.encode("down")
        case .left: try container.encode("left")
        case .right: try container.encode("right")
        }
    }
}

extension RotationDirection: Codable {}
