//
//  RampNode.swift
//  IonCircuit
//
//
//  Created by Barak Ben Hur on 13/10/2025.
//

import SpriteKit
import UIKit

final class RampNode: SKNode {
    // Gameplay params (read by GameScene)
    let heading: CGFloat        // world angle you launch along
    let strengthZ: CGFloat      // vertical impulse baseline

    // Local geometry (tip points along local +Y)
    private let rampSize: CGSize
    private let rampPath: CGPath

    // MARK: - Init
    init(center: CGPoint, size: CGSize, heading: CGFloat, strengthZ: CGFloat) {
        self.rampSize  = size
        self.heading   = heading
        self.strengthZ = strengthZ

        // Triangle pointing up in local space
        let w = size.width
        let h = size.height
        let p = CGMutablePath()
        p.move(to: CGPoint(x: -w/2, y: -h/2))
        p.addLine(to: CGPoint(x:  w/2, y: -h/2))
        p.addLine(to: CGPoint(x:  0.0, y:  h/2))
        p.closeSubpath()
        self.rampPath = p

        super.init()
        self.position = center
        // Align local +Y to the desired heading
        self.zRotation = heading - (.pi/2)
        self.name = "ramp"

        buildUI()
        buildPhysics()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    // MARK: - UI
    private func buildUI() {
        // Drop shadow
        let sh = SKShapeNode(path: rampPath)
        sh.fillColor = .black
        sh.strokeColor = .clear
        sh.alpha = 0.25
        sh.position = CGPoint(x: 0, y: -8)
        sh.zPosition = -1
        addChild(sh)

        // Beveled fill via gradient sprite
        let tex = Self.makeLinearGradient(size: rampSize,
                                          start: UIColor(hue: 0.53, saturation: 0.35, brightness: 0.85, alpha: 0.95),
                                          end:   UIColor(hue: 0.53, saturation: 0.60, brightness: 0.45, alpha: 0.95),
                                          vertical: true)
        let sprite = SKSpriteNode(texture: tex, size: rampSize)
        sprite.zRotation = 0     // already oriented by node rotation
        sprite.zPosition = 0.1

        // Mask sprite to triangle
        let mask = SKShapeNode(path: rampPath)
        mask.fillColor = .white
        mask.strokeColor = .clear
        let crop = SKCropNode()
        crop.maskNode = mask
        crop.zPosition = 0.1
        crop.addChild(sprite)
        addChild(crop)

        // Edge strokes
        let edge = SKShapeNode(path: rampPath)
        edge.fillColor = .clear
        edge.strokeColor = UIColor(white: 1, alpha: 0.14)
        edge.lineWidth = 2.0
        edge.glowWidth = 2.0
        edge.zPosition = 0.2
        addChild(edge)

        // Chevrons pointing “up-ramp”
        let chevNode = SKNode()
        let chevCount = max(2, Int(rampSize.height / 80))
        for i in 0..<chevCount {
            let t = CGFloat(i) / CGFloat(max(1, chevCount - 1))
            let y = -rampSize.height/2 + 18 + t * (rampSize.height - 36)
            let c = Self.chevronPath(width: rampSize.width * (0.25 + 0.2 * (1 - t)), height: 10)
            let s = SKShapeNode(path: c)
            s.position = CGPoint(x: 0, y: y)
            s.lineWidth = 2
            s.strokeColor = UIColor.white.withAlphaComponent(0.75 - 0.55*t)
            s.glowWidth = 1.8
            s.zPosition = 0.25
            chevNode.addChild(s)
        }
        addChild(chevNode)
    }

    // MARK: - Physics
    private func buildPhysics() {
        let pb = SKPhysicsBody(polygonFrom: rampPath)
        pb.isDynamic = false
        pb.affectedByGravity = false
        pb.friction = 0.9
        pb.restitution = 0.0
        pb.categoryBitMask = Category.ramp
        pb.collisionBitMask = Category.car | Category.obstacle | Category.wall
        pb.contactTestBitMask = Category.car
        pb.usesPreciseCollisionDetection = true
        self.physicsBody = pb
    }

    // MARK: - Helpers
    private static func chevronPath(width: CGFloat, height: CGFloat) -> CGPath {
        let w = width, h = height
        let p = CGMutablePath()
        p.move(to: CGPoint(x: -w/2, y: -h/2))
        p.addLine(to: CGPoint(x: 0,     y:  h/2))
        p.addLine(to: CGPoint(x:  w/2,  y: -h/2))
        return p
    }

    private static func makeLinearGradient(size: CGSize, start: UIColor, end: UIColor, vertical: Bool) -> SKTexture {
        let img = UIGraphicsImageRenderer(size: size).image { ctx in
            let cg = ctx.cgContext
            let colors = [start.cgColor, end.cgColor] as CFArray
            let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0,1])!
            let s = CGPoint(x: 0, y: 0), e = CGPoint(x: vertical ? 0 : size.width, y: vertical ? size.height : 0)
            cg.addPath(CGPath(rect: CGRect(origin: .zero, size: size), transform: nil))
            cg.clip()
            cg.drawLinearGradient(grad, start: s, end: e, options: [])
        }
        let t = SKTexture(image: img)
        t.filteringMode = .linear
        return t
    }
}
