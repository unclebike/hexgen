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
