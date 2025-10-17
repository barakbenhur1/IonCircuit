//
//  MiniEnhHUD.swift
//  IonCircuit
//
//  Created by Barak Ben Hur on 17/10/2025.
//


// MARK: - Simple HUD

import SpriteKit

final class CarHealthHUDNode: SKNode {
    
    private let livesRow = SKNode()
    private var heartNodes: [SKLabelNode] = []

    // public API ---------------------------------------------------------------
    func set(hp: Int, maxHP: Int, shield: Int) {
        let hpC = max(0, min(hp, maxHP))
        let shC = max(0, min(shield, 100)) // cap 100

        // numbers
        hpValueLabel.text = "\(hpC)/\(maxHP)"
        if shC > 0 {
            shieldChip.isHidden = false
            shieldValueLabel.text = "\(shC)"
        } else {
            shieldChip.isHidden = true
        }

        // bars
        let fracHP = CGFloat(hpC) / max(1, CGFloat(maxHP))
        let fracSH = CGFloat(shC) / 100.0

        let hpW = barWidth * fracHP
        hpBar.path = CGPath(roundedRect: CGRect(x: -barWidth/2, y: -barH/2, width: hpW, height: barH),
                            cornerWidth: barH/2, cornerHeight: barH/2, transform: nil)

        let shW = barWidth * fracSH
        shieldOverlay.path = CGPath(roundedRect: CGRect(x: -barWidth/2, y: -barH/2, width: shW, height: barH),
                                    cornerWidth: barH/2, cornerHeight: barH/2, transform: nil)
    }

    func place(at worldPos: CGPoint) { position = worldPos }

    // internals ----------------------------------------------------------------
    private let card     = SKShapeNode()
    private let hpTitle  = SKLabelNode(fontNamed: "Menlo-Bold")
    private let hpValueLabel = SKLabelNode(fontNamed: "Menlo")
    private let shieldChip = SKShapeNode()
    private let shieldLabel = SKLabelNode(fontNamed: "Menlo-Bold")
    private let shieldValueLabel = SKLabelNode(fontNamed: "Menlo")

    private let barBase = SKShapeNode()
    private let hpBar   = SKShapeNode()
    private let shieldOverlay = SKShapeNode()

    private let barWidth: CGFloat = 160
    private let barH: CGFloat = 12

    override init() {
        super.init()
        zPosition = 700

        let w: CGFloat = 180, h: CGFloat = 44
        card.path = CGPath(roundedRect: CGRect(x: -w/2, y: -h/2 - 5, width: w, height: h),
                           cornerWidth: 14, cornerHeight: 14, transform: nil)
        card.fillColor   = UIColor(white: 0, alpha: 0.28)
        card.strokeColor = UIColor(white: 1, alpha: 0.10)
        card.lineWidth   = 1
        addChild(card)

        hpTitle.text = "HP"
        hpTitle.fontSize = 13
        hpTitle.fontColor = UIColor.white.withAlphaComponent(0.9)
        hpTitle.horizontalAlignmentMode = .left
        hpTitle.verticalAlignmentMode = .center
        hpTitle.position = CGPoint(x: -w/2 + 44, y: h/2 - 25.5)
        addChild(hpTitle)

        hpValueLabel.text = "0/0"
        hpValueLabel.fontSize = 13
        hpValueLabel.fontColor = UIColor.white.withAlphaComponent(0.9)
        hpValueLabel.horizontalAlignmentMode = .left
        hpValueLabel.verticalAlignmentMode = .center
        hpValueLabel.position = CGPoint(x: -w/2 + 64, y: h/2 - 26.5)
        addChild(hpValueLabel)

        let chipH: CGFloat = 18
        let chipW: CGFloat = 90
        shieldChip.path = CGPath(roundedRect: CGRect(x: -chipW/2, y: -chipH/2, width: chipW, height: chipH),
                                 cornerWidth: chipH/2, cornerHeight: chipH/2, transform: nil)
        shieldChip.fillColor   = UIColor.systemBlue.withAlphaComponent(0.25)
        shieldChip.strokeColor = UIColor.systemBlue.withAlphaComponent(0.8)
        shieldChip.lineWidth   = 1
        shieldChip.position = CGPoint(x: -w/2 + 160, y: h/2 - 8)
        addChild(shieldChip)

        shieldLabel.text = "Shield"
        shieldLabel.fontSize = 12
        shieldLabel.fontColor = UIColor.white
        shieldLabel.verticalAlignmentMode = .center
        shieldLabel.horizontalAlignmentMode = .center
        shieldLabel.position = CGPoint(x: -18, y: 0)
        shieldChip.addChild(shieldLabel)

        shieldValueLabel.text = "0"
        shieldValueLabel.fontSize = 12
        shieldValueLabel.fontColor = UIColor.white
        shieldValueLabel.verticalAlignmentMode = .center
        shieldValueLabel.horizontalAlignmentMode = .center
        shieldValueLabel.position = CGPoint(x: 26, y: 0)
        shieldChip.addChild(shieldValueLabel)

        barBase.path = CGPath(roundedRect: CGRect(x: -barWidth/2, y: -barH/2, width: barWidth, height: barH),
                              cornerWidth: barH/2, cornerHeight: barH/2, transform: nil)
        barBase.fillColor = UIColor.white.withAlphaComponent(0.10)
        barBase.strokeColor = UIColor.white.withAlphaComponent(0.08)
        barBase.lineWidth = 1
        barBase.position = CGPoint(x: 0, y: -4)
        addChild(barBase)

        hpBar.fillColor = UIColor.systemGreen.withAlphaComponent(0.9)
        hpBar.strokeColor = .clear
        hpBar.position = barBase.position
        addChild(hpBar)

        shieldOverlay.fillColor = UIColor.systemBlue.withAlphaComponent(0.85)
        shieldOverlay.strokeColor = .clear
        shieldOverlay.position = barBase.position
        shieldOverlay.zPosition = 1
        addChild(shieldOverlay)
        
        livesRow.position = CGPoint(x: 0, y: 28) // above the bar
        addChild(livesRow)
        setLives(left: 3, max: 3)

        shieldChip.isHidden = true
        set(hp: 0, maxHP: 100, shield: 0)
    }

    required init?(coder: NSCoder) { fatalError() }
    
    func setLives(left: Int, max: Int) {
        rebuildLives(left: left, max: max)
    }

    private func rebuildLives(left: Int, max: Int) {
        livesRow.removeAllChildren()
        heartNodes.removeAll()
        
        // layout
        let spacing: CGFloat = 16
        let totalW = spacing * CGFloat(max - 1)
        let startX = -totalW / 2.0
        
        for i in 0..<max {
            let lbl = SKLabelNode(fontNamed: "Menlo-Bold")
            lbl.fontSize = 14
            lbl.verticalAlignmentMode = .center
            lbl.horizontalAlignmentMode = .center
            let filled = i < left
            lbl.text = filled ? "♥︎" : "♡"
            lbl.fontColor = filled ? UIColor.systemRed : UIColor.white.withAlphaComponent(0.6)
            lbl.position = CGPoint(x: startX + CGFloat(i) * spacing, y: 0)
            livesRow.addChild(lbl)
            heartNodes.append(lbl)
        }
    }
}
