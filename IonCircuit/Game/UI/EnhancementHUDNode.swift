//
//  EnhancementHUDNode.swift
//  IonCircuit
//
//  Created by Barak Ben Hur on 13/10/2025.
//

import SpriteKit
import UIKit

/// Matches the protocol you declared in GameScene.swift so we can be cleared via Obj-C fallback too.
@objc protocol EnhancementHUDClearing {
    func clearAll()
}

final class EnhancementHUDNode: SKNode, EnhancementHUDClearing {
    
    // MARK: - Public API -------------------------------------------------------
    
    /// Call whenever the scene size changes.
    func place(in size: CGSize) {
        hudWidth = size.width
        reflow()
        toastNode.position = CGPoint(x: 0, y: yTop + 36)
    }
    
    /// Tick once per frame.
    func step(_ dt: CGFloat) {
        // timers
        for (k, badge) in badges {
            guard let left = badge.timeLeft else { continue }
            let newLeft = max(0, left - Double(dt))
            badge.timeLeft = newLeft
            badge.updateRing()
            if newLeft <= 0.0001 {
                removeBadge(for: k, animated: true)
            }
        }
        // subtle float animation
        idleT += dt
        let wob = sin(idleT * 3.1) * 0.6
        container.position.y = yTop + wob
    }
    
    /// Show/refresh a timed enhancement badge (e.g. “x sec remaining”).
    func addTimed(_ kind: EnhancementKind, duration: TimeInterval) {
        let key = keyFor(kind)
        if let b = badges[key] {
            // refresh existing badge
            b.timeTotal = duration
            b.timeLeft  = duration
            b.pop()
            reorderAndTween()
        } else {
            let b = Badge(kind: kind, duration: duration, iconTex: icon(for: kind), tint: tint(for: kind))
            badges[key] = b
            container.addChild(b)
            reorderAndTween()
            b.appear()
        }
    }
    
    /// Toggle a **persistent** badge for an enhancement.
    /// Example: weapon mode, control boost, mini mode, active shield.
    func setPersistent(_ kind: EnhancementKind, active: Bool) {
        let key = keyFor(kind)
        if active {
            if let existing = badges[key] {
                // Already shown → give it a little ‘pop’
                existing.timeTotal = nil
                existing.timeLeft  = nil
                existing.pop()
                reorderAndTween()
            } else {
                let b = Badge(kind: kind, duration: nil, iconTex: icon(for: kind), tint: tint(for: kind))
                badges[key] = b
                container.addChild(b)
                reorderAndTween()
                b.appear()
            }
        } else {
            removeBadge(for: key, animated: true)
        }
    }
    
    /// Quick popup message (“HP +20”, etc.)
    func flashToast(_ text: String, tint: UIColor) {
        toastLabel.text = text
        toastRing.strokeColor = tint.withAlphaComponent(0.9)
        
        toastNode.removeAllActions()
        toastNode.alpha = 0
        toastNode.setScale(0.96)
        toastNode.isHidden = false
        
        let pop = SKAction.group([
            .fadeAlpha(to: 1, duration: 0.10),
            .scale(to: 1.02, duration: 0.10)
        ])
        pop.timingMode = .easeOut
        
        let settle = SKAction.group([
            .scale(to: 1.0, duration: 0.10)
        ])
        let hold = SKAction.wait(forDuration: 0.8)
        let out  = SKAction.group([
            .fadeOut(withDuration: 0.15),
            .scale(to: 0.98, duration: 0.15)
        ])
        toastNode.run(.sequence([pop, settle, hold, out, .hide()]))
    }
    
    /// Remove all badges immediately (used on death/respawn).
    @objc func clearAll() {
        for (_, b) in badges {
            b.removeAllActions()
            b.removeFromParent()
        }
        badges.removeAll()
        reorderAndTween()
    }
    
    // MARK: - Internals --------------------------------------------------------
    
    private let container = SKNode()
    private var hudWidth: CGFloat = 0
    private var idleT: CGFloat = 0
    
    // layout
    private var yTop: CGFloat { (20) + 6 } // relative to camera center; you can tweak
    private let gap: CGFloat = 8
    
    // registry
    private var badges: [String: Badge] = [:]
    
    // toast
    private let toastNode = SKNode()
    private let toastLabel = SKLabelNode(fontNamed: "Menlo-Bold")
    private let toastRing  = SKShapeNode()
    
