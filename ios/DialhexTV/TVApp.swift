// TVApp.swift — Apple TV entry: the SwiftUI root inside a GCEventViewController
//
// On Apple TV the remote and gamepads also drive the system: swipes move focus
// and Back leaves the app. A GCEventViewController at the root keeps their
// input for the game (ControllerInput reads it through GameController), and
// only hands it back on the top-level menu, where Back has to go Home.

import GameController
import SwiftUI
import UIKit

@main
final class TVAppDelegate: UIResponder, UIApplicationDelegate {}

final class TVSceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?
    private var model: AppModel?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let scene = scene as? UIWindowScene else { return }
        let model = AppModel()
        self.model = model
        let window = UIWindow(windowScene: scene)
        window.rootViewController = TVRootController(model: model)
        window.makeKeyAndVisible()
        self.window = window
    }

    // The same lifecycle handling as the iPhone app's scenePhase observer
    func sceneWillResignActive(_ scene: UIScene) {
        model?.pauseIfPlaying()
    }

    func sceneDidEnterBackground(_ scene: UIScene) {
        Lessons.sceneChanged(toBackground: true)
    }

    func sceneDidBecomeActive(_ scene: UIScene) {
        Lessons.sceneChanged(toBackground: false)
    }
}

/// Hosts the game and decides who gets the remote: the game, or (on the
/// top-level menu) the system, so Back returns to the Home Screen.
final class TVRootController: GCEventViewController {
    private let model: AppModel

    init(model: AppModel) {
        self.model = model
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func viewDidLoad() {
        super.viewDidLoad()
        let host = UIHostingController(rootView: RootView(model: model).preferredColorScheme(.dark))
        addChild(host)
        host.view.frame = view.bounds
        host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(host.view)
        host.didMove(toParent: self)
        // Controllers coming and going decide whether the presses fallback below is needed
        for name in [Notification.Name.GCControllerDidConnect, .GCControllerDidDisconnect] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.followBackButton() }
            })
        }
        followBackButton()
    }

    private var handOver: Task<Void, Never>?
    private var observers: [NSObjectProtocol] = []

    /// No remote shows up as a GameController device, so it arrives only as UIKit
    /// presses, handled below. On an Apple TV the Siri Remote always does show up;
    /// the tvOS Simulator's doesn't (it offers only a virtual gamepad).
    private var pressesOnly: Bool {
        !GCController.controllers().contains { $0.microGamepad != nil && $0.extendedGamepad == nil }
    }

    /// Keep `controllerUserInteractionEnabled` in step with the model, re-arming after each change.
    private func followBackButton() {
        let leaves = withObservationTracking {
            model.backLeavesApp
        } onChange: { [weak self] in
            Task { @MainActor in self?.followBackButton() }
        }
        handOver?.cancel()
        // With presses only, they must reach the responder chain to be played at all
        if pressesOnly {
            controllerUserInteractionEnabled = true
            return
        }
        guard leaves else {
            controllerUserInteractionEnabled = false
            return
        }
        // The press that got back to the menu (Back from the how-to page or the pause
        // screen) mustn't also leave the app on release: hand over once it's let go.
        handOver = Task { @MainActor [weak self] in
            while !Task.isCancelled, Self.backHeld() {
                try? await Task.sleep(for: .milliseconds(50))
            }
            guard !Task.isCancelled else { return }
            self?.controllerUserInteractionEnabled = true
        }
    }

    // MARK: - Presses

    /// Plays remote presses when GameController can't. Unplayed presses, and Back on
    /// the top-level menu, go on to the system (which leaves for the Home Screen).
    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        let unplayed = presses.filter { press in
            guard pressesOnly, !(press.type == .menu && model.backLeavesApp) else { return true }
            return !model.controls.press(press.type, pressed: true)
        }
        if !unplayed.isEmpty { super.pressesBegan(unplayed, with: event) }
    }

    override func pressesEnded(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        released(presses)
        super.pressesEnded(presses, with: event)
    }

    override func pressesCancelled(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        released(presses)
        super.pressesCancelled(presses, with: event)
    }

    /// Ends a held arrow's repeat.
    private func released(_ presses: Set<UIPress>) {
        guard pressesOnly else { return }
        for press in presses { _ = model.controls.press(press.type, pressed: false) }
    }

    /// Whether any remote's Back or gamepad's B (both the system's Back) is down.
    private static func backHeld() -> Bool {
        GCController.controllers().contains { controller in
            controller.microGamepad?.buttonMenu.isPressed == true
                || controller.extendedGamepad?.buttonB.isPressed == true
                || controller.extendedGamepad?.buttonMenu.isPressed == true
        }
    }
}
