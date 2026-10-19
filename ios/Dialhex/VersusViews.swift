// VersusViews.swift — The lobby and the overlay around the players' bins (versus) or shared bin (co-op)
//
// Both sit over the SpriteKit scene in the same skin as the rest of the app:
// one ink colour for text and lines, colour only on the players' swatches.

import DialhexCore
import SwiftUI

/// Players join here before a match: one slot per player, what to play (a versus rule or co-op), and how phones join.
struct LobbyView: View {
    let model: AppModel
    let weights: LineWeights

    var body: some View {
        if let link = model.lobby?.online {
            onlineLobby(link)
        } else {
            localLobby
        }
    }

    @ViewBuilder private var localLobby: some View {
        let skin = model.skin
        let copy = Brand.copy.versus
        let lobby = model.lobby ?? Lobby()
        let rule = copy.kind(lobby.kind)
        ZStack {
            skin.background.color.opacity(0.75).ignoresSafeArea()
            VStack(spacing: pt(18)) {
                Text(copy.title)
                    .font(skin.font(.display, 32))
                    .foregroundStyle(skin.ink.color)
                    .accessibilityAddTraits(.isHeader)
                // The rule, changed with left and right
                HStack(spacing: pt(16)) {
                    SideArrow(pointsRight: false).frame(width: pt(10), height: pt(12))
                    VStack(spacing: pt(4)) {
                        TrackedLabel(text: rule.label, size: 17, skin: skin)
                        Text(rule.detail).font(skin.font(.text, 11)).foregroundStyle(skin.ink.color(secondary))
                    }
                    .frame(width: pt(220))
                    SideArrow(pointsRight: true).frame(width: pt(10), height: pt(12))
                }
                .foregroundStyle(skin.ink.color)
                HStack(spacing: pt(14)) {
                    ForEach(PlayerID.all, id: \.self) { player in
                        slot(player, in: lobby)
                    }
                }
                VStack(spacing: pt(6)) {
                    if lobby.roster.players.count < lobby.kind.playerRange.lowerBound {
                        Text(copy.needTwo)
                    } else if lobby.roster.players.count > lobby.kind.playerRange.upperBound {
                        Text(copy.coopTwoOnly)
                    }
                    Text(Brand.copy.fill(copy.lobbyHint, for: model.inputKind))
                    if let code = model.joinCode {
                        Text(copy.phoneHint.replacingOccurrences(of: "%@", with: code))
                    }
                }
                .font(skin.font(.text, 11))
                .foregroundStyle(skin.ink.color(secondary))
                .multilineTextAlignment(.center)
            }
            .padding(pt(24))
        }
    }

    /// Online co-op: you and a Game Center friend. The host picks the mode,
    /// invites, and starts; the guest waits for them.
    private func onlineLobby(_ link: OnlineLink) -> some View {
        let skin = model.skin
        let copy = Brand.copy.online
        let lobby = model.lobby ?? Lobby()
        let mode = Brand.copy.versus.kind(lobby.kind)
        let hosts = link != .inviting && !model.isOnlineGuest
        let isHost = !model.isOnlineGuest
        return ZStack {
            skin.background.color.opacity(0.75).ignoresSafeArea()
            VStack(spacing: pt(18)) {
                Text(copy.title)
                    .font(skin.font(.display, 32))
                    .foregroundStyle(skin.ink.color)
                    .accessibilityAddTraits(.isHeader)
                // The mode: the host changes it with left and right (or the arrows, by touch)
                HStack(spacing: pt(16)) {
                    arrow(pointsRight: false, shown: isHost)
                    VStack(spacing: pt(4)) {
                        TrackedLabel(text: mode.label, size: 17, skin: skin)
                        Text(mode.detail).font(skin.font(.text, 11)).foregroundStyle(skin.ink.color(secondary))
                    }
                    .frame(width: pt(220))
                    arrow(pointsRight: true, shown: isHost)
                }
                .foregroundStyle(skin.ink.color)
                HStack(spacing: pt(14)) {
                    ForEach(CoopGame.players, id: \.self) { player in
                        slot(player, in: lobby, empty: copy.friend)
                    }
                }
                VStack(spacing: pt(6)) {
                    switch link {
                    case .inviting: hint(copy.inviteHint)
                    case .hosting: hint(copy.hostHint)
                    case .joining(let host):
                        Text(copy.waiting.replacingOccurrences(of: "%@", with: host))
                        hint(copy.guestHint)
                    }
                }
                .font(skin.font(.text, 11))
                .foregroundStyle(skin.ink.color(secondary))
                .multilineTextAlignment(.center)
                #if os(iOS)
                HStack(spacing: pt(10)) {
                    if isHost {
                        TouchButton(model: model, weights: weights, label: hosts ? copy.start : copy.invite, action: .confirm)
                    }
                    TouchButton(model: model, weights: weights, label: copy.leave, action: .cancel)
                }
                #endif
            }
            .padding(pt(24))
        }
    }

