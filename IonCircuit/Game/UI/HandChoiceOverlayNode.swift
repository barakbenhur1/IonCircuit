//
//  HandChoiceOverlayNode.swift
//  IonCircuit
//
//  Created by Barak Ben Hur on 13/10/2025.
//

import SpriteKit
import UIKit

final class HandChoiceOverlayNode: SKNode {
    // closure API used by GameScene
    var onPick: ((Bool) -> Void)?   // true = left, false = right
    
    private let dim  = SKShapeNode()
    private let panel = SKShapeNode()
    private let leftBtn  = SKShapeNode()
    private let rightBtn = SKShapeNode()
    private let title = SKLabelNode(fontNamed: "Menlo-Bold")
    private var viewSize: CGSize
    
    init(size: CGSize) {
        self.viewSize = size
        super.init()
        isUserInteractionEnabled = true
        zPosition = 10_000
        buildUI()
    }
    required init?(coder: NSCoder) { fatalError() }
    
    func updateSize(_ size: CGSize) {
        viewSize = size
        removeAllChildren()
        buildUI()
    }
    
    // MARK: UI
    private func buildUI() {
        // dim
        let rect = CGRect(x: -viewSize.width/2, y: -viewSize.height/2, width: viewSize.width, height: viewSize.height)
        dim.path = CGPath(rect: rect, transform: nil)
        dim.fillColor = UIColor.black.withAlphaComponent(0.60)
        dim.strokeColor = .clear
        addChild(dim)
        
        // panel
        let pw: CGFloat = min(360, viewSize.width - 40)
        let ph: CGFloat = 200
        let panelRect = CGRect(x: -pw/2, y: -ph/2, width: pw, height: ph)
        panel.path = CGPath(roundedRect: panelRect, cornerWidth: 16, cornerHeight: 16, transform: nil)
        panel.fillColor = UIColor(white: 0.08, alpha: 0.95)
        panel.strokeColor = UIColor.white.withAlphaComponent(0.12)
        panel.lineWidth = 1
        addChild(panel)
        
        title.text = "Choose hand preference"
        title.fontSize = 16
        title.fontColor = Ion.palette.textDim
        title.verticalAlignmentMode = .center
        title.position = CGPoint(x: 0, y: panelRect.maxY - 44)
        addChild(title)
        
        func makeButton(text: String, primary: Bool) -> SKShapeNode {
            let w: CGFloat = (pw - 48) / 2
            let h: CGFloat = 56
            let btn = SKShapeNode(rectOf: CGSize(width: w, height: h), cornerRadius: 12)
            btn.fillColor = primary ? Ion.palette.accentB : Ion.palette.accentB.withAlphaComponent(0.12)
            btn.strokeColor = UIColor.white.withAlphaComponent(0.20)
            btn.lineWidth = 1
            
            let label = SKLabelNode(fontNamed: "Menlo-Bold")
            label.text = text
            label.fontSize = 16
            label.fontColor = Ion.palette.text
            label.verticalAlignmentMode = .center
            label.horizontalAlignmentMode = .center
            btn.addChild(label)
            return btn
        }
        
        let L = makeButton(text: "Left", primary: true)
        let R = makeButton(text: "Right", primary: false)
        leftBtn.path = L.path;  leftBtn.fillColor = L.fillColor;   leftBtn.strokeColor = L.strokeColor
        rightBtn.path = R.path; rightBtn.fillColor = R.fillColor; rightBtn.strokeColor = R.strokeColor
        leftBtn.name = "left"; rightBtn.name = "right"
        
        // labels (paths don’t copy subnodes)
        let ll = SKLabelNode(fontNamed: "Menlo-Bold"); ll.text = "Left";  ll.fontSize = 16; ll.verticalAlignmentMode = .center; ll.horizontalAlignmentMode = .center
        let rl = SKLabelNode(fontNamed: "Menlo-Bold"); rl.text = "Right"; rl.fontSize = 16; rl.verticalAlignmentMode = .center; rl.horizontalAlignmentMode = .center
        leftBtn.addChild(ll); rightBtn.addChild(rl)
        
        leftBtn.position  = CGPoint(x: -((panel.frame.width - 48)/2 + 5 - leftBtn.frame.width/2),  y: -20)
        rightBtn.position = CGPoint(x:  ((panel.frame.width - 48)/2 + 5 - rightBtn.frame.width/2), y: -20)
        addChild(leftBtn); addChild(rightBtn)
        
        alpha = 0
        setScale(0.98)
        run(.group([.fadeIn(withDuration: 0.15),
                    .sequence([.scale(to: 1.02, duration: 0.12),
                               .scale(to: 1.00, duration: 0.10)])]))
    }
    
    // MARK: Touch
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let t = touches.first else { return }
        let p = t.location(in: self)
        if leftBtn.contains(p) {
            leftBtn.run(.sequence([.scale(to: 0.96, duration: 0.05), .scale(to: 1.0, duration: 0.08)]))
            onPick?(true)
            run(.sequence([.fadeOut(withDuration: 0.12), .removeFromParent()]))
        } else if rightBtn.contains(p) {
            rightBtn.run(.sequence([.scale(to: 0.96, duration: 0.05), .scale(to: 1.0, duration: 0.08)]))
            onPick?(false)
            run(.sequence([.fadeOut(withDuration: 0.12), .removeFromParent()]))
        }
    }
}
