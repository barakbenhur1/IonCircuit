//
//  ObstacleKind.swift
//  IonCircuit
//
//  Created by Barak Ben Hur on 12/10/2025.
//

//
//  ObstacleKit.swift
//  IonCircuit
//

import SpriteKit
import UIKit

// NOTE: keep this ObstacleKind in sync with your spawner
enum ObstacleKind { case rock, barrel, cone, barrier, steel } // NEW: steel (indestructible)

/// Breakable/indestructible obstacle node with visuals, physics and damage UI.
/// - Destructible kinds: rock, barrel, cone, barrier
/// - Indestructible: steel (shows a shield badge + metallic sheen)
final class ObstacleNode: SKNode {
    let kind: ObstacleKind
    
    // HP only for destructible; steel has nil hp/maxHP
    private(set) var hp: Int?
    private let maxHP: Int?
    private var barYOffset: CGFloat = 26
    
    // UI
    private var damageBarBG: SKShapeNode?
    private var damageBarFG: SKShapeNode?
    private var badgeNode: SKNode? // for steel's “shield” badge
    
    init(kind: ObstacleKind) {
        self.kind = kind
        if ObstacleNode.isDestructible(kind) {
            let m = ObstacleNode.defaultHP[kind] ?? 64
            self.maxHP = m
            self.hp = m
        } else {
            self.maxHP = nil
            self.hp = nil
        }
        super.init()
        buildVisualsAndPhysics()
        buildDamageUIIfNeeded()
    }
    required init?(coder: NSCoder) { fatalError() }
    
    // MARK: Tunables
    static let defaultHP: [ObstacleKind: Int] = [
        .cone: 16,
        .barrel: 32,
        .rock: 80,
        .barrier: 120
    ]
    static func isDestructible(_ k: ObstacleKind) -> Bool {
        switch k {
        case .steel: return false
        default: return true
        }
    }
    
    // MARK: Build
    private func buildVisualsAndPhysics() {
        switch kind {
        case .rock:
            let r: CGFloat = 40
            let shape = SKShapeNode(circleOfRadius: r)
            shape.fillColor = .init(white: 0.34, alpha: 1)
            shape.strokeColor = .init(white: 1, alpha: 0.12)
            shape.lineWidth = 1.5
            addChild(shape)
            let pb = SKPhysicsBody(circleOfRadius: r)
            configure(body: pb)
            barYOffset = r + 18
            
        case .barrel:
            let w: CGFloat = 44, h: CGFloat = 54
            let rect = CGRect(x: -w/2, y: -h/2, width: w, height: h)
            let body = SKShapeNode(rect: rect, cornerRadius: 4)
            body.fillColor = .brown
            body.strokeColor = .white.withAlphaComponent(0.18)
            body.lineWidth = 1.2
            // Rings
            let rings = SKShapeNode()
            let p = CGMutablePath()
            p.move(to: CGPoint(x: rect.minX+3, y: 6));  p.addLine(to: CGPoint(x: rect.maxX-3, y: 6))
            p.move(to: CGPoint(x: rect.minX+3, y: -6)); p.addLine(to: CGPoint(x: rect.maxX-3, y: -6))
            rings.path = p
            rings.strokeColor = .black.withAlphaComponent(0.25)
            rings.lineWidth = 2
            body.addChild(rings)
            addChild(body)
            let pb = SKPhysicsBody(rectangleOf: CGSize(width: w, height: h))
            configure(body: pb)
            barYOffset = h/2 + 16
            
        case .cone:
            let path = CGMutablePath()
            path.move(to: CGPoint(x: 0, y: 18))
            path.addLine(to: CGPoint(x: -18, y: -22))
            path.addLine(to: CGPoint(x: 18, y: -22))
            path.closeSubpath()
            let shape = SKShapeNode(path: path)
            shape.fillColor = .orange
            shape.strokeColor = .white.withAlphaComponent(0.20)
            shape.lineWidth = 1.0
            addChild(shape)
            let pb = SKPhysicsBody(rectangleOf: CGSize(width: 22, height: 30))
            configure(body: pb)
            barYOffset = 26
            
        case .barrier:
            let w: CGFloat = 96, h: CGFloat = 18
            let rect = CGRect(x: -w/2, y: -h/2, width: w, height: h)
            let shape = SKShapeNode(rect: rect, cornerRadius: 4)
            shape.fillColor = .darkGray
            shape.strokeColor = .white.withAlphaComponent(0.16)
            shape.lineWidth = 1.2
            // hazard stripes
            let stripes = SKShapeNode()
            let p = CGMutablePath()
            for i in stride(from: -w/2, through: w/2, by: 12) {
                p.move(to: CGPoint(x: i, y: -h/2))
                p.addLine(to: CGPoint(x: i+12, y: h/2))
            }
            stripes.path = p
            stripes.strokeColor = .yellow.withAlphaComponent(0.35)
            stripes.lineWidth = 3
            shape.addChild(stripes)
            addChild(shape)
            let pb = SKPhysicsBody(rectangleOf: CGSize(width: w, height: h))
            configure(body: pb)
            barYOffset = h/2 + 16
            
        case .steel:
            // Indestructible: cool steel plate + shield badge + metallic sheen
            let w: CGFloat = 90, h: CGFloat = 24
            let rect = CGRect(x: -w/2, y: -h/2, width: w, height: h)
            let plate = SKShapeNode(rect: rect, cornerRadius: 4)
            plate.fillColor = UIColor(hue: 0.58, saturation: 0.20, brightness: 0.65, alpha: 1) // bluish steel
            plate.strokeColor = .white.withAlphaComponent(0.22)
            plate.lineWidth = 1.2
            
            // rivets
            let rivets = SKShapeNode()
            let rp = CGMutablePath()
            for x in stride(from: rect.minX+8, through: rect.maxX-8, by: 22) {
                rp.addEllipse(in: CGRect(x: CGFloat(x)-2, y: rect.maxY-6, width: 4, height: 4))
                rp.addEllipse(in: CGRect(x: CGFloat(x)-2, y: rect.minY+2, width: 4, height: 4))
            }
            rivets.path = rp
            rivets.fillColor = .white.withAlphaComponent(0.55)
            rivets.strokeColor = .clear
            plate.addChild(rivets)
            
            // shield badge (clear visual that it can't be broken)
            let shield = SKShapeNode(path: makeShieldPath(size: CGSize(width: 18, height: 22)))
            shield.position = CGPoint(x: 0, y: 0)
            shield.fillColor = UIColor.systemBlue.withAlphaComponent(0.95)
            shield.strokeColor = .white.withAlphaComponent(0.8)
            shield.lineWidth = 1.2
            plate.addChild(shield)
            badgeNode = shield
            
            // subtle sheen animation
            let sheen = SKShapeNode(rect: CGRect(x: rect.minX, y: rect.minY, width: 18, height: rect.height))
            sheen.fillColor = .white.withAlphaComponent(0.10)
            sheen.strokeColor = .clear
            plate.addChild(sheen)
            let slide = SKAction.sequence([
                .moveTo(x: rect.maxX, duration: 1.0),
                .wait(forDuration: 0.8),
                .moveTo(x: rect.minX, duration: 0.0)
            ])
            sheen.position.x = rect.minX
            sheen.run(.repeatForever(slide))
            
            addChild(plate)
            let pb = SKPhysicsBody(rectangleOf: CGSize(width: w, height: h))
            configure(body: pb)
            barYOffset = h/2 + 16
        }
    }
    
