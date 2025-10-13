//
//  HillNode.swift
//  IonCircuit
//
//
//  Created by Barak Ben Hur on 13/10/2025.
//

import SpriteKit
import UIKit

final class HillNode: SKNode {
    // World-space frame and landing height (used by GameScene.groundHeight)
    let rectWorld: CGRect
    let topHeight: CGFloat

    // Internal shapes (local space)
    private let outerRect: CGRect
    private let innerRect: CGRect
    private let rimPath: CGPath
    private let corePath: CGPath

    // MARK: - Init
    init(rect: CGRect, height: CGFloat) {
        self.rectWorld  = rect
        self.topHeight  = height

        // Build geometry around origin, then place the node at rect center
        let w = rect.width
        let h = rect.height
        self.outerRect = CGRect(x: -w/2, y: -h/2, width: w, height: h)
        self.innerRect = outerRect.insetBy(dx: w*0.14, dy: h*0.14)

        self.rimPath  = CGPath(ellipseIn: outerRect, transform: nil)
        self.corePath = CGPath(ellipseIn: innerRect, transform: nil)

        super.init()
        self.position = CGPoint(x: rect.midX, y: rect.midY)
        self.name = "hill"

        buildUI()
        buildPhysics()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    // MARK: - UI
    private func buildUI() {
        // Drop shadow under the hill (soft, offset)
        let shadow = SKShapeNode(ellipseIn: outerRect.insetBy(dx: -10, dy: -6))
        shadow.fillColor = .black
        shadow.strokeColor = .clear
        shadow.alpha = 0.28
        shadow.position = CGPoint(x: 0, y: -10)
        shadow.zPosition = -2
        addChild(shadow)

        // Outer body with darker ring
        let body = SKShapeNode(path: rimPath)
        body.fillColor   = UIColor(hue: 0.33, saturation: 0.48, brightness: 0.34, alpha: 1)
        body.strokeColor = UIColor(hue: 0.33, saturation: 0.42, brightness: 0.55, alpha: 1)
        body.lineWidth   = 8
        body.glowWidth   = 2
        body.zPosition   = 0
        addChild(body)

        // Radial gradient core (gives real depth)
        let coreTex = Self.makeRadialGradient(size: innerRect.size,
                                              inner: UIColor(hue: 0.33, saturation: 0.26, brightness: 0.54, alpha: 1),
                                              outer: UIColor(hue: 0.33, saturation: 0.44, brightness: 0.38, alpha: 1))
        let core = SKSpriteNode(texture: coreTex, size: innerRect.size)
        core.position = .zero
        core.zPosition = 0.1
        addChild(core)

        // Inner rim line for separation
        let innerRim = SKShapeNode(path: corePath)
        innerRim.strokeColor = UIColor(white: 1, alpha: 0.08)
        innerRim.lineWidth   = 2
        innerRim.fillColor   = .clear
        innerRim.zPosition   = 0.12
        addChild(innerRim)

        // Directional rim highlight (light from top-left)
        let hl = SKShapeNode()
        let arc = CGMutablePath()
        arc.addArc(center: .zero,
                   radius: max(outerRect.width, outerRect.height) * 0.52,
                   startAngle: .pi * 1.15, endAngle: .pi * 1.7, clockwise: false)
        hl.path = arc
        hl.strokeColor = UIColor(white: 1.0, alpha: 0.08)
        hl.lineWidth = 10
        hl.glowWidth = 6
        hl.zPosition = 0.2
        addChild(hl)
    }

    // MARK: - Physics
    private func buildPhysics() {
        // A thin edge loop around the outer rim acts as a "wall".
        // Cars cannot drive up unless they jump over it.
        let pb = SKPhysicsBody(edgeLoopFrom: rimPath)
        pb.isDynamic = false
        pb.friction = 0.8
        pb.restitution = 0.05
        pb.categoryBitMask = Category.wall
        pb.collisionBitMask = Category.car | Category.obstacle | Category.bullet
        pb.contactTestBitMask = 0
        self.physicsBody = pb
    }

    // MARK: - Query
    /// True if the world point is over the plateau (inner ellipse).
    func containsTop(_ pWorld: CGPoint, in scene: SKScene?) -> Bool {
        guard let scene else { return false }
        let pLocal = convert(pWorld, from: scene)
        return corePath.contains(pLocal)
    }

    // MARK: - Texture helper
    private static func makeRadialGradient(size: CGSize, inner: UIColor, outer: UIColor) -> SKTexture {
        let px = max(2, Int(ceil(max(size.width, size.height))))
        let img = UIGraphicsImageRenderer(size: CGSize(width: px, height: px)).image { ctx in
            let cg = ctx.cgContext
            let colors = [inner.cgColor, outer.cgColor] as CFArray
            let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1])!
            cg.drawRadialGradient(
                grad,
                startCenter: CGPoint(x: CGFloat(px)/2, y: CGFloat(px)/2), startRadius: 0,
                endCenter:   CGPoint(x: CGFloat(px)/2, y: CGFloat(px)/2), endRadius: CGFloat(px)/2,
                options: .drawsAfterEndLocation
            )
        }
        let t = SKTexture(image: img)
        t.filteringMode = .linear
        return t
    }
}
