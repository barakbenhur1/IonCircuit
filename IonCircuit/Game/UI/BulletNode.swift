//
//  BulletNode.swift
//  IonCircuit
//
//  Created by Barak Ben Hur on 12/10/2025.
//

import SpriteKit
import UIKit

enum ShotStyle {
    case rapid, damage, spread

    struct Look {
        let coreRadius: CGFloat
        let coreColor: UIColor
        let glowRadius: CGFloat
        let glowAlpha: CGFloat
        let trailLen: CGFloat
        let trailWidth: CGFloat
        let ttl: TimeInterval
    }

    var look: Look {
        switch self {
        case .rapid:
            return .init(coreRadius: 3.2,
                         coreColor: .white,
                         glowRadius: 10,
                         glowAlpha: 0.7,
                         trailLen: 28,
                         trailWidth: 2.0,
                         ttl: 1.1)
        case .damage:
            return .init(coreRadius: 5.6,
                         coreColor: .systemOrange,
                         glowRadius: 16,
                         glowAlpha: 0.9,
                         trailLen: 36,
                         trailWidth: 3.2,
                         ttl: 1.4)
        case .spread:
            return .init(coreRadius: 4.4,
                         coreColor: .systemPurple,
                         glowRadius: 12,
                         glowAlpha: 0.8,
                         trailLen: 18,
                         trailWidth: 2.6,
                         ttl: 0.9)
        }
    }

    var impactColor: UIColor {
        switch self {
        case .rapid:  return .systemYellow
        case .damage: return .orange
        case .spread: return .systemPurple
        }
    }
}

final class BulletNode: SKNode {
    let damage: Int
    let style: ShotStyle

    private let core  = SKShapeNode()
    private let glow  = SKShapeNode()
    private let trail = SKShapeNode()

    private var trailBaseLen: CGFloat = 24
    private let spawnT: CFTimeInterval = CACurrentMediaTime()