    override init() {
        super.init()
        zPosition = 900
        
        // container for badges
        addChild(container)
        
        // toast
        let w: CGFloat = 160, h: CGFloat = 28
        let rr = CGPath(roundedRect: CGRect(x: -w/2, y: -h/2, width: w, height: h), cornerWidth: 12, cornerHeight: 12, transform: nil)
        let bg = SKShapeNode(path: rr)
        bg.fillColor = UIColor(white: 0, alpha: 0.52)
        bg.strokeColor = UIColor.white.withAlphaComponent(0.22)
        bg.lineWidth = 1.0
        toastNode.addChild(bg)
        
        toastLabel.fontSize = 13
        toastLabel.verticalAlignmentMode = .center
        toastLabel.horizontalAlignmentMode = .center
        toastLabel.fontColor = .white
        toastLabel.text = ""
        toastNode.addChild(toastLabel)
        
        let ring = CGMutablePath()
        ring.addEllipse(in: CGRect(x: -h/2-6, y: -h/2-6, width: h+12, height: h+12))
        toastRing.path = ring
        toastRing.strokeColor = UIColor.systemTeal.withAlphaComponent(0.9)
        toastRing.lineWidth = 2
        toastRing.glowWidth = 3
        toastRing.fillColor = .clear
        toastNode.addChild(toastRing)
        
        toastNode.isHidden = true
        addChild(toastNode)
    }
    
    required init?(coder: NSCoder) { fatalError() }
    
    // layout badges centered under the Speed/Heading row
    private func reflow() {
        var x: CGFloat = 0
        let sorted = badges.values.sorted { $0.sortIndex < $1.sortIndex }
        for b in sorted { x += b.size.width }
        x += CGFloat(max(0, sorted.count - 1)) * gap
        var cursor = -x/2
        for b in sorted {
            b.targetPos = CGPoint(x: cursor + b.size.width * 0.5, y: yTop)
            cursor += b.size.width + gap
        }
    }
    
    private func reorderAndTween() {
        reflow()
        for (_, b) in badges {
            b.moveToTarget()
        }
    }
    
    private func removeBadge(for key: String, animated: Bool) {
        guard let b = badges.removeValue(forKey: key) else { return }
        if animated {
            b.disappear { [weak self] in
                b.removeFromParent()
                self?.reorderAndTween()
            }
        } else {
            b.removeFromParent()
            reorderAndTween()
        }
    }
    
    private func keyFor(_ kind: EnhancementKind) -> String {
        switch kind {
        case .hp20:          return "hp20"
        case .shield20:      return "shield"
        case .weaponRapid:   return "rapid"
        case .weaponDamage:  return "damage"
        case .weaponSpread:  return "spread"
        case .control:     return "control"
        case .shrink:      return "shrink"
        @unknown default:    return "other"
        }
    }
    
    private func tint(for kind: EnhancementKind) -> UIColor {
        switch kind {
        case .hp20:         return .systemGreen
        case .shield20:     return .systemBlue
        case .weaponRapid:  return .systemYellow
        case .weaponDamage: return .systemOrange
        case .weaponSpread: return .systemPurple
        case .control:    return .systemTeal
        case .shrink:     return .magenta
        @unknown default:   return .white
        }
    }
    
