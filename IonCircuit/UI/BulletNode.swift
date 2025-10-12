//
//  BulletNode.swift
//  IonCircuit
//
//  Created by Barak Ben Hur on 12/10/2025.
//

import SpriteKit
import UIKit

final class BulletNode: SKNode {
    private let body = SKShapeNode(circleOfRadius: 3.5)
    private let trail = SKEmitterNode()
    private let life: CGFloat

    init(velocity: CGVector, life: CGFloat = 1.0) {
        self.life = life
        super.init()

        // Visual core
        body.fillColor = .white
        body.strokeColor = UIColor.white.withAlphaComponent(0.25)
        body.lineWidth = 0.8
        body.glowWidth = 2.0
        addChild(body)

        // Physics
        let pb = SKPhysicsBody(circleOfRadius: 3.5)
        pb.affectedByGravity = false
        pb.allowsRotation = false
        pb.usesPreciseCollisionDetection = true
        pb.linearDamping = 0
        pb.friction = 0
        pb.categoryBitMask = Category.bullet
        pb.collisionBitMask = 0                           // no bounce; we handle impact in scene
        pb.contactTestBitMask = Category.wall | Category.obstacle
        pb.velocity = velocity
        self.physicsBody = pb

        // Trail (additive, short)
        trail.particleTexture = nil
        trail.particleBirthRate = 280
        trail.numParticlesToEmit = 0                      // continuous
        trail.particleLifetime = 0.25
        trail.particleLifetimeRange = 0.08
        trail.particleSpeed = 0
        trail.particleAlpha = 0.65
        trail.particleAlphaRange = 0.15
        trail.particleAlphaSpeed = -2.7
        trail.particleScale = 0.6
        trail.particleScaleRange = 0.2
        trail.particleScaleSpeed = -1.6
        trail.emissionAngleRange = .pi
        trail.particleColor = .white
        trail.particleBlendMode = .add
        addChild(trail)

        // Auto-remove after life
        run(.sequence([.wait(forDuration: Double(life)), .removeFromParent()]))
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func attach(to scene: SKScene) {
        trail.targetNode = scene
    }
}
