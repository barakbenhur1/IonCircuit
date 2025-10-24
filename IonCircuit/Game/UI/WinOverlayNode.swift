//
//  WinOverlayNode.swift
//  IonCircuit
//
//  Created by Barak Ben Hur on 17/10/2025.
//

import SpriteKit
import UIKit

final class WinOverlayNode: SKNode {
    var onRestart: (() -> Void)?

    private let block = SKShapeNode()
    private let panel = SKShapeNode()
    private let title = SKLabelNode(fontNamed: "Menlo-Bold")
    private let hint  = SKLabelNode(fontNamed: "Menlo")
    private let button = SKShapeNode()
    private let btnLabel = SKLabelNode(fontNamed: "Menlo-Bold")

    override init() {
        super.init()
        zPosition = 10_000

        // dim the world
        block.path = CGPath(rect: CGRect(x: -2000, y: -2000, width: 4000, height: 4000), transform: nil)
        block.fillColor = UIColor(white: 0, alpha: 0.55)
        block.strokeColor = .clear
        addChild(block)

        // panel
        let w: CGFloat = 280, h: CGFloat = 180
        panel.path = CGPath(roundedRect: CGRect(x: -w/2, y: -h/2, width: w, height: h),
                            cornerWidth: 16, cornerHeight: 16, transform: nil)
        panel.fillColor = UIColor(white: 0.08, alpha: 0.95)
        panel.strokeColor = UIColor(white: 1, alpha: 0.10)
        panel.lineWidth = 1.0
        addChild(panel)

        title.text = "YOU WIN!"
        title.fontSize = 26
        title.fontColor = Ion.palette.text
        title.verticalAlignmentMode = .center
        title.position = CGPoint(x: 0, y: 40)
        addChild(title)

        hint.text = "All enemies eliminated."
        hint.fontSize = 14
        hint.fontColor = Ion.palette.textDim
        hint.verticalAlignmentMode = .center
        hint.position = CGPoint(x: 0, y: 10)
        addChild(hint)

        // restart / play again
        let bw: CGFloat = 160, bh: CGFloat = 42
        button.path = CGPath(roundedRect: CGRect(x: -bw/2, y: -bh/2, width: bw, height: bh),
                             cornerWidth: 12, cornerHeight: 12, transform: nil)
        button.fillColor = UIColor.systemGreen
        button.strokeColor = UIColor.white.withAlphaComponent(0.2)
        button.lineWidth = 1.0
        button.position = CGPoint(x: 0, y: -40)
        button.name = "restart"
        addChild(button)

        btnLabel.text = "Play Again"
        btnLabel.fontSize = 16
        btnLabel.fontColor = Ion.palette.text
        btnLabel.verticalAlignmentMode = .center
        btnLabel.position = .zero
        button.addChild(btnLabel)

        isHidden = true
        alpha = 0
    }

    required init?(coder: NSCoder) { fatalError() }

    func show(in camera: SKNode, size: CGSize) {
        position = .zero
        isHidden = false
        alpha = 0
        run(.fadeAlpha(to: 1, duration: 0.18))
    }

    func hide() {
        run(.sequence([.fadeOut(withDuration: 0.12), .hide()]))
    }

    // Call from touches in GameScene
    func handleTouch(scenePoint p: CGPoint) -> Bool {
        guard let scn = scene else { return false }
        let local = convert(p, from: scn)
        let hitRect = button.frame.insetBy(dx: -10, dy: -10)
        if hitRect.contains(local) {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            onRestart?()
            return true
        }
        return false
    }
}