    private func configure(body pb: SKPhysicsBody) {
        pb.isDynamic = false
        pb.affectedByGravity = false
        pb.friction = 0.6
        pb.restitution = 0.05
        
        pb.categoryBitMask = Category.obstacle
        pb.contactTestBitMask = Category.bullet          // we want bullet hits
        pb.collisionBitMask = UInt32.max                 // <— include bullets so the engine tests contact
        // Note: Obstacle is static, so it won't move. We remove the bullet on impact in didBegin(_:).
        physicsBody = pb
    }
    
    private func makeShieldPath(size: CGSize) -> CGPath {
        let w = size.width, h = size.height
        let p = CGMutablePath()
        // simple pentagonal shield
        p.move(to: CGPoint(x: 0, y: h/2))
        p.addLine(to: CGPoint(x:  w/2, y:  h/6))
        p.addLine(to: CGPoint(x:  w/3, y: -h/2))
        p.addLine(to: CGPoint(x: -w/3, y: -h/2))
        p.addLine(to: CGPoint(x: -w/2, y:  h/6))
        p.closeSubpath()
        return p
    }
    
    // MARK: Damage UI
    private func buildDamageUIIfNeeded() {
        guard ObstacleNode.isDestructible(kind) else { return }
        
        let w: CGFloat = 40
        let h: CGFloat = 5
        let bg = SKShapeNode(rectOf: CGSize(width: w, height: h), cornerRadius: 2)
        bg.fillColor = UIColor(white: 0, alpha: 0.35)
        bg.strokeColor = .clear
        bg.zPosition = 5
        bg.position = CGPoint(x: 0, y: barYOffset)
        addChild(bg)
        damageBarBG = bg
        
        let fg = SKShapeNode(rectOf: CGSize(width: w-2, height: h-2), cornerRadius: 2)
        fg.fillColor = .systemGreen
        fg.strokeColor = .clear
        fg.zPosition = 6
        fg.position = CGPoint(x: 0, y: barYOffset)
        addChild(fg)
        damageBarFG = fg
        
        updateDamageBar() // set initial width/color
    }
    