    // minimalist vector icons for each kind
    private func icon(for kind: EnhancementKind) -> SKTexture {
        let sz = CGSize(width: 22, height: 22)
        let img = UIGraphicsImageRenderer(size: sz).image { ctx in
            let cg = ctx.cgContext
            cg.setLineWidth(2)
            cg.setLineCap(.round)
            UIColor.white.setStroke()
            UIColor.white.setFill()
            
            switch kind {
            case .hp20:
                // cross
                let r = CGRect(x: 9, y: 3, width: 4, height: 16)
                cg.fill(r); cg.fill(r.insetBy(dx: -6, dy: 6).offsetBy(dx: -2, dy: -6))
            case .shield20:
                // shield
                let p = UIBezierPath()
                p.move(to: CGPoint(x: 11, y: 3))
                p.addCurve(to: CGPoint(x: 19, y: 7), controlPoint1: CGPoint(x: 14, y: 3), controlPoint2: CGPoint(x: 19, y: 4))
                p.addCurve(to: CGPoint(x: 11, y: 19), controlPoint1: CGPoint(x: 19, y: 11), controlPoint2: CGPoint(x: 15, y: 16))
                p.addCurve(to: CGPoint(x: 3, y: 7), controlPoint1: CGPoint(x: 7, y: 16), controlPoint2: CGPoint(x: 3, y: 11))
                p.addCurve(to: CGPoint(x: 11, y: 3), controlPoint1: CGPoint(x: 3, y: 4), controlPoint2: CGPoint(x: 8, y: 3))
                p.close()
                p.lineWidth = 2
                p.stroke()
            case .weaponRapid:
                // lightning
                let p = UIBezierPath()
                p.move(to: CGPoint(x: 6, y: 18))
                p.addLine(to: CGPoint(x: 12, y: 10))
                p.addLine(to: CGPoint(x: 9, y: 10))
                p.addLine(to: CGPoint(x: 16, y: 4))
                p.addLine(to: CGPoint(x: 12, y: 12))
                p.addLine(to: CGPoint(x: 15, y: 12))
                p.close()
                p.fill()
            case .weaponDamage:
                // skull-ish
                cg.strokeEllipse(in: CGRect(x: 4, y: 4, width: 14, height: 12))
                cg.fillEllipse(in: CGRect(x: 8, y: 8, width: 3, height: 3))
                cg.fillEllipse(in: CGRect(x: 13, y: 8, width: 3, height: 3))
                cg.move(to: CGPoint(x: 8, y: 15)); cg.addLine(to: CGPoint(x: 8, y: 19))
                cg.move(to: CGPoint(x: 11, y: 15)); cg.addLine(to: CGPoint(x: 11, y: 19))
                cg.move(to: CGPoint(x: 14, y: 15)); cg.addLine(to: CGPoint(x: 14, y: 19))
                cg.strokePath()
            case .weaponSpread:
                // three bullets
                for i in 0..<3 {
                    let x = 6 + i*5
                    cg.stroke(CGRect(x: x, y: 5, width: 3, height: 12))
                }
            case .control:
                // steering wheel
                cg.strokeEllipse(in: CGRect(x: 3, y: 3, width: 16, height: 16))
                cg.move(to: CGPoint(x: 11, y: 4)); cg.addLine(to: CGPoint(x: 11, y: 20))
                cg.move(to: CGPoint(x: 4, y: 11)); cg.addLine(to: CGPoint(x: 18, y: 11))
                cg.strokePath()
            case .shrink:
                // inward arrows
                let p = UIBezierPath()
                p.move(to: CGPoint(x: 3, y: 11)); p.addLine(to: CGPoint(x: 9, y: 11))
                p.move(to: CGPoint(x: 19, y: 11)); p.addLine(to: CGPoint(x: 13, y: 11))
                p.move(to: CGPoint(x: 11, y: 3)); p.addLine(to: CGPoint(x: 11, y: 9))
                p.move(to: CGPoint(x: 11, y: 19)); p.addLine(to: CGPoint(x: 11, y: 13))
                UIColor.white.setStroke(); p.lineWidth = 2; p.lineCapStyle = .round; p.stroke()
            @unknown default:
                cg.strokeEllipse(in: CGRect(x: 4, y: 4, width: 14, height: 14))
            }
        }
        let t = SKTexture(image: img); t.filteringMode = .linear
        return t
    }
    
    // MARK: - Badge (inner class) ---------------------------------------------
    
    private final class Badge: SKNode {
        let kind: EnhancementKind
        let size = CGSize(width: 44, height: 28)
        var timeTotal: TimeInterval?
        var timeLeft: TimeInterval?
        
        var targetPos: CGPoint = .zero
        var sortIndex: Int { // fixed order for prettiness
            switch kind {
            case .hp20: return 0
            case .shield20: return 1
            case .weaponRapid: return 2
            case .weaponDamage: return 3
            case .weaponSpread: return 4
            case .control: return 5
            case .shrink: return 6
            @unknown default: return 7
            }
        }
        
        // visuals
        private let card = SKShapeNode()
        private let icon = SKSpriteNode()
        private let ring = SKShapeNode()
        private let glow = SKShapeNode()
        
