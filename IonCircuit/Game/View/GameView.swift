//
//  GameView.swift
//  IonCircuit
//
//  Created by Barak Ben Hur on 12/10/2025.
//

import SwiftUI
import SpriteKit
import UIKit

// Helper: grabs the UIScreen from the SwiftUI view's window.
private final class ScreenProbeView: UIView {
    var onChange: (UIScreen?) -> Void = { _ in }
    override func didMoveToWindow() {
        super.didMoveToWindow()
        onChange(window?.windowScene?.screen)
    }
}

private struct ScreenReader: UIViewRepresentable {
    var onChange: (UIScreen?) -> Void
    func makeUIView(context: Context) -> ScreenProbeView {
        let v = ScreenProbeView()
        v.isUserInteractionEnabled = false
        v.backgroundColor = .clear
        v.onChange = onChange
        return v
    }
    func updateUIView(_ uiView: ScreenProbeView, context: Context) {}
}

struct GameView: View {
    // Create with zero size; SpriteKit will resize it to the SpriteView bounds.
    @State private var scene: GameScene = {
        let s = GameScene(size: .zero)
        s.backgroundColor = .black
        s.scaleMode = .resizeFill
        return s
    }()
    
    @State private var preferredFPS: Int = 60
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()          // <- backplate so any transparent pixels read as black
            SpriteView(scene: scene,
                       preferredFramesPerSecond: preferredFPS,
                       options: [.ignoresSiblingOrder])
            .ignoresSafeArea()
            
            // Reads the correct UIScreen from the hosting window/scene.
            ScreenReader { screen in
                preferredFPS = screen?.maximumFramesPerSecond ?? 60
            }
            .allowsHitTesting(false)
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)) { _ in
            scene.isPaused = true
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            scene.isPaused = false
        }
    }
}

