// ConnectView.swift — Pair a gamepad, or use this phone as the controller for an Apple TV
//
// Opened from the menu's CONNECT tile. Lists the gamepads (and keyboard) the
// game can hear right now, says how to pair one when there's none, and leads
// on to the phone-as-controller screen. Drawn over the menu's demo game, like
// the how-to page.

import Combine
import GameController
import SwiftUI

struct ConnectView: View {
    let model: AppModel
    let weights: LineWeights
    @State private var gamepads: [Gamepad] = []
    @State private var keyboard = false

    private struct Gamepad: Identifiable {
        let id: ObjectIdentifier
        let name: String
    }

    var body: some View {
        let skin = model.skin
        let copy = Brand.copy.controller
        ZStack {
            skin.background.color.opacity(0.75).ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: pt(12)) {
                    Text(copy.hubTitle)
                        .font(skin.font(.display, 32))
                        .foregroundStyle(skin.ink.color)
                        .accessibilityAddTraits(.isHeader)
                        .padding(.bottom, pt(10))

                    heading(copy.gamepads)
                    if gamepads.isEmpty && !keyboard {
                        note(copy.noGamepads)
                    }
                    ForEach(gamepads) { pad in
                        device(symbol: "gamecontroller.fill", name: pad.name)
                    }
                    if keyboard {
                        device(symbol: "keyboard.fill", name: copy.keyboard)
                    }

                    heading(copy.tv)
                        .padding(.top, pt(22))
                    note(copy.tvDetail)
                    tvButton
                        .padding(.top, pt(4))

                    Button { model.hideConnect() } label: {
                        ButtonFace(skin: skin, weights: weights, selected: true, width: pt(160), height: pt(44)) {
                            TrackedLabel(text: copy.back, size: 15, skin: skin)
                        }
                    }
                    .plainButton()
                    .frame(maxWidth: .infinity)
                    .padding(.top, pt(28))
                }
                .frame(maxWidth: pt(420), alignment: .leading)
                .padding(.horizontal, pt(28))
                .padding(.vertical, pt(40))
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
        }
        .onAppear { refresh() }
        .onReceive(changes) { note in
            // A controller that just went is still listed as its notice arrives
            refresh(leaving: note.name == .GCControllerDidDisconnect ? note.object as? GCController : nil)
        }
    }

    /// Phone-as-controller needs iOS 26 (its pad uses the newer networking).
    private var tvAvailable: Bool {
        #if os(iOS)
        if #available(iOS 26.0, *) { return true }
        #endif
        return false
    }

    @ViewBuilder private var tvButton: some View {
        let skin = model.skin
        let copy = Brand.copy.controller
        Button {
            model.showingController = true
        } label: {
            ButtonFace(skin: skin, weights: weights, width: pt(220), height: pt(52)) {
                HStack(spacing: pt(10)) {
                    Image(systemName: "appletv")
                        .font(.system(size: pt(18), weight: .regular))
                        .foregroundStyle(skin.ink.color)
                    TrackedLabel(text: copy.tvButton, size: 15, skin: skin)
                }
            }
        }
        .plainButton()
        .disabled(!tvAvailable)
        .opacity(tvAvailable ? 1 : 0.5)
        .accessibilityHint(tvAvailable ? copy.detail : copy.tvNeedsUpdate)
        if !tvAvailable {
            note(copy.tvNeedsUpdate)
        }
    }

    private func heading(_ text: String) -> some View {
        Text(text)
            .font(model.skin.font(.display, 15))
            .foregroundStyle(model.skin.ink.color)
            .accessibilityAddTraits(.isHeader)
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .font(model.skin.font(.text, 13))
            .foregroundStyle(model.skin.ink.color(secondary))
            .fixedSize(horizontal: false, vertical: true)
    }

    /// One connected device: what it is, and that it's ready to play.
    private func device(symbol: String, name: String) -> some View {
        let skin = model.skin
        return HStack(spacing: pt(10)) {
            Image(systemName: symbol)
                .font(.system(size: pt(16), weight: .regular))
                .frame(width: pt(24))
            Text(name)
                .font(skin.font(.text, 13))
                .lineLimit(1)
            Spacer(minLength: pt(8))
            Text(Brand.copy.controller.connected)
                .font(skin.font(.display, 10))
                .tracking(pt(10) * labelTracking)
                .foregroundStyle(skin.ink.color(secondary))
        }
        .foregroundStyle(skin.ink.color)
        .frame(height: pt(28))
        .accessibilityElement(children: .combine)
    }

    private var changes: AnyPublisher<Notification, Never> {
        let center = NotificationCenter.default
        let names: [Notification.Name] = [.GCControllerDidConnect, .GCControllerDidDisconnect,
                                          .GCKeyboardDidConnect, .GCKeyboardDidDisconnect]
        return Publishers.MergeMany(names.map { center.publisher(for: $0) })
            .receive(on: RunLoop.main)
            .eraseToAnyPublisher()
    }

    private func refresh(leaving gone: GCController? = nil) {
        gamepads = GCController.controllers()
            .filter { $0.extendedGamepad != nil && $0 !== gone }
            .map { Gamepad(id: ObjectIdentifier($0), name: $0.vendorName ?? Brand.copy.inputs.gamepad.name) }
        keyboard = GCKeyboard.coalesced != nil
    }
}
