//
//  BulletNode.swift
//  IonCircuit
//
//  Created by Barak Ben Hur on 12/10/2025.
//

import SpriteKit

final class BulletNode: SKNode {

    // Visuals
    private let core: SKSpriteNode
    private let bloom: SKSpriteNode
    private let trail: SKEmitterNode

    init(velocity: CGVector, life: CGFloat) {
        // Textures (procedural, so no asset dependency)
        let coreTex  = BulletNode.makeRoundTex(px: 22)
        let bloomTex = BulletNode.makeRoundTex(px: 36)

        // Core (hot white)
        core = SKSpriteNode(texture: coreTex, color: .white, size: coreTex.size())
        core.colorBlendFactor = 1
        core.blendMode = .add
        core.alpha = 1.0
        core.setScale(0.55)

        // Bloom (cool tint, wide & soft)
        bloom = SKSpriteNode(texture: bloomTex, color: UIColor.systemTeal, size: bloomTex.size())
        bloom.colorBlendFactor = 0.85
        bloom.blendMode = .add
        bloom.alpha = 0.45
        bloom.setScale(0.85)
        bloom.zPosition = -1

        // Trail (short additive comet)
        trail = SKEmitterNode()
        trail.particleTexture = BulletNode.makeRoundTex(px: 16)
        trail.particleBirthRate = 0              // will be enabled in attach()
        trail.particleLifetime = 0.22
        trail.particleLifetimeRange = 0.06
        trail.particleSpeed = 0
        trail.particleAlpha = 0.8
        trail.particleAlphaSpeed = -3.6
        trail.particleScale = 0.18
        trail.particleScaleRange = 0.06
        trail.particleBlendMode = .add
        trail.particlePositionRange = CGVector(dx: 2, dy: 2)
        trail.zPosition = -2

        super.init()

        name = "bullet"
        zPosition = 900  // above world/hills/obstacles

        addChild(bloom)
        addChild(core)
        addChild(trail)

        // Physics
        let r: CGFloat = 4.0
        let body = SKPhysicsBody(circleOfRadius: r)
        body.isDynamic = true
        body.affectedByGravity = false
        body.allowsRotation = false
        body.friction = 0
        body.linearDamping = 0
        body.usesPreciseCollisionDetection = true

        body.categoryBitMask = Category.bullet
        body.contactTestBitMask = Category.obstacle | Category.wall
        body.collisionBitMask = Category.obstacle    // hit obstacles; pass through car/walls visually but get contact
        body.velocity = velocity
        physicsBody = body

        // Orient trail opposite the flight direction
        let heading = atan2(velocity.dy, velocity.dx)
        trail.emissionAngle = heading + .pi
        trail.emissionAngleRange = .pi / 10

        // Life / flicker
        let lifeT = TimeInterval(max(life, 0.05))
        run(.sequence([
            .repeat(.sequence([
                .run { [weak self] in self?.core.alpha = 0.95 + CGFloat.random(in: -0.05...0.0) },
                .wait(forDuration: 0.03)
            ]), count: Int(ceil(lifeT / 0.06))),
            .removeFromParent()
        ]))
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// Call after adding to scene so the emitter can render into scene space.
    func attach(to scene: SKScene) {
        trail.targetNode = scene
        trail.particleBirthRate = 1300
    }
}

// MARK: - Helpers
private extension BulletNode {
    static func makeRoundTex(px: CGFloat) -> SKTexture {
        let size = CGSize(width: px, height: px)
        let img = UIGraphicsImageRenderer(size: size).image { ctx in
            let cg = ctx.cgContext
            let colors = [UIColor.white.cgColor,
                          UIColor(white: 1.0, alpha: 0.0).cgColor] as CFArray
            let space = CGColorSpaceCreateDeviceRGB()
            let grad = CGGradient(colorsSpace: space, colors: colors, locations: [0, 1])!
            cg.drawRadialGradient(
                grad,
                startCenter: CGPoint(x: px/2, y: px/2), startRadius: 0,
                endCenter: CGPoint(x: px/2, y: px/2), endRadius: px/2,
                options: .drawsBeforeStartLocation
            )
        }
        let t = SKTexture(image: img)
        t.filteringMode = .linear
        return t
    }
}
