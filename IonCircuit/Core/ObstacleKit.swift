//
//  ObstacleKind.swift
//  IonCircuit
//
//  Created by Barak Ben Hur on 12/10/2025.
//

import SpriteKit
import UIKit

// NOTE: keep this ObstacleKind in sync with your spawner
enum ObstacleKind { case rock, barrel, cone, barrier, steel, hole, worm } // NEW: steel (indestructible)

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
    
    private weak var visualBase: SKShapeNode?
    private var visualBaseColor: UIColor = .clear
    
    // Auto-hide tunables
    private let barAutoHideDelay: TimeInterval = 2.5
    private let barFadeDuration: TimeInterval = 0.25
    
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
            visualBase = shape
            visualBaseColor = shape.fillColor
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
            visualBase = body
            visualBaseColor = body.fillColor
            let pb = SKPhysicsBody(rectangleOf: CGSize(width: w, height: h))
            configure(body: pb)
            barYOffset = h/2 + 16
            
        case .cone: // 🔁 REPLACE the whole cone case with this
            // Visual size roughly matches your old 36×40 triangle (±18 wide, +18/-22 tall)
            let w: CGFloat = 36
            let h: CGFloat = 40
            let tipY: CGFloat  = 18
            let baseY: CGFloat = -22
            
            // Ensure the white stripe is at least ~2 device pixels thick
            let scale = UIScreen.main.scale
            let stripeH = max(h * 0.18, 2.0 / max(scale, 1.0))
            let stripeY = -h * 0.12               // slightly below center
            let stripeW = w * 0.82
            
            // ── Orange triangle body ───────────────────────────────────────────
            let tri = CGMutablePath()
            tri.move(to: CGPoint(x: 0,   y: tipY))
            tri.addLine(to: CGPoint(x: -w*0.5, y: baseY))
            tri.addLine(to: CGPoint(x:  w*0.5, y: baseY))
            tri.closeSubpath()
            
            let body = SKShapeNode(path: tri)
            body.isAntialiased = true
            body.fillColor = .orange
            body.strokeColor = UIColor(white: 1.0, alpha: 0.20)
            body.lineWidth = 1.0
            addChild(body)
            visualBase = body
            visualBaseColor = body.fillColor
            
            // ── White reflective stripe (filled band, not a hairline stroke) ──
            let band = SKShapeNode(rectOf: CGSize(width: stripeW, height: stripeH),
                                   cornerRadius: stripeH * 0.45)
            band.position = CGPoint(x: 0, y: stripeY)
            band.fillColor = .white
            band.strokeColor = .clear
            band.zPosition = 1
            addChild(band)
            
            // Orange caps so the band looks inset inside the triangle silhouette
            func capPath(top: Bool) -> CGPath {
                let p = CGMutablePath()
                if top {
                    p.move(to: CGPoint(x: 0, y: tipY))
                    p.addLine(to: CGPoint(x: -w*0.42, y: stripeY + stripeH*0.5))
                    p.addLine(to: CGPoint(x:  w*0.42, y: stripeY + stripeH*0.5))
                } else {
                    p.move(to: CGPoint(x: -w*0.5, y: baseY))
                    p.addLine(to: CGPoint(x:  w*0.5, y: baseY))
                    p.addLine(to: CGPoint(x:  w*0.42, y: stripeY - stripeH*0.5))
                    p.addLine(to: CGPoint(x: -w*0.42, y: stripeY - stripeH*0.5))
                }
                p.closeSubpath()
                return p
            }
            
            let topCap = SKShapeNode(path: capPath(top: true))
            topCap.fillColor = .orange
            topCap.strokeColor = .clear
            topCap.zPosition = 2
            addChild(topCap)
            
            let baseCap = SKShapeNode(path: capPath(top: false))
            baseCap.fillColor = .orange
            baseCap.strokeColor = .clear
            baseCap.zPosition = 2
            addChild(baseCap)
            
            // Soft base shadow to pop from ground
            let shadow = SKShapeNode(ellipseOf: CGSize(width: w*0.85, height: w*0.34))
            shadow.position = CGPoint(x: 0, y: baseY - 2)
            shadow.fillColor = UIColor.black.withAlphaComponent(0.22)
            shadow.strokeColor = .clear
            shadow.zPosition = -1
            addChild(shadow)
            
            // Physics: small rectangle (close to your old 22×30); static per your configure(body:)
            let pb = SKPhysicsBody(rectangleOf: CGSize(width: 22, height: 30))
            configure(body: pb)
            
            // Damage bar offset roughly like before
            barYOffset = 26
            
            // Help your AI/heuristics recognize destructibility quickly
            self.name = "obstacle_cone"
            if userData == nil { userData = [:] }
            userData?["destructible"] = true
            
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
            visualBase = shape
            visualBaseColor = shape.fillColor
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
            
            self.name = "obstacle_steel"
            if userData == nil { userData = [:] }
            userData?["destructible"] = false
            
        case .hole:
            // Visual: deep pit with soft rim
            let R: CGFloat = 120

            // dark pit
            let pit = SKShapeNode(circleOfRadius: R)
            pit.fillColor = UIColor.black.withAlphaComponent(0.92)
            pit.strokeColor = UIColor.white.withAlphaComponent(0.08)
            pit.lineWidth = 1.0
            addChild(pit)
            visualBase = pit
            visualBaseColor = pit.fillColor

            // inner darkness vignette
            let inner = SKShapeNode(circleOfRadius: R * 0.72)
            inner.fillColor = UIColor.black
            inner.strokeColor = .clear
            inner.alpha = 0.85
            inner.zPosition = -1
            addChild(inner)

            // faint rim glow (helps readability on dark backgrounds)
            let rim = SKShapeNode(circleOfRadius: R + 6)
            rim.strokeColor = UIColor.systemTeal.withAlphaComponent(0.25)
            rim.lineWidth = 4
            rim.fillColor = .clear
            rim.zPosition = -2
            addChild(rim)

            // Physics: sensor that marks a hole area (no collisions)
            let pb = SKPhysicsBody(circleOfRadius: R * 0.90)
            pb.isDynamic = false
            pb.affectedByGravity = false
            pb.friction = 0
            pb.restitution = 0
            pb.linearDamping = 0
            pb.angularDamping = 0
            pb.categoryBitMask = Category.hole
            pb.collisionBitMask = 0                            // don’t physically collide
            pb.contactTestBitMask = Category.car               // notify if you want reactions
            self.physicsBody = pb

            // Indestructible; no HP bar
            barYOffset = 0
            if userData == nil { userData = [:] }
            userData?["destructible"] = false
            self.name = "obstacle_hole"

        case .worm:
            break
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
        
        // Start invisible; first hit will reveal + schedule auto-hide
        bg.alpha = 0.0
        fg.alpha = 0.0
        
        updateDamageBar() // set initial width/color and hidden state for full HP
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
        
        // Hide completely when at full HP; otherwise allow visibility (alpha controlled by timer)
        let shouldHideFully = (frac >= 0.999)
        bg.isHidden = shouldHideFully
        fg.isHidden = shouldHideFully
    }
    
    /// Reveal the damage bar immediately and schedule it to fade out
    /// after `barAutoHideDelay` seconds of no further hits.
    private func revealDamageUIThenAutoHide() {
        guard let fg = damageBarFG, let bg = damageBarBG else { return }
        for node in [bg, fg] {
            node.isHidden = false            // be visible if HP < 100%
            node.removeAction(forKey: "barAutoHide") // reset timer if re-hit
            node.alpha = 1.0
            let seq = SKAction.sequence([
                .wait(forDuration: barAutoHideDelay),
                .fadeOut(withDuration: barFadeDuration)
            ])
            node.run(seq, withKey: "barAutoHide")
        }
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
        revealDamageUIThenAutoHide() // show now, and auto-hide later
        
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
        //        else {
        //            Audio.shared.playShatter(at: impact)
        //        }
        
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
        guard let base = visualBase else { return }
        let orig = visualBaseColor
        
        // If a previous flash is mid-flight, cancel and reset first
        base.removeAction(forKey: "flash")
        base.fillColor = orig
        
        let toRed = SKAction.customAction(withDuration: 0.0) { _,_ in
            base.fillColor = .red.withAlphaComponent(0.85)
        }
        let wait  = SKAction.wait(forDuration: 0.06)
        let back  = SKAction.customAction(withDuration: 0.0) { _,_ in
            base.fillColor = orig
        }
        base.run(.sequence([toRed, wait, back]), withKey: "flash")
    }
    
    private func ricochetFX(at p: CGPoint?) {
        // tiny white/yellow spark fan
        let origin = p ?? CGPoint.zero
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
        dot.position = p ?? CGPoint.zero
        addChild(dot)
        dot.run(.sequence([.fadeOut(withDuration: 0.15), .removeFromParent()]))
    }
    
    private func destroyFX(at p: CGPoint?) {
        let count = 10
        for _ in 0..<count {
            let s = SKShapeNode(circleOfRadius: 2)
            s.fillColor = .white.withAlphaComponent(0.9)
            s.strokeColor = .clear
            s.position = p ?? CGPoint.zero
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

// MARK: - Worm segment

final class WormSegmentNode: SKShapeNode {
    var hp: Int = 420
    var maxHP: Int = 420
    weak var worm: WormNode?
    var isHead: Bool = false { didSet { if isHead { maxHP = 420 * 10; hp = 420 * 10 } }}
}

protocol WormNodeSpeedConfigurable {
    var moveSpeed: CGFloat { get set }   // mapped to headSpeed
    var turnRate: CGFloat  { get set }
}

// MARK: - Worm

final class WormNode: SKNode {
    // MARK: Data
    private(set) var segments: [WormSegmentNode] = []
    private var desiredDir: CGFloat = 0
    private var slitherT: CGFloat = 0

    private struct Link {
        weak var a: WormSegmentNode?
        weak var b: WormSegmentNode?
        weak var spring: SKPhysicsJointSpring?
        weak var limit:  SKPhysicsJointLimit?
    }
    private var links: [Link] = []
    private weak var headBackupLimit: SKPhysicsJointLimit?

    // MARK: Tunables
    var segmentCount: Int = 10
    var segmentRadius: CGFloat = 34
    var spacing: CGFloat = 30

    var slitherFreq: CGFloat = 1.0
    var slitherAmp:  CGFloat = .pi/8

    var attackStart: CGFloat = 620
    var attackStop:  CGFloat = 880

    var headSpeed: CGFloat = 8
    var turnRate:  CGFloat = .pi * 0.05

    weak var target: CarNode?

    private enum Mode { case roam, pursue }
    private var mode: Mode = .roam
    private var roamDir: CGFloat = 0
    private var nextWanderChange: CGFloat = 0

    // MARK: Health bar (auto show/hide like obstacles)
    private let hpBarRoot = SKNode()
    private let hpBarBG   = SKShapeNode()
    private let hpBarFill = SKShapeNode()
    private var maxTotalHP: Int = 0

    private let hpBarHoldTime: TimeInterval = 1.3
    private let hpBarFadeIn:  TimeInterval = 0.10
    private let hpBarFadeOut: TimeInterval = 0.22
    private let hpBarHideKey  = "worm.hpbar.hide"
    
    // Eyes
    private weak var eyesRoot: SKNode?
    private weak var leftEye: SKShapeNode?
    private weak var rightEye: SKShapeNode?
    private weak var leftPupil: SKShapeNode?
    private weak var rightPupil: SKShapeNode?
    
    private var isEmerging = false
    private var emergeHeading: CGFloat = 0
    private var emergingSegmentsLeft = 0
    
    override init() { super.init() }
    required init?(coder: NSCoder) { super.init(coder: coder) }
    
    var onRemoved: (() -> Void)?

    override func removeFromParent() {
        onRemoved?()
        onRemoved = nil
        super.removeFromParent()
    }

    // MARK: Helpers
    @inline(__always)
    private func shortestSignedAngle(from a: CGFloat, to b: CGFloat) -> CGFloat {
        var d = (b - a).truncatingRemainder(dividingBy: .pi * 2)
        if d >  .pi { d -= .pi * 2 }
        if d < -.pi { d += .pi * 2 }
        return d
    }
    @inline(__always)
    private func angleLerp(from a: CGFloat, to b: CGFloat, by t: CGFloat) -> CGFloat {
        a + shortestSignedAngle(from: a, to: b) * t
    }

    // MARK: Build
    @discardableResult
    static func spawn(in scene: GameScene, at p: CGPoint, toward target: SKNode?) -> WormNode {
        let w = WormNode()
        w.position = p
        scene.addChild(w)
        w.build(in: scene, towards: target)
        return w
    }

    private func makeSeg(radius r: CGFloat,
                         color: UIColor,
                         category: UInt32,
                         contact: UInt32,
                         collide: UInt32) -> WormSegmentNode
    {
        let s = WormSegmentNode(circleOfRadius: r)
        s.fillColor = color
        s.strokeColor = UIColor.white.withAlphaComponent(0.22)
        s.lineWidth = 1.0
        s.zPosition = 1
        s.name = "worm.segment"

        let pb = SKPhysicsBody(circleOfRadius: r)
        pb.usesPreciseCollisionDetection = false
        pb.affectedByGravity = false
        pb.allowsRotation = true
        pb.isDynamic = true
        pb.categoryBitMask = category
        pb.contactTestBitMask = contact
        pb.collisionBitMask = collide      // world + car only (not other worm parts)
        pb.fieldBitMask = 0
        pb.linearDamping = 1.1
        pb.angularDamping = 0.8
        pb.friction = 0.4
        pb.restitution = 0.02
        pb.mass = 0.25
        s.physicsBody = pb
        return s
    }

    private func build(in scene: GameScene, towards target: SKNode?) {
        let headCat   = (Category.wormHead != 0) ? Category.wormHead : Category.obstacle
        let bodyCat   = (Category.wormBody != 0) ? Category.wormBody : Category.obstacle
        let bulletCat = Category.bullet
        let carCat    = Category.car

        let contactWith: UInt32 = bulletCat | carCat
        let collideWith: UInt32 = Category.wall | carCat   // no self-collide

        // ---- Head only (for now) ----
        let head = makeSeg(radius: segmentRadius + 2,
                           color: .systemPink.withAlphaComponent(0.95),
                           category: headCat, contact: contactWith, collide: collideWith)
        head.isHead = true
        head.worm = self
        head.position = .zero
        addChild(head)
        segments = [head]
        attachEyes(to: head)
        
        links.removeAll()
        refreshHeadBackupTether(in: scene)   // will activate once ≥ 3 segs exist

        // Face initial target if given
        if let t = target {
            desiredDir = atan2(t.position.y - position.y, t.position.x - position.x)
        } else {
            desiredDir = CGFloat.random(in: -.pi...(.pi))
        }
        
        emergeHeading = desiredDir
        isEmerging = true
        emergingSegmentsLeft = max(0, segmentCount - 1)

        // Small “pop” for the head as it breaches the hole
        head.setScale(0.72)
        head.alpha = 0
        head.run(.group([
            .fadeIn(withDuration: 0.10),
            .scale(to: 1.0, duration: 0.12)
        ]))
        
        // ---- Emerge the tail one-by-one ----
        emergeBodySegments(in: scene, bodyCategory: bodyCat, contact: contactWith, collide: collideWith)
        
        // Total HP bar
        
        if segments.count > 1 {
            maxTotalHP = head.maxHP + (segmentCount - 1) * segments[1].maxHP
        }
        
        prepareHPBar(over: head)
    }

    /// Spawn body segments with a short stagger; each appears at the hole and slides
    /// back to its chained slot, then its joints are created.
    private func emergeBodySegments(in scene: GameScene,
                                    bodyCategory: UInt32,
                                    contact: UInt32,
                                    collide: UInt32)
    {
        guard let head = segments.first else { return }
        
        let back = CGVector(dx: -cos(desiredDir), dy: -sin(desiredDir))
        
        // Durations for the tiny pop/slide of each spawned segment
        let appearDur: TimeInterval = 0.10
        let slideDur:  TimeInterval = 0.10
        
        for i in 1..<segmentCount {
            // Stagger each segment spawn
            let body = self.makeSeg(radius: self.segmentRadius,
                                    color: .systemPink.withAlphaComponent(0.65),
                                    category: bodyCategory, contact: contact, collide: collide)
            
            body.alpha = 0
            body.worm = self
            
            body.setScale(0.60)
            body.position = head.position
            body.physicsBody?.isDynamic = false
            
            self.addChild(body)
            self.segments.append(body)
            
            let targetP = CGPoint(
                x: head.position.x + back.dx * self.spacing * CGFloat(i),
                y: head.position.y + back.dy * self.spacing * CGFloat(i)
            )
            
            let appear = SKAction.group([
                .fadeIn(withDuration: appearDur),
                .scale(to: 1.0, duration: appearDur),
                .move(to: targetP, duration: slideDur)
            ])
            
            let activate = SKAction.run { [weak self, weak body] in
                guard let self, let body = body else { return }
                body.physicsBody?.isDynamic = true
                
                // Connect to previous link
                let prevIndex = i - 1
                if prevIndex >= 0, prevIndex < self.segments.count {
                    self.connect(self.segments[prevIndex], body, in: scene)
                }
                
                if self.segments.count >= 3 { self.refreshHeadBackupTether(in: scene) }
                
                // ⬇️ NEW: when the last piece is in, unlock normal AI
                self.emergingSegmentsLeft = max(0, self.emergingSegmentsLeft - 1)
                if self.emergingSegmentsLeft == 0 {
                    self.isEmerging = false
                }
            }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.90) {
                body.run(.sequence([activate, appear]))
            }
        }
    }

    private func attachEyes(to head: WormSegmentNode) {
        // eye geometry scaled from head radius
        let forward: CGFloat = max(8, segmentRadius * 0.45)
        let spread:  CGFloat = max(6, segmentRadius * 0.35)
        let rEye:    CGFloat = max(4, segmentRadius * 0.22)
        let rPupil:  CGFloat = max(2, rEye * 0.55)

        let root = SKNode()
        root.name = "worm.eyes"
        root.zPosition = 12       // above head fill
        head.addChild(root)
        self.eyesRoot = root

        func makeEye() -> (eye: SKShapeNode, pupil: SKShapeNode) {
            let eye = SKShapeNode(circleOfRadius: rEye)
            eye.fillColor = .systemPurple.withAlphaComponent(0.2)
            eye.strokeColor = UIColor.black.withAlphaComponent(0.25)
            eye.lineWidth = 1

            let pupil = SKShapeNode(circleOfRadius: rPupil)
            pupil.fillColor = .systemRed
            pupil.strokeColor = UIColor.black.withAlphaComponent(0.25)
            pupil.lineWidth = 0.5

            eye.addChild(pupil)
            return (eye, pupil)
        }

        let L = makeEye()
        let R = makeEye()
        leftEye = L.eye; leftPupil = L.pupil
        rightEye = R.eye; rightPupil = R.pupil

        // Place eyes forward on the head, slightly apart vertically.
        L.eye.position = CGPoint(x: forward, y:  spread)
        R.eye.position = CGPoint(x: forward, y: -spread)

        root.addChild(L.eye)
        root.addChild(R.eye)

        // Start pupils looking “forward” within the sclera.
        let maxOff = rEye - rPupil - 1
        L.pupil.position = CGPoint(x: maxOff * 0.65, y: 0)
        R.pupil.position = CGPoint(x: maxOff * 0.65, y: 0)
    }

    private func updateEyes(head: WormSegmentNode, aimAngle: CGFloat) {
        guard let eyes = eyesRoot,
              let lEye = leftEye,
              let lP = leftPupil,
              let rP = rightPupil else { return }
        
        // Turn the eyes so their “forward” points toward aimAngle in world space.
        // Because eyes are children of head, subtract head.zRotation.
        eyes.zRotation = aimAngle - head.zRotation

        // Tiny pupil “look” bias toward the current target/heading.
        let eyeR   = (lEye.frame.width * 0.5)
        let pupilR = (lP.frame.width  * 0.5)
        let maxOff = max(1, eyeR - pupilR - 1)

        // Nudge a bit more when pursuing, a bit less when roaming.
        let lookFactor: CGFloat = (mode == .pursue) ? 0.8 : 0.55
        let px = maxOff * lookFactor

        lP.position = CGPoint(x: px, y: 0)
        rP.position = CGPoint(x: px, y: 0)
    }
    
    private func connect(_ a: WormSegmentNode, _ b: WormSegmentNode, in scene: SKScene) {
        guard let pa = a.physicsBody, let pb = b.physicsBody else { return }
        let aA = a.convert(CGPoint.zero, to: scene)
        let aB = b.convert(CGPoint.zero, to: scene)

        let spring = SKPhysicsJointSpring.joint(withBodyA: pa, bodyB: pb, anchorA: aA, anchorB: aB)
        spring.frequency = 1.8
        spring.damping   = 0.55
        scene.physicsWorld.add(spring)

        let limit = SKPhysicsJointLimit.joint(withBodyA: pa, bodyB: pb, anchorA: aA, anchorB: aB)
        limit.maxLength = spacing * 1.03
        scene.physicsWorld.add(limit)

        links.append(.init(a: a, b: b, spring: spring, limit: limit))
    }

    private func breakLinks(connectedTo s: WormSegmentNode) {
        guard let world = scene?.physicsWorld else { return }
        var keep: [Link] = []
        for L in links {
            if L.a === s || L.b === s {
                if let j = L.spring { world.remove(j) }
                if let j = L.limit  { world.remove(j) }
            } else {
                keep.append(L)
            }
        }
        links = keep
    }

    private func refreshHeadBackupTether(in scene: SKScene? = nil) {
        guard let world = self.scene?.physicsWorld ?? scene?.physicsWorld else { return }
        if let backup = headBackupLimit { world.remove(backup) }
        headBackupLimit = nil

        guard segments.count >= 3,
              let pa = segments[0].physicsBody,
              let pb = segments[2].physicsBody else { return }

        let aA = segments[0].convert(CGPoint.zero, to: self.scene!)
        let aB = segments[2].convert(CGPoint.zero, to: self.scene!)
        let limit = SKPhysicsJointLimit.joint(withBodyA: pa, bodyB: pb, anchorA: aA, anchorB: aB)
        limit.maxLength = spacing * 2.06   // slack tendon
        world.add(limit)
        headBackupLimit = limit
    }

    // MARK: Health bar (build hidden, auto show/hide on hit)
    private func prepareHPBar(over head: WormSegmentNode) {
        let w: CGFloat = 80, h: CGFloat = 8, r: CGFloat = 3, yOff: CGFloat = segmentRadius + 20
        hpBarRoot.removeAllChildren()
        hpBarRoot.zPosition = 10
        hpBarRoot.position = CGPoint(x: 0, y: yOff)
        hpBarRoot.alpha = 0
        hpBarRoot.isHidden = true

        let bgPath = CGPath(roundedRect: CGRect(x: -w/2, y: -h/2, width: w, height: h),
                            cornerWidth: r, cornerHeight: r, transform: nil)
        hpBarBG.path = bgPath
        hpBarBG.fillColor = UIColor(white: 0, alpha: 0.65)
        hpBarBG.strokeColor = UIColor.white.withAlphaComponent(0.18)
        hpBarBG.lineWidth = 1
        hpBarRoot.addChild(hpBarBG)

        hpBarFill.fillColor = UIColor.systemGreen.withAlphaComponent(0.92)
        hpBarFill.strokeColor = .clear
        hpBarRoot.addChild(hpBarFill)

        head.addChild(hpBarRoot)
    }

    private func showHPBar() {
        guard let head = segments.first else { return }
        if hpBarRoot.parent == nil { prepareHPBar(over: head) }
        hpBarRoot.removeAction(forKey: hpBarHideKey)
        hpBarRoot.isHidden = false
        if hpBarRoot.alpha < 0.99 {
            hpBarRoot.run(.fadeAlpha(to: 1.0, duration: hpBarFadeIn))
        }
    }

    private func scheduleHideHPBar() {
        hpBarRoot.removeAction(forKey: hpBarHideKey)
        let seq = SKAction.sequence([
            .wait(forDuration: hpBarHoldTime),
            .fadeOut(withDuration: hpBarFadeOut),
            .hide()
        ])
        hpBarRoot.run(seq, withKey: hpBarHideKey)
    }

    private func currentTotalHP() -> Int {
        segments.reduce(0) { $0 + max(0, $1.hp) }
    }

    private func updateHPBar() {
        guard maxTotalHP > 0 else { return }
        let frac = CGFloat(currentTotalHP()) / CGFloat(max(1, maxTotalHP))
        let w: CGFloat = 80, h: CGFloat = 8
        let cw = max(0, w * frac)
        let rr = min(3, h * 0.5)
        let path = CGMutablePath()
        if cw <= 0.0001 {
            path.addRect(.init(x: -w/2, y: -h/2, width: 0.0001, height: h))
        } else {
            path.addRoundedRect(in: CGRect(x: -w/2, y: -h/2, width: cw, height: h),
                                cornerWidth: rr, cornerHeight: rr)
        }
        hpBarFill.path = path
        hpBarFill.fillColor =
            (frac >= 0.66) ? UIColor.systemGreen.withAlphaComponent(0.92) :
            (frac >= 0.33) ? UIColor.systemYellow.withAlphaComponent(0.92) :
                             UIColor.systemRed.withAlphaComponent(0.92)

        // keep the bar upright (called on hit and while visible in update)
        if let head = segments.first {
            hpBarRoot.zRotation = -head.zRotation
        }
    }

    // MARK: Damage
    func damage(segment: WormSegmentNode, amount: Int, at p: CGPoint, in scene: GameScene) {
        guard segment.parent != nil else { return }
        segment.hp -= max(0, amount)
        scene.spawnDestructionFX(at: p, for: .rock)

        // Show/refresh HP bar like obstacles
        showHPBar()
        updateHPBar()
        scheduleHideHPBar()
        target?.notifyDealtDamage(amount)

        if segment.hp <= 0 {
            if segment.isHead || segments.count <= 3 {
                // kill the worm
                target?.notifyObstacleDestroyed()
                removeAllChildren()
                removeFromParent()
                return
            } else {
                // stitch chain around the dead link
                guard let idx = segments.firstIndex(of: segment) else { return }
                let prev = (idx > 0) ? segments[idx - 1] : nil
                let next = (idx + 1 < segments.count) ? segments[idx + 1] : nil

                breakLinks(connectedTo: segment)
                segment.removeFromParent()
                segments.remove(at: idx)

                if let a = prev, let b = next, let scn = scene as SKScene? {
                    connect(a, b, in: scn)
                }
                refreshHeadBackupTether()

                // HP bar update after topology change
                updateHPBar()
                scheduleHideHPBar()
            }
        }
    }

    // MARK: Update
    func update(dt: CGFloat, target: CarNode) { update(dt: dt, target: target as SKNode) }

    func update(dt: CGFloat, target: SKNode?) {
        guard let scene = self.scene,
              let head = segments.first,
              let headPB = head.physicsBody else { return }
        
        // --- While emerging: move straight along a fixed heading, no turning/wiggle ---
        if isEmerging {
            slitherT += dt * slitherFreq  // keep time if you want subtle anim; not used for steering

            // Lock the steering to the emergence direction
            desiredDir = emergeHeading

            // Constant forward thrust
            let thrustMag: CGFloat = headSpeed
            headPB.applyForce(CGVector(dx: cos(emergeHeading) * thrustMag,
                                       dy: sin(emergeHeading) * thrustMag))

            // Cap speed like usual (so the chain stays cohesive)
            let maxSpeed: CGFloat = 60
            let v = headPB.velocity
            let s2 = v.dx*v.dx + v.dy*v.dy
            if s2 > maxSpeed*maxSpeed {
                let s = maxSpeed / sqrt(s2)
                headPB.velocity = CGVector(dx: v.dx * s, dy: v.dy * s)
            }

            // Slightly higher damping on followers so the tail settles behind the head
            for s in segments.dropFirst() { s.physicsBody?.linearDamping = 1.3 }

            updateHPBar()
            return
        }

        slitherT += dt * slitherFreq
        let headWorld = head.convert(CGPoint.zero, to: scene)

        if let t = target {
            let d = hypot(t.position.x - headWorld.x, t.position.y - headWorld.y)
            switch mode {
            case .roam:   if d < attackStart { mode = .pursue }
            case .pursue: if d > attackStop  { mode = .roam }
            }
        } else { mode = .roam }

        var desired = roamDir
        if mode == .pursue, let t = target {
            desired = atan2(t.position.y - headWorld.y, t.position.x - headWorld.x)
        } else {
            nextWanderChange -= dt
            if nextWanderChange <= 0 {
                let v  = headPB.velocity
                let cur = (abs(v.dx) > 1 || abs(v.dy) > 1) ? atan2(v.dy, v.dx) : desiredDir
                roamDir = cur + CGFloat.random(in: (-.pi/3)...(.pi/3))
                nextWanderChange = CGFloat.random(in: 0.8...1.6)
            }
            if let gs = scene as? GameScene {
                let bounds = gs.worldBounds.insetBy(dx: 180, dy: 180)
                if !bounds.contains(headWorld) {
                    let centerDir = atan2(bounds.midY - headWorld.y, bounds.midX - headWorld.x)
                    roamDir = angleLerp(from: roamDir, to: centerDir, by: 0.25)
                }
            }
            desired = roamDir
        }

        let wiggle = sin(slitherT) * slitherAmp
        let want = desired + wiggle
        let err  = shortestSignedAngle(from: desiredDir, to: want)
        let step = CGFloat.clamp(err, -turnRate*dt, turnRate*dt)
        desiredDir += step
        
        let thrustMag: CGFloat = (mode == .pursue) ? headSpeed : headSpeed * 0.62
        let thrust = CGVector(dx: cos(desiredDir) * thrustMag,
                              dy: sin(desiredDir) * thrustMag)
        headPB.applyForce(thrust)

        // cap head linear speed (keeps chain cohesive)
        let maxSpeed: CGFloat = 30
        let v = headPB.velocity
        let s2 = v.dx*v.dx + v.dy*v.dy
        let m2 = maxSpeed * maxSpeed
        if s2 > m2 {
            let s = maxSpeed / sqrt(s2)
            headPB.velocity = CGVector(dx: v.dx * s, dy: v.dy * s)
        }

        for s in segments.dropFirst() { s.physicsBody?.linearDamping = 1.3 }

        // keep HP bar upright while it’s visible
        if !hpBarRoot.isHidden { hpBarRoot.zRotation = -head.zRotation }
        
        if let head = segments.first {
            updateEyes(head: head, aimAngle: desiredDir)
        }
    }
}

// MARK: - Back-compat alias for moveSpeed
extension WormNode: WormNodeSpeedConfigurable {
    var moveSpeed: CGFloat {
        get { headSpeed }
        set { headSpeed = newValue }
    }
}

/// Factory to keep your existing calls intact.
enum ObstacleFactory {
    static func make(_ kind: ObstacleKind) -> ObstacleNode {
        ObstacleNode(kind: kind)
    }
}