    private func updateDamageBar() {
        guard let hp, let maxHP, let fg = damageBarFG, let bg = damageBarBG else { return }
        let w: CGFloat = 40
        let frac = max(0, min(1, CGFloat(hp) / CGFloat(maxHP)))
        let targetW = max(2, (w-2) * frac)
        
        let path = CGMutablePath()
        
        let rect = CGRect(x: -targetW/2, y: -2, width: targetW, height: 4)
        // Clamp radii so they’re always valid for the current rect
        let cw = min(2, rect.width  * 0.5)
        let ch = min(2, rect.height * 0.5)
        
        if cw <= 0 || ch <= 0 {
            path.addRect(rect)             // fallback for extremely small sizes
        } else {
            path.addRoundedRect(in: rect, cornerWidth: cw, cornerHeight: ch)
        }
        
        fg.path = path
        
        // Green -> Yellow -> Red
        if frac > 0.66 { fg.fillColor = .systemGreen }
        else if frac > 0.33 { fg.fillColor = .systemYellow }
        else { fg.fillColor = .systemRed }
        bg.isHidden = (frac >= 0.999)
        fg.isHidden = (frac >= 0.999)
    }
    
    @discardableResult
    func applyDamage(_ amount: Int, impact: CGPoint? = nil) -> Bool {
        // Indestructible steel → tiny pulse + ricochet and exit.
        if kind == .steel {
            steelBadgePulse()
            ricochetFX(at: impact)
            return false
        }

        // Destructible: update HP and UI
        guard var curHP = self.hp, let _ = self.maxHP else { return false }
        let dmg = max(0, amount)
        curHP = max(0, curHP - dmg)
        self.hp = curHP

        // Feedback
        flashTint()
        hitFX(at: impact)
        updateDamageBar()

        // Still alive → bump anim and done
        if curHP > 0 {
            removeAction(forKey: "hitBump")
            let bump = SKAction.sequence([
                .scale(to: 1.06, duration: 0.05),
                .scale(to: 1.00, duration: 0.08)
            ])
            run(bump, withKey: "hitBump")
            return false
        }

        // Dead → big scene FX + local debris, then remove
        if let scene = self.scene as? GameScene {
            let worldPoint = self.convert(CGPoint.zero, to: scene)   // <- explicit CGPoint
            scene.spawnDestructionFX(at: worldPoint, for: kind)
        }
        destroyFX(at: impact)

        physicsBody = nil
        removeAllActions()
        removeFromParent()
        return true
    }
    
    private func flashTint() {
        guard let base = (children.first as? SKShapeNode) else { return }
        let orig = base.fillColor
        base.removeAction(forKey: "flash")
        let flash = SKAction.sequence([
            .customAction(withDuration: 0.0) { _,_ in base.fillColor = .red.withAlphaComponent(0.85) },
            .wait(forDuration: 0.06),
            .customAction(withDuration: 0.0) { _,_ in base.fillColor = orig }
        ])
        base.run(flash, withKey: "flash")
    }
    
    private func ricochetFX(at p: CGPoint?) {
        // tiny white/yellow spark fan
        let origin = p ?? .zero
        let N = 6
        for i in 0..<N {
            let s = SKShapeNode(circleOfRadius: 1.6)
            s.fillColor = (i % 2 == 0) ? .white : .yellow
            s.strokeColor = .clear
            s.position = origin
            addChild(s)
            let a = CGFloat.random(in: 0..<(2 * .pi))
            let v = CGVector(dx: cos(a) * CGFloat.random(in: 120...220),
                             dy: sin(a) * CGFloat.random(in: 120...220))
            s.run(.sequence([
                .group([.move(by: v, duration: 0.18), .fadeOut(withDuration: 0.18)]),
                .removeFromParent()
            ]))
        }
    }
    
    private func steelBadgePulse() {
        guard let badge = badgeNode else { return }
        badge.removeAction(forKey: "pulse")
        let up = SKAction.group([.scale(to: 1.15, duration: 0.08), .fadeAlpha(to: 1.0, duration: 0.08)])
        let down = SKAction.group([.scale(to: 1.00, duration: 0.10), .fadeAlpha(to: 0.95, duration: 0.10)])
        badge.run(.sequence([up, down]), withKey: "pulse")
    }
    
    private func hitFX(at p: CGPoint?) {
        let dot = SKShapeNode(circleOfRadius: 4)
        dot.fillColor = .white
        dot.strokeColor = .clear
        dot.alpha = 0.9
        dot.position = p ?? .zero
        addChild(dot)
        dot.run(.sequence([.fadeOut(withDuration: 0.15), .removeFromParent()]))
    }
    
    private func destroyFX(at p: CGPoint?) {
        let count = 10
        for _ in 0..<count {
            let s = SKShapeNode(circleOfRadius: 2)
            s.fillColor = .white.withAlphaComponent(0.9)
            s.strokeColor = .clear
            s.position = p ?? .zero
            addChild(s)
            let a = CGFloat.random(in: 0..<(2 * .pi))
            let v = CGVector(dx: cos(a) * CGFloat.random(in: 80...200),
                             dy: sin(a) * CGFloat.random(in: 80...200))
            s.run(.sequence([
                .group([.move(by: v, duration: 0.25), .fadeOut(withDuration: 0.25)]),
                .removeFromParent()
            ]))
        }
    }
}

/// Factory to keep your existing calls intact.
enum ObstacleFactory {
    static func make(_ kind: ObstacleKind) -> ObstacleNode {
        ObstacleNode(kind: kind)
    }
}