    init(style: ShotStyle, damage: Int) {
        self.damage = damage
        self.style = style
        super.init()
        zPosition = 500

        let look = style.look
        trailBaseLen = look.trailLen

        // CORE (centered) — no stroke → no hairline
        core.path = CGPath(ellipseIn: CGRect(x: -look.coreRadius,
                                             y: -look.coreRadius,
                                             width: look.coreRadius * 2,
                                             height: look.coreRadius * 2),
                           transform: nil)
        core.fillColor = look.coreColor
        core.strokeColor = .clear
        core.lineWidth = 0
        core.blendMode = .add
        core.isAntialiased = false
        addChild(core)

        // GLOW (centered), additive, no stroke
        glow.path = CGPath(ellipseIn: CGRect(x: -look.glowRadius,
                                             y: -look.glowRadius,
                                             width: look.glowRadius * 2,
                                             height: look.glowRadius * 2),
                           transform: nil)
        glow.fillColor = look.coreColor.withAlphaComponent(look.glowAlpha * 0.35)
        glow.strokeColor = .clear
        glow.lineWidth = 0
        glow.blendMode = .add
        glow.isAntialiased = false
        addChild(glow)

        // TRAIL: filled rounded-rect (points down −Y). Start invisible.
        let w = look.trailWidth, h = max(1, look.trailLen)
        trail.path = CGPath(roundedRect: CGRect(x: -w/2, y: -h, width: w, height: h),
                            cornerWidth: w/2, cornerHeight: w/2, transform: nil)
        trail.fillColor = look.coreColor.withAlphaComponent(0.9)
        trail.strokeColor = .clear
        trail.lineWidth = 0
        trail.blendMode  = .add
        trail.isAntialiased = false
        trail.zPosition = -1
        trail.alpha = 0.0 // ← hide until moving
        addChild(trail)

        // Flavor micro-anims (subtle, no alpha pulsing that can reveal slivers)
        switch style {
        case .rapid:
            core.run(.repeatForever(.sequence([.scale(to: 1.05, duration: 0.06),
                                               .scale(to: 1.00, duration: 0.08)])))
        case .damage:
            core.run(.repeatForever(.sequence([.scale(to: 1.12, duration: 0.08),
                                               .scale(to: 1.00, duration: 0.10)])))
        case .spread:
            let wob = SKAction.sequence([
                .rotate(byAngle: 0.03, duration: 0.06),
                .rotate(byAngle: -0.06, duration: 0.12),
                .rotate(byAngle: 0.03, duration: 0.06)
            ])
            run(.repeatForever(wob))
        }

        // PHYSICS — no gravity, precise
        let body = SKPhysicsBody(circleOfRadius: max(look.coreRadius, 4))
        body.isDynamic = true
        body.affectedByGravity = false
        body.fieldBitMask = 0
        body.usesPreciseCollisionDetection = true
        body.allowsRotation = false
        body.friction = 0
        body.restitution = 0
        body.linearDamping = 0
        body.angularDamping = 0
        body.categoryBitMask = Category.bullet
        body.collisionBitMask = Category.wall | Category.obstacle
        body.contactTestBitMask = Category.wall | Category.obstacle | Category.hole
        physicsBody = body

        // Frame-by-frame orientation & trail management
        run(followVelocity(duration: look.ttl))

        // Lifetime
        run(.sequence([
            .wait(forDuration: look.ttl),
            .fadeOut(withDuration: 0.06),
            .removeFromParent()
        ]))
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func followVelocity(duration: TimeInterval) -> SKAction {
        .customAction(withDuration: duration) { [weak self] node, _ in
            guard let self = self, let pb = self.physicsBody else { return }
            let v = pb.velocity
            let sp = hypot(v.dx, v.dy)

            // Align nose to velocity (our trail points to −Y in local space)
            if sp > 1 {
                node.zRotation = atan2(v.dy, v.dx) - .pi/2
            }

            // First frames after spawn → force-trail hidden to avoid sliver
            let since = CACurrentMediaTime() - self.spawnT
            let speedOK = sp >= 60
            let timeOK  = since >= 0.03

            // Compute trail length; collapse to 0 when slow to avoid any 1-px artifact
            if speedOK && timeOK {
                let k = CGFloat.clamp(sp / 1400.0, 0.25, 1.4)
                let len = max(2, self.trailBaseLen * (0.7 + 0.6 * k))
                let w = self.style.look.trailWidth
                self.trail.path = CGPath(roundedRect: CGRect(x: -w/2, y: -len, width: w, height: len),
                                         cornerWidth: w/2, cornerHeight: w/2, transform: nil)
                self.trail.alpha = 0.9
            } else {
                // Collapse the trail geometry and hide it completely
                let w = self.style.look.trailWidth
                self.trail.path = CGPath(roundedRect: CGRect(x: -w/2, y: 0, width: w, height: 0.001),
                                         cornerWidth: w/2, cornerHeight: w/2, transform: nil)
                self.trail.alpha = 0.0
            }

            // Glow gets a tiny boost with speed
            self.glow.alpha = 0.28 + 0.50 * min(1, sp / 900.0)
        }
    }

    func playImpactFX(at p: CGPoint, in scene: SKScene) {
        let color = style.impactColor

        let ring = SKShapeNode(circleOfRadius: 6)
        ring.position = p
        ring.strokeColor = color.withAlphaComponent(0.95)
        ring.lineWidth = 3
        ring.fillColor = .clear
        ring.zPosition = 900
        ring.blendMode = .add
        ring.isAntialiased = false
        scene.addChild(ring)

        let ringDur: TimeInterval = (style == .damage) ? 0.26 : 0.18
        ring.run(.sequence([
            .group([.scale(to: (style == .damage) ? 5.0 : 3.6, duration: ringDur),
                    .fadeOut(withDuration: ringDur)]),
            .removeFromParent()
        ]))

        if style == .damage {
            for _ in 0..<6 {
                let spark = SKShapeNode(circleOfRadius: 2.2)
                spark.position = p
                spark.fillColor = .white
                spark.strokeColor = .clear
                spark.alpha = 0.9
                spark.blendMode = .add
                spark.isAntialiased = false
                scene.addChild(spark)
                let dx = CGFloat.random(in: -36...36)
                let dy = CGFloat.random(in: 10...52)
                spark.run(.sequence([
                    .group([.moveBy(x: dx, y: dy, duration: 0.18),
                            .fadeOut(withDuration: 0.18)]),
                    .removeFromParent()
                ]))
            }
        } else if style == .rapid {
            let streak = SKShapeNode(rectOf: CGSize(width: 16, height: 2), cornerRadius: 1)
            streak.position = p
            streak.fillColor = color.withAlphaComponent(0.9)
            streak.strokeColor = .clear
            streak.blendMode = .add
            streak.isAntialiased = false
            scene.addChild(streak)
            streak.run(.sequence([
                .group([.scaleX(to: 2.2, duration: 0.08),
                        .fadeOut(withDuration: 0.08)]),
                .removeFromParent()
            ]))
        } else {
            let puff = SKShapeNode(circleOfRadius: 5)
            puff.position = p
            puff.fillColor = color.withAlphaComponent(0.35)
            puff.strokeColor = .clear
            puff.lineWidth = 0
            puff.blendMode = .add
            puff.isAntialiased = false
            scene.addChild(puff)
            puff.run(.sequence([
                .group([.scale(to: 1.8, duration: 0.14),
                        .fadeOut(withDuration: 0.14)]),
                .removeFromParent()
            ]))
        }
    }
}