        init(kind: EnhancementKind, duration: TimeInterval?, iconTex: SKTexture, tint: UIColor) {
            self.kind = kind
            super.init()
            self.timeTotal = duration
            self.timeLeft  = duration
            
            // card
            let rr = CGPath(roundedRect: CGRect(x: -size.width/2, y: -size.height/2, width: size.width, height: size.height), cornerWidth: 10, cornerHeight: 10, transform: nil)
            card.path = rr
            card.fillColor = UIColor(white: 0, alpha: 0.42)
            card.strokeColor = UIColor.white.withAlphaComponent(0.18)
            card.lineWidth = 1
            card.glowWidth = 2
            addChild(card)
            
            // glow line
            glow.path = rr
            glow.strokeColor = tint.withAlphaComponent(0.65)
            glow.lineWidth = 1.2
            glow.glowWidth = 2.0
            glow.fillColor = .clear
            glow.alpha = 0
            addChild(glow)
            
            // icon
            icon.texture = iconTex
            icon.size = CGSize(width: 22, height: 22)
            icon.position = CGPoint(x: -size.width/2 + 16 + 6, y: 0)
            icon.alpha = 0.95
            addChild(icon)
            
            // timer ring (only visible for timed badges)
            let r: CGFloat = 10.5
            let rect = CGRect(x: size.width/2 - 16 - r, y: -r, width: r*2, height: r*2)
            ring.strokeColor = tint.withAlphaComponent(0.95)
            ring.fillColor = .clear
            ring.lineWidth = 2.2
            ring.glowWidth = 3.5
            ring.path = circlePath(in: rect, fraction: (duration == nil ? 0 : 1))
            ring.alpha = (duration == nil) ? 0.0 : 1.0
            addChild(ring)
        }
        
        required init?(coder: NSCoder) { fatalError() }
        
        func appear() {
            removeAllActions()
            setScale(0.88); alpha = 0
            let up = SKAction.group([.fadeIn(withDuration: 0.14),
                                     .scale(to: 1.05, duration: 0.14)])
            up.timingMode = .easeOut
            let settle = SKAction.scale(to: 1.0, duration: 0.08)
            run(.sequence([up, settle]))
            // brief glow ping
            glow.removeAllActions()
            glow.alpha = 1
            glow.run(.sequence([.fadeAlpha(to: 0, duration: 0.35)]))
        }
        
        func pop() {
            let up = SKAction.scale(to: 1.08, duration: 0.08)
            let dn = SKAction.scale(to: 1.00, duration: 0.10)
            up.timingMode = .easeOut; dn.timingMode = .easeIn
            run(.sequence([up, dn]))
            glow.removeAllActions()
            glow.alpha = 1
            glow.run(.sequence([.fadeAlpha(to: 0, duration: 0.35)]))
        }
        
        func moveToTarget() {
            let move = SKAction.move(to: targetPos, duration: 0.14)
            move.timingMode = .easeOut
            run(move)
        }
        
        func disappear(_ done: @escaping ()->Void) {
            let out = SKAction.group([
                .fadeOut(withDuration: 0.12),
                .scale(to: 0.9, duration: 0.12)
            ])
            out.timingMode = .easeIn
            run(.sequence([out, .run(done)]))
        }
        
        func updateRing() {
            guard let total = timeTotal, let left = timeLeft else { return }
            let frac = max(0, min(1, left / max(0.0001, total)))
            let r: CGFloat = 10.5
            ring.alpha = 1.0
            ring.path = circlePath(in: CGRect(x: size.width/2 - 16 - r, y: -r, width: r*2, height: r*2), fraction: CGFloat(frac))
            
            // “about to expire” pulse
            if frac < 0.2, ring.action(forKey: "pulse") == nil {
                let up = SKAction.fadeAlpha(to: 1.0, duration: 0.10)
                let dn = SKAction.fadeAlpha(to: 0.55, duration: 0.18)
                ring.run(.repeatForever(.sequence([up, dn])), withKey: "pulse")
            } else if frac >= 0.2 {
                ring.removeAction(forKey: "pulse")
                ring.alpha = 1.0
            }
        }
        
        private func circlePath(in rect: CGRect, fraction f: CGFloat) -> CGPath {
            let p = CGMutablePath()
            let center = CGPoint(x: rect.midX, y: rect.midY)
            let r = rect.width * 0.5
            let start: CGFloat = .pi * 1.5
            let end: CGFloat = start - (.pi * 2 * f)
            p.addArc(center: center, radius: r, startAngle: start, endAngle: end, clockwise: true)
            return p
        }
    }
}
