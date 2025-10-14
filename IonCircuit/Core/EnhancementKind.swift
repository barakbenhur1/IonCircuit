//
//  EnhancementKind.swift
//  IonCircuit
//
//  Created by Barak Ben Hur on 13/10/2025.
//

import SpriteKit

// ==================================
// Enhancement kinds & pickup node
// ==================================
enum EnhancementKind: CaseIterable {
    case hp20               // +20 HP (cap 100, cannot pick at 100)
    case shield20           // +20 Shield (cap 100, cannot pick at 100)
    case weaponRapid        // weapon: rapid fire
    case weaponDamage       // weapon: high-caliber (more damage)
    case weaponSpread       // weapon: spread shot (triple)
    case control          // steering/traction boost for 30s
    case shrink           // smaller car for 30s (cannot pick while active)
}

final class EnhancementNode: SKNode {
    let kind: EnhancementKind
    
    init(kind: EnhancementKind) {
        self.kind = kind
        super.init()
        name = "enhancement.\(kind)"
        zPosition = 2
        
        // Visual: base coin + icon
        let R: CGFloat = 16
        let ring = SKShapeNode(circleOfRadius: R)
        ring.fillColor = UIColor(white: 0, alpha: 0.25)
        ring.strokeColor = UIColor.white.withAlphaComponent(0.25)
        ring.lineWidth = 1.5
        ring.glowWidth = 2
        addChild(ring)
        
        let icon = SKShapeNode()
        icon.strokeColor = .white
        icon.lineWidth = 2
        icon.glowWidth = 1
        
        switch kind {
        case .hp20:
            icon.path = CGPath(roundedRect: CGRect(x: -6, y: -6, width: 12, height: 12), cornerWidth: 3, cornerHeight: 3, transform: nil)
            icon.fillColor = UIColor.systemGreen.withAlphaComponent(0.8)
        case .shield20:
            let p = CGMutablePath()
            p.move(to: CGPoint(x: 0, y: 7))
            p.addLine(to: CGPoint(x: 8, y: 2))
            p.addLine(to: CGPoint(x: 8, y: -5))
            p.addLine(to: CGPoint(x: 0, y: -9))
            p.addLine(to: CGPoint(x: -8, y: -5))
            p.addLine(to: CGPoint(x: -8, y: 2))
            p.closeSubpath()
            icon.path = p
            icon.fillColor = UIColor.systemTeal.withAlphaComponent(0.8)
        case .weaponRapid:
            let p = CGMutablePath()
            p.move(to: CGPoint(x: -8, y: -2)); p.addLine(to: CGPoint(x: 8, y: -2))
            p.move(to: CGPoint(x: -8, y:  0)); p.addLine(to: CGPoint(x: 8, y:  0))
            p.move(to: CGPoint(x: -8, y:  2)); p.addLine(to: CGPoint(x: 8, y:  2))
            icon.path = p
        case .weaponDamage:
            icon.path = CGPath(ellipseIn: CGRect(x: -4, y: -4, width: 8, height: 8), transform: nil)
        case .weaponSpread:
            let p = CGMutablePath()
            p.move(to: CGPoint(x: -6, y: -6)); p.addLine(to: CGPoint(x: 0, y: 6))
            p.move(to: CGPoint(x:  0, y: -6)); p.addLine(to: CGPoint(x: 0, y: 6))
            p.move(to: CGPoint(x:  6, y: -6)); p.addLine(to: CGPoint(x: 0, y: 6))
            icon.path = p
        case .control:
            let p = CGMutablePath()
            p.addRoundedRect(in: CGRect(x: -8, y: -3, width: 16, height: 6), cornerWidth: 3, cornerHeight: 3)
            icon.path = p
            icon.fillColor = UIColor.systemYellow.withAlphaComponent(0.8)
        case .shrink:
            let p = CGMutablePath()
            p.addRect(CGRect(x: -6, y: -8, width: 12, height: 16))
            icon.path = p
            icon.fillColor = UIColor.systemPurple.withAlphaComponent(0.8)
        }
        addChild(icon)
        
        // Float / pulse
        let up = SKAction.moveBy(x: 0, y: 6, duration: 0.6); up.timingMode = .easeInEaseOut
        let dn = SKAction.moveBy(x: 0, y: -6, duration: 0.6); dn.timingMode = .easeInEaseOut
        run(.repeatForever(.sequence([up, dn])))
        
        // Physics: sensor only
        let pb = SKPhysicsBody(circleOfRadius: R + 4)
        pb.isDynamic = false
        pb.categoryBitMask = Category.enhancements
        pb.contactTestBitMask = Category.car
        pb.collisionBitMask = 0
        self.physicsBody = pb
    }
    required init?(coder: NSCoder) { fatalError() }
}