    /// The mode picker's arrow: a button by touch, only for the host.
    @ViewBuilder
    private func arrow(pointsRight: Bool, shown: Bool) -> some View {
        if shown {
            Button {
                model.handleOnline(.move(pointsRight ? .right : .left))
            } label: {
                SideArrow(pointsRight: pointsRight).frame(width: pt(10), height: pt(12))
                    .padding(pt(10))
                    .contentShape(Rectangle())
            }
            .plainButton()
            .accessibilityLabel(pointsRight ? "Next mode" : "Previous mode")
        } else {
            Color.clear.frame(width: pt(30), height: pt(32))
        }
    }

    private func hint(_ text: String) -> Text {
        Text(Brand.copy.fill(text, for: model.inputKind))
    }

    private func slot(_ player: PlayerID, in lobby: Lobby, empty: String? = nil) -> some View {
        let skin = model.skin
        let copy = Brand.copy.versus
        let seated = lobby.source(of: player) != nil
        return ButtonFace(skin: skin, weights: weights, selected: seated, width: pt(130), height: pt(96)) {
            VStack(spacing: pt(6)) {
                HStack(spacing: pt(6)) {
                    if seated { PlayerSwatch(color: model.playerColor(player)) }
                    TrackedLabel(text: player.description, size: 22, skin: skin)
                }
                Text(seated ? lobby.name(of: player) ?? copy.ready : empty ?? Brand.copy.fill(copy.join, for: model.inputKind))
                    .font(skin.font(.text, 10))
                    .foregroundStyle(skin.ink.color(seated ? 1 : secondary))
                    .lineLimit(1)
                    .padding(.horizontal, pt(6))
            }
        }
        .opacity(seated ? 1 : 0.7)
        .accessibilityElement(children: .combine)
    }
}

/// The match line across the top, each player's line over their bin, and the
/// pause and results cards.
struct VersusHUDView: View {
    let model: AppModel
    let weights: LineWeights
    let size: CGSize

