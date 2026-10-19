# Dialhex for iOS

A native port of the web game, for iPhone and iPad, with game controller and
hardware keyboard support.

| Layer | Framework |
| --- | --- |
| Game rules (`DialhexCore/`) | Plain Swift package, unit-tested with `swift test` |
| Board rendering and effects | SpriteKit (`SpriteView`, `SKEmitterNode`, `SKAction`) |
| Menus and HUD | SwiftUI |
| Controllers and keyboards | GameController (`GCController`, `GCKeyboard`, light bar) |
| Rumble | CoreHaptics (controller) and `UIFeedbackGenerator` (device) |
| Sound | `AVAudioEngine` with `AVAudioUnitEQ` filters |
| High scores | `UserDefaults` |

## Build

```sh
brew install xcodegen
cd ios
xcodegen generate
open Dialhex.xcodeproj
```

Set your signing team on the Dialhex target to run on a device. To run the
game-logic tests on their own:

```sh
cd ios/DialhexCore
swift test
```

## Controls

| Action | Controller | Keyboard | Touch |
| --- | --- | --- | --- |
| Move the dial | D-pad / left stick | Arrows / WASD | Tap a spot |
| Turn clockwise | A, Y, R1, R2 | E / X | Tap the dial again, ↻ button, twist |
| Turn counter-clockwise | X, L1, L2 | Q / Z | ↺ button, twist |
| Pause | Menu, B | Space, Esc | Pause button |
| Back to menu | B or Options while paused | Esc while paused | Menu button |
| Start a mode | D-pad then A | 1 / 2 / 3 | Tap a mode |

The game pauses itself when the app leaves the foreground or the controller
disconnects.

## Apple TV

The `DialhexTV` target builds the same app for tvOS (same bundle ID, for a
universal purchase). It starts from `DialhexTV/TVApp.swift`, which hosts the
SwiftUI root in a `GCEventViewController` so the remote's input goes to the game;
only on the top-level menu does the system get it, so Back returns Home. The UI
is laid out at half the TV's size and drawn at double.

| Action | Siri Remote |
| --- | --- |
| Move the dial | Swipe (hold to repeat), or click the clickpad's edge |
| Turn clockwise | Click (the centre, on the clickpad remote) |
| Turn counter-clockwise | Play/Pause |
| Pause / back | Back |

Gamepads work as on iPhone. The iPhone's Control Center remote plays like the
Siri Remote.
