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

@main
struct SwiftUI2048App: App {

    @StateObject private var gameLogic = GameLogic()

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
