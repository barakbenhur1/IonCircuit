//
//  TrackNode.swift
//  IonCircuit
//
//  Created by Barak Ben Hur on 12/10/2025.
//

import SpriteKit

/// A closed loop path rendered as a filled "track".
/// Optionally places small barrier dots along the edges to collide with.
final class TrackNode: SKNode {

    struct Config {
        var center: CGPoint
        var radius: CGFloat
        var wobble: CGFloat = 120
        var width: CGFloat  = 120
        var barrierEvery: CGFloat = 80  // approx spacing, set 0 to disable
    }

    private let cfg: Config
    private(set) var checkpoints: [SKNode] = []

    init(config: Config) {
        self.cfg = config
        super.init()
        build()
    }
    required init?(coder: NSCoder) { fatalError() }

    private func build() {
        // Build a wobbly closed path around center
        let steps = 64
        let p = CGMutablePath()
        for i in 0..<steps {
            let t = CGFloat(i) / CGFloat(steps) * 2 * .pi
            let r = cfg.radius + CGFloat.random(in: -cfg.wobble...cfg.wobble)
            let x = cfg.center.x + cos(t) * r
            let y = cfg.center.y + sin(t) * r
            if i == 0 { p.move(to: CGPoint(x: x, y: y)) }
            else { p.addLine(to: CGPoint(x: x, y: y)) }
        }
        p.closeSubpath()

        // Draw track by stroking the path thickly
        let track = SKShapeNode(path: p)
        track.lineWidth = cfg.width
        track.strokeColor = .darkGray
        track.fillColor = .clear
        track.glowWidth = 2
        addChild(track)

        // Barriers (collidable pebbles along each side)
        if cfg.barrierEvery > 0 {
            let lengthApprox = 2 * .pi * cfg.radius
            let count = Int(lengthApprox / cfg.barrierEvery)
            for i in 0..<count {
                let t = CGFloat(i) / CGFloat(count) * 2 * .pi
                for side in [-1, 1] {
                    let offset = (cfg.width/2) * CGFloat(side)
                    let x = cfg.center.x + cos(t) * (cfg.radius + offset)
                    let y = cfg.center.y + sin(t) * (cfg.radius + offset)
                    let dot = SKShapeNode(circleOfRadius: 10)
                    dot.fillColor = .gray
                    dot.strokeColor = .clear
                    dot.position = CGPoint(x: x, y: y)
                    addChild(dot)

                    let pb = SKPhysicsBody(circleOfRadius: 10)
                    pb.isDynamic = false
                    pb.categoryBitMask = Category.wall
                    pb.collisionBitMask = UInt32.max
                    pb.contactTestBitMask = 0
                    dot.physicsBody = pb
                }
            }
        }

        // Simple start/finish checkpoint (sensor)
        let flag = SKShapeNode(rectOf: CGSize(width: cfg.width * 0.8, height: 12), cornerRadius: 6)
        flag.fillColor = .white
        flag.strokeColor = .clear
        flag.position = CGPoint(x: cfg.center.x + cfg.radius, y: cfg.center.y)
        addChild(flag)

        let cpBody = SKPhysicsBody(rectangleOf: flag.frame.size)
        cpBody.isDynamic = false
        cpBody.categoryBitMask = Category.checkpoint
        cpBody.collisionBitMask = 0
        cpBody.contactTestBitMask = Category.car
        flag.physicsBody = cpBody
        checkpoints = [flag]
    }
}