    var body: some View {
        let hud = model.versusHUD
        ZStack(alignment: .topLeading) {
            matchLine(hud)
                .frame(width: size.width, height: GameScene.versusTopBand)
            #if os(iOS)
            // Online by touch: a way to pause, since there's no button for it
            if online && hud.phase == .playing {
                Button { model.handleOnline(.pause) } label: {
                    Image(systemName: "pause")
                        .font(.system(size: pt(18), weight: .regular))
                        .foregroundStyle(skin.ink.color)
                        .frame(width: pt(44), height: GameScene.versusTopBand)
                        .contentShape(Rectangle())
                }
                .plainButton()
                .accessibilityLabel(Brand.copy.paused)
                .frame(width: size.width - pt(8), alignment: .trailing)
            }
            #endif
            if hud.kind.isCoop {
                coopLines(hud)
                #if os(iOS)
                coopSpinner(hud)
                #endif
            } else {
                versusLines(hud)
            }
            if hud.phase != .playing {
                card(hud)
                    .frame(width: size.width, height: size.height)
            }
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
    }

    /// Each player's line over their own bin.
    private func versusLines(_ hud: VersusHUD) -> some View {
        let frames = GameScene.versusFrames(for: size, players: hud.boards.count)
        return ForEach(Array(zip(hud.boards, frames)), id: \.0.player) { board, frame in
            playerLine(board)
                .frame(width: frame.width, height: GameScene.versusLabelBand)
                .position(x: frame.midX, y: frame.minY - GameScene.versusLabelBand / 2)
            if board.out || board.dropped {
                Text(board.dropped ? Brand.copy.versus.dropped : Brand.copy.versus.out)
                    .font(skin.font(.display, 24))
                    .foregroundStyle(skin.ink.color)
                    .position(x: frame.midX, y: frame.midY)
            }
        }
    }

    /// Both players over the shared bin, P1 on the left like their dial, with the team's score between.
    @ViewBuilder
    private func coopLines(_ hud: VersusHUD) -> some View {
        let frame = GameScene.coopFrames(for: size, spinner: online, spinnerOnLeft: model.leftHanded).bin
        let skin = model.skin
        HStack(spacing: pt(14)) {
            ForEach(hud.boards, id: \.player) { board in
                HStack(spacing: pt(6)) {
                    PlayerSwatch(color: model.playerColor(board.player))
                    TrackedLabel(text: board.player.description, size: 15, skin: skin)
                    if board.dropped {
                        Text(Brand.copy.versus.dropped).font(skin.font(.text, 10)).foregroundStyle(skin.ink.color)
                    } else if let name = board.name {
                        Text(name)
                            .font(skin.font(.text, 10))
                            .foregroundStyle(skin.ink.color(secondary))
                            .lineLimit(1)
                    }
                }
                .opacity(board.out ? 0.5 : 1)
                .accessibilityElement(children: .combine)
                if board.player == hud.boards.first?.player {
                    Spacer(minLength: pt(4))
                    Text("\(hud.boards.first?.score ?? 0)")
                        .font(skin.font(.digits, 15))
                        .foregroundStyle(skin.ink.color)
                        .monospacedDigit()
                    Spacer(minLength: pt(4))
                }
            }
        }
        .frame(width: frame.width, height: GameScene.versusLabelBand)
        .position(x: frame.midX, y: frame.minY - GameScene.versusLabelBand / 2)
    }

    private func matchLine(_ hud: VersusHUD) -> some View {
        let skin = model.skin
        return HStack(spacing: pt(14)) {
            TrackedLabel(text: Brand.copy.versus.kind(hud.kind).label, size: 13, skin: skin)
            if let seconds = hud.sprintSeconds {
                Text(String(format: "%d:%02d", seconds / 60, seconds % 60))
                    .font(skin.font(.digits, 15))
                    .foregroundStyle(skin.ink.color)
                    .monospacedDigit()
            }
        }
    }

    private func playerLine(_ board: VersusHUD.Board) -> some View {
        let skin = model.skin
        return HStack(spacing: pt(6)) {
            PlayerSwatch(color: model.playerColor(board.player))
            TrackedLabel(text: board.player.description, size: 15, skin: skin)
            if let name = board.name {
                Text(name)
                    .font(skin.font(.text, 10))
                    .foregroundStyle(skin.ink.color(secondary))
                    .lineLimit(1)
            }
            Spacer(minLength: pt(4))
            Text("\(board.score)")
                .font(skin.font(.digits, 15))
                .foregroundStyle(skin.ink.color)
                .monospacedDigit()
        }
        .opacity(board.out ? 0.5 : 1)
        .accessibilityElement(children: .combine)
    }

    /// Paused, someone's controller lost, or the result.
    private func card(_ hud: VersusHUD) -> some View {
        let skin = model.skin
        let copy = Brand.copy.versus
        let dropped = hud.boards.filter(\.dropped).map(\.player.description)
        return VStack(spacing: pt(10)) {
            if hud.phase == .gameOver {
                Text(result(hud))
                    .font(skin.font(.display, 32))
                    .foregroundStyle(skin.ink.color)
                ForEach(hud.unlocked, id: \.self) { id in
                    Text(Brand.copy.unlocked(id)).font(skin.font(.text, 13)).foregroundStyle(skin.ink.color)
                }
                if online {
                    onlineControls(again: true)
                } else {
                    hint(copy.matchOver)
                }
            } else if !dropped.isEmpty {
                Text(copy.lost.replacingOccurrences(of: "%@", with: dropped.joined(separator: ", ")))
                    .font(skin.font(.display, 20))
                    .foregroundStyle(skin.ink.color)
                hint(copy.lostHint)
            } else {
                Text(Brand.copy.paused).font(skin.font(.display, 32)).foregroundStyle(skin.ink.color)
                if online {
                    onlineControls(again: false)
                } else {
                    hint(copy.pausedHint)
                }
            }
        }
        .padding(.horizontal, pt(28))
        .padding(.vertical, pt(20))
        .background(skin.empty.color)
        .overlay(Rectangle().strokeBorder(skin.ink.color, style: sharp(weights.heavy)))
    }

    /// This match is online co-op.
    private var online: Bool { model.lobby?.online != nil }

    #if os(iOS)
    /// Online co-op: your dial as a spinner beside the shared bin, as in a solo game.
    /// It shows the six pieces under your dial, ringed dot in your colour, and turns
    /// as it's spun (either way) or tapped (forward).
    @ViewBuilder
    private func coopSpinner(_ hud: VersusHUD) -> some View {
        if online, hud.phase == .playing, let dial = hud.dial,
           let frame = GameScene.coopFrames(for: size, spinner: true, spinnerOnLeft: model.leftHanded).spinner {
            // In portrait the spinner pulls its drawing in to keep its outline whole; give it that back
            let grow: CGFloat = GameScene.isLandscape(size) ? 1 : 1 + CGFloat(Brand.tokens.weights.line) * 0.6
            let side = frame.height * grow
            DialSpinner(skin: skin, weights: weights, dial: dial, tint: model.playerColor(model.onlinePlayer)) {
                model.rotate($0, from: .corner)
            }
            .frame(width: side, height: side)
            .position(x: frame.midX, y: frame.midY)
        }
    }
    #endif

    /// Online, paused or over: the buttons to name, or by touch, the buttons themselves.
    @ViewBuilder
    private func onlineControls(again: Bool) -> some View {
        let copy = Brand.copy.online
        #if os(iOS)
        HStack(spacing: pt(10)) {
            TouchButton(model: model, weights: weights, label: again ? copy.again : copy.resume, action: .confirm)
            TouchButton(model: model, weights: weights, label: copy.leave, action: .cancel)
        }
        .padding(.top, pt(4))
        #else
        hint(again ? copy.matchOver : copy.pausedHint)
        #endif
    }

    /// A line naming buttons, in the current input's names.
    private func hint(_ text: String) -> some View {
        Text(Brand.copy.fill(text, for: model.inputKind))
            .font(skin.font(.text, 11))
            .foregroundStyle(model.skin.ink.color(secondary))
            .multilineTextAlignment(.center)
    }

    private var skin: Skin { model.skin }

    private func result(_ hud: VersusHUD) -> String {
        let copy = Brand.copy.versus
        if hud.kind.isCoop {
            return hud.won ? copy.coopWon : copy.coopOver.replacingOccurrences(of: "%@", with: "\(hud.boards.first?.score ?? 0)")
        }
        let winners = (hud.winners ?? []).map(\.description)
        if winners.count == 1 { return copy.wins.replacingOccurrences(of: "%@", with: winners[0]) }
        return copy.tie.replacingOccurrences(of: "%@", with: winners.joined(separator: ", "))
    }
}

/// A short labelled button for online co-op by touch; it does what a controller's button would.
private struct TouchButton: View {
    let model: AppModel
    let weights: LineWeights
    let label: String
    let action: ControlAction

    var body: some View {
        Button { model.handleOnline(action) } label: {
            ButtonFace(skin: model.skin, weights: weights, selected: action == .confirm, width: pt(120), height: pt(44)) {
                TrackedLabel(text: label, size: 14, skin: model.skin)
            }
        }
        .plainButton()
    }
}

/// A small square in a player's colour.
private struct PlayerSwatch: View {
    let color: RGB

    var body: some View {
        Rectangle().fill(color.color).frame(width: pt(10), height: pt(10))
    }
}

/// A small solid triangle pointing left or right, for the lobby's rule picker.
private struct SideArrow: Shape {
    let pointsRight: Bool

    func path(in rect: CGRect) -> Path {
        let tip = CGPoint(x: pointsRight ? rect.maxX : rect.minX, y: rect.midY)
        let back = pointsRight ? rect.minX : rect.maxX
        return Path(Marks.polygon([tip, CGPoint(x: back, y: rect.minY), CGPoint(x: back, y: rect.maxY)]))
    }
}
