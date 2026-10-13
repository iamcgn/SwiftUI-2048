# 2048 — a SwiftUI game, as a portable source port

**Play it in your browser: https://iamcgn.github.io/SwiftUI-2048/**

This is a fork of [unixzii/SwiftUI-2048](https://github.com/unixzii/SwiftUI-2048), the 2048
game Cyandev wrote in 2019 to demonstrate SwiftUI (MIT, © 2019 Cyandev — see
[LICENSE](LICENSE)). The game itself — the board model, the move and merge algorithm, the
tile views and their animations, the swipe gesture — is Cyandev's code, unchanged. What this
fork changes is the shell around it, so the same Swift files run:

- natively on **iOS 17+** (and macOS 14+) with Apple's SwiftUI, from the Xcode project;
- in the **browser**, compiled to WebAssembly against
  [iamcgn/swiftui-web](https://github.com/iamcgn/swiftui-web) (SwiftUIWeb), a SwiftUI
  implementation that paints into a canvas, with its Foundation and Combine stand-ins.

This is a *port*, labelled as such. It is not the "unchanged upstream app running in the
browser" that SwiftUIWeb's own acceptance standard asks for: that standard still holds the
pristine upstream as its benchmark, and upstream's `@objc`/`#selector` entry point still
does not compile for wasm. See "What changed" below for exactly what was replaced.

![Upstream's screenshot](Screenshot.png)

## What changed, and what did not

Upstream hosts `GameView` from a UIKit `AppDelegate` on iOS (and an `NSHostingView` on
macOS), starts a new game through an Objective-C selector behind a `UIKeyCommand` in a
`MainMenu.xib`, and reads the arrow keys in `pressesBegan` (Mac Catalyst) and `keyDown`
(macOS). None of that is portable, and `@objc`/`#selector` cannot be compiled for wasm at
all. The port replaces that shell with the SwiftUI app life cycle:

| Upstream | This port |
|---|---|
| `SwiftUI2048/AppDelegate.swift` (`@UIApplicationMain`, `UIWindow`, `UIHostingController`) | `SwiftUI2048/SwiftUI2048App.swift`: `@main struct SwiftUI2048App: App`, a `WindowGroup`, the `GameLogic` as a `@StateObject` |
| `@objc func newGame(_:)` + `UIKeyCommand(input: "N", modifierFlags: .command, action: #selector(...))` in `buildMenu(with:)` | a closure: `CommandGroup(replacing: .newItem) { Button("New Game") { … }.keyboardShortcut("n") }` in the File menu, and a visible **New Game** button in `GameView` (a phone and a browser page have no menu bar; upstream's iOS build had no way to restart) |
| `pressesBegan` / `keyDown` arrow handling in the window's responder | `GameView` is `focusable()`, takes focus on appear, and handles `.upArrow/.downArrow/.leftArrow/.rightArrow` through `onKeyPress` (iOS 17+) |
| `SwiftUI2048-mac/` (AppKit target), `MainMenu.xib`, `LaunchScreen.storyboard`, `Info.plist`, entitlements | removed; one multi-platform target with a generated Info.plist and launch screen |
| `SwiftUI2048.xcodeproj` (Xcode 11, iOS 13, Catalyst) | rewritten for Xcode 16+: iOS 17 / macOS 14, synchronized folders, a unit-test target |

Unchanged: `Models/` (`BlockMatrix`, `GameLogic`, `IdentifiedBlock`), `Views/` (`BlockView`,
`BlockGridView`, and `GameView` except for the additions above), `FunctionalUtils.swift`,
`SwiftUIExtensions.swift`, the asset catalog. The deprecation warnings Xcode 16 gives on
upstream's `animation(_:)` and `cornerRadius(_:)` are left as upstream wrote them.

Two small additions to `GameLogic` are **test seams**, not behaviour: `init(randomIndex:)`
takes the chooser that decides where new blocks land (the app passes nothing and gets
upstream's `Int.random(in:)`), and `init(board:randomIndex:)` starts a game from a board a
test laid out. The app never uses the second; nothing in the app is replaced by fixtures.

The port also surfaced two bugs in SwiftUIWeb's runtime, fixed there (a `focusable()` view
swallowing the drag gesture around it; a canvas click moving the page's focus to the body),
and one fidelity gap it records (`withTransaction` being `@MainActor` there while Apple's is
nonisolated). The pin in `vendor/swiftui-web` includes the fixes.

## Upstream's algorithm, as it is

Upstream's README says "the game algorithm may have issues, and this is still WIP". The port
keeps the algorithm exactly as it is — these are characterised by `SwiftUI2048Tests` and
checked in the browser by the probe, not corrected. What a correction would be is noted so
nobody mistakes the behaviour for a bug in the port:

1. **Two blocks spawn per move, always 2s.** Standard 2048 spawns one block, a 4 one time in
   ten. (`generateNewBlocks` places two `IdentifiedBlock(number: 2)`.)
2. **Nothing spawns with fewer than two blank squares.** A move that leaves one blank gets no
   new block. (`guard blankLocations.count >= 2`.)
3. **A swipe that moves nothing can still spawn.** `move` decides "moved" by comparing each
   new line against a snapshot that is not aligned with the squares (`rowSnapshot` gets an
   extra `nil` after every square, so a block at column 1 is compared with the snapshot's
   column-0 gap). Any line holding two or more blocks counts as moved even when none can
   move, and two blocks appear. A fix would snapshot the line's four squares as they are.
4. **No score, no win, no game over.** A full board with no merges just stays; nothing
   says so. The view's colour table ends at 2048 — a 4096 block would hit upstream's
   `fatalError("No color for such number")`.
5. **`objectWillChange` fires after the change.** Upstream sends it from `defer` blocks. SwiftUI
   re-reads on the next turn either way.
6. Merges are standard: one merge per pair per swipe, leading pair first (`[2,2,2]` → `[4,2]`
   leftwards, `[2,4]` rightwards), the block that slid into its partner keeps its identity
   (so that is the tile the animation carries).

## Building and running

Requirements: Xcode 16 or later for the native app; for the browser build, the Swift 6.3.3
toolchain and its wasm SDK (installed through [swiftly](https://www.swift.org/install/), see
`.swift-version` and [SwiftUIWeb's README](https://github.com/iamcgn/swiftui-web)), Node 18+
for the probe. Clone with submodules:

```sh
git clone --recurse-submodules https://github.com/iamcgn/SwiftUI-2048.git
cd SwiftUI-2048
```

**Native (Apple's SwiftUI):** open `SwiftUI2048.xcodeproj` and run the `SwiftUI2048` scheme on
an iPhone simulator, an iPad or a Mac; or from the shell:

```sh
xcodebuild test -project SwiftUI2048.xcodeproj -scheme SwiftUI2048 \
  -destination 'platform=iOS Simulator,name=iPhone 16' CODE_SIGNING_ALLOWED=NO
```

Swipe to move; with a hardware keyboard, the arrow keys move and ⌘N starts over (the
File ▸ New Game command on iPad and Mac); the **New Game** button is always there.

**Browser (SwiftUIWeb):**

```sh
swiftly install 6.3.3          # once; see .swift-version
swift sdk install https://download.swift.org/swift-6.3.3-release/wasm-sdk/swift-6.3.3-RELEASE/swift-6.3.3-RELEASE_wasm.artifactbundle.tar.gz \
  --checksum cabfa08b73bb8ac783927ecd15fa386e99d0c139c5f232445067bcf58379cae7
scripts/build-web.sh           # release; `--debug` for a quick build with DWARF
python3 -m http.server 8791 --directory dist
open http://127.0.0.1:8791/
```

`scripts/build-web.sh` compiles `Package.swift` for `wasm32-unknown-wasip1` with the
JavaScriptKit `PackageToJS` plugin, adds the asset catalog, and writes a self-contained site
to `dist/` (the bundle under a name unique to the build, so caches never serve a stale wasm).
That `dist/` is what GitHub Pages serves.

In a browser: swipe (touch or mouse drag) or use the arrow keys; **New Game** restarts.
⌘N / Ctrl+N is the browser's own New Window shortcut and never reaches a page, which is why
the restart is a visible button and the probe records the shortcut rather than counting it.

## Tests and evidence

- `SwiftUI2048Tests/GameLogicTests.swift` — Swift Testing, run by Xcode against Apple's
  frameworks on an iOS simulator (and on macOS): new games, slides in every direction,
  merges (once per pair, leading pair first, identity of the merged block), spawns at the
  chooser's blanks, and each quirk above as upstream has it.
- `Playwright/game-probe.mjs` — plays the browser build in headless Chromium. It reads the
  settled board as cells (column, row, number) from the page's display list and judges every
  input against `expectedMove`, a JavaScript port of upstream's `GameLogic.move` (quirk 3
  included). Flows: launch, arrows (until a merge, a swipe that changes nothing, and a
  changes-nothing-yet-spawns swipe have all been seen), New Game then arrows (a regression:
  a click once dropped the board's focus), a mouse drag in each direction, a finger drag in
  each direction (real touch events over the Chrome DevTools Protocol), four viewport sizes
  for upstream's banner rule and the button staying clear of the grid, and the DOM-level
  ⌘N/Ctrl+N (recorded only). It writes `report.json` and screenshots to `.build/probe`.

  ```sh
  cd Playwright && npm install && npx playwright install chromium
  node game-probe.mjs http://127.0.0.1:8791/index.html
  ```
- `.github/workflows/ci.yml` — `native`: the iOS simulator tests and a macOS build with
  Xcode; `web`: the release wasm build, the probe (evidence uploaded as an artifact), and on
  `master` the deploy of `dist/` to GitHub Pages.

## Credits

- The game: [SwiftUI-2048](https://github.com/unixzii/SwiftUI-2048) by
  [Cyandev (unixzii)](https://github.com/unixzii), MIT License, © 2019 Cyandev. This fork keeps
  the license and copyright; the port's changes are under the same license.
- The browser runtime: [SwiftUIWeb](https://github.com/iamcgn/swiftui-web) by
  [iamcgn](https://github.com/iamcgn) — SwiftUI, Foundation and Combine for WebAssembly,
  pinned as the `vendor/swiftui-web` submodule.
- The port: iamcgn, 2026.
