# Hexgen: App Store Connect kit

Everything needed to create and submit Hexgen 1.0, in the order App Store
Connect asks for it. The text fields live in `metadata/` in
[fastlane `deliver`](https://docs.fastlane.tools/actions/deliver/) layout, so
you can paste them by hand or upload them with `fastlane deliver`.

## Before you submit: blockers

| # | Item | Status |
| --- | --- | --- |
| 0 | **Home-screen name.** The logo now says HEXGEN, but `CFBundleDisplayName` in `project.yml` (and so Info.plist) is still `Dialhex`. Change it to `Hexgen` and run `xcodegen generate`, or review may reject the build for a name mismatch (guideline 2.3.8). The bundle ID `xyz.unclebike.dialhex`, the leaderboard IDs and the `dialhex.pages.dev` domain can stay: players don't see them, apart from the URLs. | To do |
| 1 | **Privacy manifest.** The app uses `UserDefaults`, a required-reason API. Without a manifest, the upload gets an ITMS-91053 rejection. Copy `PrivacyInfo.xcprivacy` to `ios/Dialhex/`, then run `xcodegen generate`. | **Done**: in the app, builds, bundled |
| 2 | **Privacy policy and support URLs.** The pages are in [PR #12](https://github.com/unclebike/hexgen/pull/12), with contact support@unclebike.xyz. Merge it, check that `/privacy` and `/support` load, and make sure the address receives mail. The kit's `web/` copies match. | PR open |
| 3 | **Review contact phone.** `metadata/review_information/phone_number.txt` has a placeholder. Apple only sees it, but it has to be real. | To do |
| 4 | **Screenshots.** See [Screenshots](#screenshots). Required for iPhone 6.9″ and iPad 13″, because the target supports iPad (`TARGETED_DEVICE_FAMILY 1,2`). | **Enough to submit**; better shots recommended |
| 5 | **Name availability.** Reserve "Hexgen" when you create the app record. If it's taken, fall back to "Hexgen: Triangle Puzzle" (23 chars). | Check |
| 6 | **Game Center leaderboards.** Create the three leaderboards in [Game Center](#game-center) and add them to version 1.0. Otherwise the submitted scores go nowhere and review may flag it. | To do |
| 7 | **Archive.** Version 1.0, build 1, team 5C2GM29P79, bundle `xyz.unclebike.dialhex`. Product › Archive › Distribute › App Store Connect. | To do |

## 1. New app record

| Field | Value |
| --- | --- |
| Platform | iOS |
| Name | Hexgen |
| Primary language | English (U.K.). The app's copy says "colour". If you'd rather have en-US, rename `metadata/en-GB` to `en-US`. |
| Bundle ID | `xyz.unclebike.dialhex` |
| SKU | `hexgen-ios` |
| User access | Full access |

## 2. App Information

| Field | Value |
| --- | --- |
| Subtitle | `metadata/en-GB/subtitle.txt` (25/30) |
| Category | Games |
| Subcategories | Puzzle, then Arcade |
| Content rights | **No**, the app doesn't contain, show or access third-party content. The bundled fonts are OFL-licensed and their licences ship in the app. |
| Age rating | See [Age rating](#age-rating) → **4+** |
| Copyright (on the version page) | `2026 Adam Tilley` |

## 3. Pricing and availability

- Price: Free (my recommendation; it matches the "no ads, no purchases" copy).
- Availability: all countries and regions.
- Apple silicon Mac / Apple Vision Pro availability: leave on. The iPad build
  runs as-is, and the game supports keyboards and controllers.

## 4. App Privacy

Privacy policy URL: `metadata/en-GB/privacy_url.txt`

Data collection: **"No, we do not collect data from this app."** The app has
no server, analytics or third-party SDKs, and `UserDefaults` stays on the
device. The only data that leaves the device is the Game Center score, which
goes to Apple's leaderboard through GameKit. Apple collects that under its own
[Game Center privacy notice](https://www.apple.com/legal/privacy/data/en/game-center/);
the app never stores or sends the player's identity anywhere.

Resulting label: **Data Not Collected**.

> **The cautious alternative.** You can view and remove leaderboard entries in
> App Store Connect. If you'd rather count that as collection, declare
> **Gameplay Content** (purpose: App Functionality, not linked to identity, not
> used for tracking). The privacy page text works either way.

## 5. Age rating

Every questionnaire answer is **None** / **No**:

| Section | Answer |
| --- | --- |
| Violence, sexual content, profanity, horror, drugs/alcohol/tobacco, gambling themes, mature themes, medical | None |
| Simulated gambling, contests | None |
| Unrestricted web access | No |
| User-generated content, messaging or chat | No |
| Advertising | No |
| Parental controls / age assurance | No |
| Health or wellness topics | No |

Result: **4+**. You don't need to opt into the Kids category.

## 6. Accessibility Nutrition Labels

Claim only what the app actually supports. Reviewers can test these.

| Label | Claim? | Why |
| --- | --- | --- |
| Differentiate Without Color Alone | **Yes** | Every piece colour has its own mark (`skins.json` → `marks`). |
| Dark Interface | **Yes** | The default skin is dark and the app forces the dark scheme. |
| Sufficient Contrast | Not yet | Wait until the colour-accessibility pass in progress is done and checked. |
| VoiceOver | No | Only the pause and turn buttons have labels. The board isn't exposed. |
| Voice Control | No | Same reason. |
| Larger Text | No | Text sizes are fixed, with no Dynamic Type. |
| Reduced Motion | No | The acid skin's flash and the screen shake ignore Reduce Motion. |
| Captions / Audio Descriptions | N/A | No speech or video. |

## 7. Version 1.0: store listing

| Field | File | Limit |
| --- | --- | --- |
| Promotional text | `metadata/en-GB/promotional_text.txt` | 164/170 |
| Description | `metadata/en-GB/description.txt` | 1957/4000 |
| Keywords | `metadata/en-GB/keywords.txt` | 100/100 |
| Support URL | `metadata/en-GB/support_url.txt` | |
| Marketing URL | `metadata/en-GB/marketing_url.txt` (the web game) | |
| What's New | You can't enter it for a first version. | |

The keywords leave out words App Store search already covers: the app name,
"puzzle" and "games" (from the category), and plurals.

## 8. Build, export compliance, controllers

- **Encryption:** `ITSAppUsesNonExemptEncryption = NO` is already in
  Info.plist, so App Store Connect won't ask.
- **Game controllers:** `GCSupportedGameControllers` (ExtendedGamepad) is in
  Info.plist. That's what puts the "Game Controller" badge on the store page.
- **Game Center:** on. The entitlement is in `Dialhex.entitlements`. See
  [Game Center](#game-center).
- **In-App Purchases:** none.
- **Sign-in required:** No. Game Center is optional. Leave the demo account
  fields empty.

## Game Center

The three **Classic** leaderboards are defined in
`Dialhex/GameCenterResources.gamekit`. Open it in Xcode for the GameKit editor,
then use **Push to App Store Connect** (the More (…) button at the bottom of the
editor's list) to create them. IDs can't change once pushed, and must match
`Scores.leaderboardID(for:)` exactly:

| Reference name | Leaderboard ID | Score format | Submission | Sort | Range | Display name (en-GB) | Suffix |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Main | `dialhex.main` | Integer | Best score | High to low | 0 – 10,000,000 | MAIN | points |
| Endless | `dialhex.endless` | Integer | Best score | High to low | 0 – 100,000,000 | ENDLESS | points |
| Sprint | `dialhex.sprint` | Integer | Best score | High to low | 0 – 10,000,000 | SPRINT | points |

Each one can also have an image (optional, 512 × 512 or 1024 × 1024): the mode name in the
display font on the base skin works well. Then, on the **1.0 version page**
under **Game Center**, turn it on and add all three leaderboards. No
achievements yet.

## 9. App Review information

| Field | File |
| --- | --- |
| First / last name | `review_information/first_name.txt`, `last_name.txt` |
| Email | `review_information/email_address.txt` |
| Phone | `review_information/phone_number.txt` (**placeholder, replace**) |
| Notes | `review_information/notes.txt` |

Release: **Manually release this version**, so you can make sure the support
and privacy pages are live first.

## Screenshots

**Captured** (in `screenshots/en-GB/`, raw simulator captures, no captions):

| File | Size | Shows |
| --- | --- | --- |
| `iphone-01-play-base.png` | 1320 × 2868 | base skin, ENDLESS, pile in the lower third, dial visible |
| `iphone-02-gameover.png` | 1320 × 2868 | crt skin, "bin full.", "new best." |
| `iphone-03-menu.png` | 1320 × 2868 | menu, base skin, HEXGEN logo |
| `iphone-04…08-play-*.png` | 1320 × 2868 | riso, crt, flash, mono, acid mid-game |
| `ipad-01-play-base.png` | 2064 × 2752 | base skin, ENDLESS |
| `ipad-02-gameover.png` | 2064 × 2752 | base, "bin full." **(a "that was a swap." tip card is in the shot; retake)** |

That's enough to submit: App Store Connect needs at least one per required size.

**Limits of these shots.** No one was playing, so every gameplay shot has
only the first two colours and a score near 0. For stronger shots, either play
a few minutes on a device and screenshot, or add a Debug-only launch argument
that starts a game mid-level with more colours on the board.

**Not used:** `screenshots-rejected/ipad-03-menu-button-clipping.png`. On iPad,
the selected MAIN button's inner frame cuts through its text, and the whole menu
is small for a 13″ screen. Fix it in the app, then retake.

**Still to take on iPad:** riso, crt, and one landscape shot. The simulator
interaction sessions kept dropping after a few minutes.

**Things seen in the shots worth fixing before release:**
- The menu shows controller and keyboard hints on touch-only devices.
- The pause screen shows the "controller." tip with no controller connected.
- A brief flat grey board for about a second when a game starts on iPad.
- With the acid skin, the "best" badge touches the ENDLESS label on the menu.
- `defaults write … dialhex_skin` on the simulator was ignored at launch,
  so the saved skin may not be restored. Worth checking on a device.

Captions, if you frame them later (display font, lower case, full stop):
"turn six. make one." · "grab a point. turn it." · "main. endless. sprint." ·
"six skins to unlock." · "plays with a controller." · "no ads. no tracking."

To retake: install a Debug build in the simulator, then open every skin with
`xcrun simctl spawn booted defaults write xyz.unclebike.dialhex dialhex_progress -data $(printf '{"mainWins":0,"hexes":1000}' | xxd -p | tr -d '\n')`
and hide the lessons with `… dialhex_lessons_learned -array 0 1 2 3`. Save with
`xcrun simctl io booted screenshot <file>.png`.

## Upload with fastlane (optional)

```sh
cd ios/AppStore
fastlane deliver --skip_binary_upload --metadata_path ./metadata \
  --screenshots_path ./screenshots --app_identifier xyz.unclebike.dialhex
```
