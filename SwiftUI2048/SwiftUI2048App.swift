//
//  SwiftUI2048App.swift
//  SwiftUI2048 (portable port)
//
//  The app shell of the port. Upstream (unixzii/SwiftUI-2048) hosts GameView from a UIKit
//  AppDelegate on iOS and an NSHostingView on macOS, with New Game as an Objective-C selector
//  behind a UIKeyCommand / MainMenu.xib and the arrow keys read in pressesBegan / keyDown.
//  This file replaces those with the SwiftUI App life cycle: one GameLogic owned by the scene,
//  New Game as a plain closure in the File menu (⌘N) and in GameView's visible button, the
//  arrow keys through onKeyPress on the focused board (GameView). The model and the views are
//  upstream's.
//

import SwiftUI
#if HARNESS && os(WASI)
import JavaScriptKit
#endif

@main
struct SwiftUI2048App: App {

    @StateObject private var gameLogic = SwiftUI2048App.makeGameLogic()

    /// The game. In the app this is upstream's `GameLogic()` — the native and the published
    /// web builds compile nothing else. In the **harness** build only (`scripts/build-web.sh
    /// --harness`, which has the manifest define `HARNESS`; never the published page), the
    /// page's URL may name the model's two test seams so a browser test can lay out a board
    /// and know where new blocks land: `?board=` sixteen numbers, row by row, 0 for a blank;
    /// `?chooser=first` (the first blank, then the last) or `last` (the last, then the one
    /// before). The rules of the game are the same either way.
    static func makeGameLogic() -> GameLogic {
#if HARNESS && os(WASI)
        var query: [String: String] = [:]
        for pair in (JSObject.global.location.search.string ?? "").dropFirst().split(separator: "&") {
            let parts = pair.split(separator: "=", maxSplits: 1).map(String.init)
            if parts.count == 2 { query[parts[0]] = parts[1] }
        }
        let chooser: (Range<Int>) -> Int
        switch query["chooser"] {
        case "first": chooser = { $0.lowerBound }
        case "last": chooser = { $0.upperBound - 1 }
        default: chooser = { Int.random(in: $0) }
        }
        let numbers = (query["board"] ?? "").split(separator: ",").compactMap { Int($0) }
        if numbers.count == 16 {
            var board = GameLogic.BlockMatrixType()
            for (i, number) in numbers.enumerated() where number > 0 {
                board.place(IdentifiedBlock(id: 1000 + i, number: number), to: (i % 4, i / 4))
            }
            return GameLogic(board: board, randomIndex: chooser)
        }
        return GameLogic(randomIndex: chooser)
#else
        return GameLogic()
#endif
    }

    var body: some Scene {
        WindowGroup {
            GameView()
                .environmentObject(gameLogic)
        }
        .commands {
            // Upstream's buildMenu(with:): a "New Game" item at the top of the File menu, ⌘N.
            CommandGroup(replacing: .newItem) {
                Button("New Game") {
                    gameLogic.startNewGame()
                }
                .keyboardShortcut("n", modifiers: .command)
            }
        }
    }

}

extension GameLogic {

    /// Upstream's `newGame(_:)` action: the reset inside a spring transaction, so the old
    /// blocks animate out and the two new ones in. Main-actor, as the menu and the button
    /// that call it are.
    @MainActor func startNewGame() {
        withTransaction(Transaction(animation: .spring())) {
            newGame()
        }
    }

    /// Upstream's key handling (`pressesBegan` on Catalyst, `keyDown` on macOS): a move inside
    /// a spring transaction.
    @MainActor func moveAnimated(_ direction: Direction) {
        withTransaction(Transaction(animation: .spring())) {
            move(direction)
        }
    }

}
