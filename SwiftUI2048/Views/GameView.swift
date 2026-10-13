//
//  GameView.swift
//  SwiftUI2048
//
//  Created by Hongyu on 6/5/19.
//  Copyright © 2019 Cyandev. All rights reserved.
//

import SwiftUI

extension Edge {
    
    static func from(_ from: GameLogic.Direction) -> Self {
        switch from {
        case .down:
            return .top
        case .up:
            return .bottom
        case .left:
            return .trailing
        case .right:
            return .leading
        }
    }
    
}

struct GameView : View {
    
    @State var ignoreGesture = false
    @EnvironmentObject var gameLogic: GameLogic
    
    // The port: the board holds keyboard focus so the arrow keys reach it (onKeyPress acts
    // on the focused view; upstream read the keys in the window's responder instead).
    @FocusState fileprivate var boardFocused: Bool
    
    fileprivate struct LayoutTraits {
        let bannerOffset: CGSize
        let showsBanner: Bool
        let containerAlignment: Alignment
        // The port: where the New Game button sits — the edge opposite the banner.
        let buttonAlignment: Alignment
    }
    
    fileprivate func layoutTraits(`for` proxy: GeometryProxy) -> LayoutTraits {
#if os(macOS)
        let landscape = false
#else
        let landscape = proxy.size.width > proxy.size.height
#endif
        
        return LayoutTraits(
            bannerOffset: landscape
                ? .init(width: 32, height: 0)
                : .init(width: 0, height: 32),
            showsBanner: landscape ? proxy.size.width > 720 : proxy.size.height > 550,
            containerAlignment: landscape ? .leading : .top,
            buttonAlignment: landscape ? .trailing : .bottom
        )
    }
    
    var gestureEnabled: Bool {
        // Existed for future usage.
#if os(macOS) || targetEnvironment(macCatalyst)
        return false
#else
        return true
#endif
    }
    
    var gesture: some Gesture {
        let threshold: CGFloat = 44
        let drag = DragGesture()
            .onChanged { v in
                guard !self.ignoreGesture else { return }
                
                guard abs(v.translation.width) > threshold ||
                    abs(v.translation.height) > threshold else {
                    return
                }
                
                withTransaction(Transaction(animation: .spring())) {
                    self.ignoreGesture = true
                    
                    if v.translation.width > threshold {
                        // Move right
                        self.gameLogic.move(.right)
                    } else if v.translation.width < -threshold {
                        // Move left
                        self.gameLogic.move(.left)
                    } else if v.translation.height > threshold {
                        // Move down
                        self.gameLogic.move(.down)
                    } else if v.translation.height < -threshold {
                        // Move up
                        self.gameLogic.move(.up)
                    }
                }
            }
            .onEnded { _ in
                self.ignoreGesture = false
            }
        return drag
    }
    
    var content: some View {
        GeometryReader { proxy in
            bind(self.layoutTraits(for: proxy)) { layoutTraits in
                ZStack(alignment: layoutTraits.containerAlignment) {
                    if layoutTraits.showsBanner {
                        Text("2048")
                            .font(Font.system(size: 48).weight(.black))
                            .foregroundColor(Color(red:0.47, green:0.43, blue:0.40, opacity:1.00))
                            .offset(layoutTraits.bannerOffset)
                    }
                    
                    ZStack(alignment: .center) {
                        BlockGridView(matrix: self.gameLogic.blockMatrix,
                                      blockEnterEdge: .from(self.gameLogic.lastGestureDirection))
                    }
                    .frame(width: proxy.size.width, height: proxy.size.height, alignment: .center)
                    
                    // The port: upstream's New Game lived only in the Catalyst and macOS menus;
                    // a phone and a browser page have no menu bar, so the game shows it.
                    Button("New Game") {
                        self.gameLogic.startNewGame()
                    }
                    .buttonStyle(.bordered)
                    .padding(32)
                    .frame(width: proxy.size.width, height: proxy.size.height, alignment: layoutTraits.buttonAlignment)
                }
                .frame(width: proxy.size.width, height: proxy.size.height, alignment: .center)
                .background(
                    Rectangle()
                        .fill(Color(red:0.96, green:0.94, blue:0.90, opacity:1.00))
                        .edgesIgnoringSafeArea(.all)
                )
            }
        }
    }
    
    // The port: upstream's `pressesBegan` (Catalyst) and `keyDown` (macOS) as onKeyPress on the
    // focused board. The down phase only, as the macOS shell ignored key repeats.
    fileprivate func keyMove(_ press: KeyPress) -> KeyPress.Result {
        switch press.key {
        case .upArrow:
            self.gameLogic.moveAnimated(.up)
        case .downArrow:
            self.gameLogic.moveAnimated(.down)
        case .leftArrow:
            self.gameLogic.moveAnimated(.left)
        case .rightArrow:
            self.gameLogic.moveAnimated(.right)
        default:
            return .ignored
        }
        return .handled
    }
    
    var keyedContent: some View {
        content
            .focusable()
            .focused($boardFocused)
            .onAppear { self.boardFocused = true }
            .onKeyPress(keys: [.upArrow, .downArrow, .leftArrow, .rightArrow], phases: .down) { press in
                self.keyMove(press)
            }
    }
    
    var body: AnyView {
        return gestureEnabled ? (
            keyedContent
                .gesture(gesture, including: .all)>*
        ) : keyedContent>*
    }
    
}

#if DEBUG
struct GameView_Previews : PreviewProvider {
    
    static var previews: some View {
        GameView()
            .environmentObject(GameLogic())
    }
    
}
#endif
