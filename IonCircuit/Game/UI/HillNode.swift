//
//  HillNode.swift
//  IonCircuit
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
        // soft ground shadow under the hill
        let shadow = SKShapeNode(ellipseIn: outerRect.insetBy(dx: -18, dy: -16))
        shadow.fillColor = .black
        shadow.strokeColor = .clear
        shadow.alpha = 0.28
        shadow.position = CGPoint(x: 0, y: -12)
        shadow.zPosition = -2
        shadow.isAntialiased = true
        addChild(shadow)

        // pre-rendered hill texture (dome shading + contour lines + rim AO)
        let tex = Self.makeHillTexture(
            outerSize: outerRect.size,
            innerSize: innerRect.size,
            hue: 0.33,                  // green-ish
            lightDirection: .pi * 1.25  // light from top-left
        )
        let sprite = SKSpriteNode(texture: tex, size: outerRect.size)
        sprite.zPosition = 0
        sprite.blendMode = .alpha
        addChild(sprite)
    }
    
    private static func makeHillTexture(
        outerSize: CGSize,
        innerSize: CGSize,
        hue: CGFloat,
        lightDirection: CGFloat
    ) -> SKTexture {
        let fmt = UIGraphicsImageRendererFormat.default()
        fmt.opaque = false                                // <- crucial: no black box
        let img = UIGraphicsImageRenderer(size: outerSize, format: fmt).image { ctx in
            let cg = ctx.cgContext
            let W = outerSize.width, H = outerSize.height
            let outerR = CGRect(origin: .zero, size: outerSize)
            let center = CGPoint(x: W*0.5, y: H*0.5)

            // Clear to transparent
            cg.setBlendMode(.copy)
            cg.setFillColor(UIColor.clear.cgColor)
            cg.fill(outerR)
            cg.setBlendMode(.normal)

            // Clip to outer ellipse — all drawing stays inside the hill
            cg.addEllipse(in: outerR)
            cg.clip()

            // --- Base dome gradient (darker rim → lighter center)
            let baseGrad = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: [
                    UIColor(hue: hue, saturation: 0.52, brightness: 0.28, alpha: 1).cgColor, // rim
                    UIColor(hue: hue, saturation: 0.38, brightness: 0.52, alpha: 1).cgColor, // mid
                    UIColor(hue: hue, saturation: 0.26, brightness: 0.62, alpha: 1).cgColor  // center
                ] as CFArray,
                locations: [0.0, 0.55, 1.0]
            )!
            let rimR = max(W, H) * 0.50
            let innerR = min(innerSize.width, innerSize.height) * 0.50
            cg.drawRadialGradient(
                baseGrad,
                startCenter: center, startRadius: rimR,    // from rim…
                endCenter:   center, endRadius: innerR,    // …to center
                options: [.drawsAfterEndLocation]
            )

            // --- Ambient “vignette” at the outer edge (soft AO toward rim)
            let rimAO = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: [UIColor(white: 0, alpha: 0.30).cgColor,
                         UIColor(white: 0, alpha: 0.0).cgColor] as CFArray,
                locations: [0, 1]
            )!
            cg.drawRadialGradient(
                rimAO,
                startCenter: center, startRadius: min(W, H)*0.36,
                endCenter:   center, endRadius: max(W, H)*0.52,
                options: [.drawsAfterEndLocation]
            )

            // --- Directional highlight (specular lobe toward the light)
            let hlC = CGPoint(x: center.x + cos(lightDirection) * W * 0.18,
                              y: center.y + sin(lightDirection) * H * 0.18)
            let spec = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: [UIColor(white: 1, alpha: 0.35).cgColor,
                         UIColor(white: 1, alpha: 0.0).cgColor] as CFArray,
                locations: [0, 1]
            )!
            cg.drawRadialGradient(
                spec,
                startCenter: hlC, startRadius: 0,
                endCenter:   hlC, endRadius: min(W, H)*0.28,
                options: [.drawsAfterEndLocation]
            )

            // --- Contour “curves” (topographic rings between inner and outer)
            let rings = 7
            let insetDX = (W - innerSize.width) * 0.5
            let insetDY = (H - innerSize.height) * 0.5
            for i in 0..<rings {
                let t = CGFloat(i + 1) / CGFloat(rings + 1) // 0→1 (outer→inner)
                let aBright = 0.10 * pow(1 - t, 0.8)        // brighter near center
                let aDark   = 0.06 * pow(1 - t, 0.8)

                let rect = outerR.insetBy(dx: insetDX * t, dy: insetDY * t)
                cg.setLineWidth(2)
                // bright ridge
                cg.setStrokeColor(UIColor(white: 1, alpha: aBright).cgColor)
                cg.strokeEllipse(in: rect)
                // shadowed lower side of the same ring (directional)
                cg.saveGState()
                cg.addEllipse(in: rect)
                cg.replacePathWithStrokedPath()
                cg.clip()

                let shadowC = CGPoint(x: center.x + cos(lightDirection + .pi) * W * 0.08,
                                      y: center.y + sin(lightDirection + .pi) * H * 0.08)
                let band = CGGradient(
                    colorsSpace: CGColorSpaceCreateDeviceRGB(),
                    colors: [UIColor(white: 0, alpha: aDark).cgColor,
                             UIColor(white: 0, alpha: 0).cgColor] as CFArray,
                    locations: [0, 1]
                )!
                cg.drawRadialGradient(
                    band,
                    startCenter: shadowC, startRadius: 0,
                    endCenter:   shadowC, endRadius: max(W, H)*0.6,
                    options: [.drawsAfterEndLocation]
                )
                cg.restoreGState()
            }
        }

        let t = SKTexture(image: img)
        t.filteringMode = .linear
        return t
    }

    // MARK: - Physics
    private func buildPhysics() {
        // Thin edge loop around the outer rim (still blocks bullets/obstacles)
        let pb = SKPhysicsBody(edgeLoopFrom: rimPath)
        pb.isDynamic = false
        pb.friction = 0.8
        pb.restitution = 0.05

        // Keep whatever category you use for static geometry. Category.wall is fine.
        pb.categoryBitMask = Category.wall

        // ❗ One-way: DO NOT collide with cars
        pb.collisionBitMask = Category.obstacle | Category.bullet | Category.car  // ← removed Category.car

        // Still let bullets register hits on the hill so they pop on impact
        pb.contactTestBitMask = Category.bullet

        self.physicsBody = pb
    }
    
    // MARK: - Query
    /// True if the world point is over the plateau (inner ellipse).
    func containsTop(_ pWorld: CGPoint, in scene: SKScene?) -> Bool {
        guard let scene else { return false }
        let pLocal = convert(pWorld, from: scene)
        return corePath.contains(pLocal)
    }
    
    // MARK: - Texture helpers
    private static func makeRadialGradient(size: CGSize, inner: UIColor, outer: UIColor) -> SKTexture {
        let w = max(2, Int(ceil(size.width)))
        let h = max(2, Int(ceil(size.height)))
        let px = CGSize(width: w, height: h)

        let img = UIGraphicsImageRenderer(size: px).image { ctx in
            let cg = ctx.cgContext

            // Clip drawing to an ellipse the size of the texture
            let ellipseRect = CGRect(origin: .zero, size: px)
            cg.addEllipse(in: ellipseRect)
            cg.clip()

            // Radial gradient (center → edge)
            let colors = [inner.cgColor, outer.cgColor] as CFArray
            let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1])!
            let c = CGPoint(x: px.width/2, y: px.height/2)
            let endR = max(px.width, px.height) * 0.5

            cg.drawRadialGradient(
                grad,
                startCenter: c, startRadius: 0,
                endCenter:   c, endRadius: endR,
                options: [.drawsAfterEndLocation]
            )
        }

        let t = SKTexture(image: img)
        t.filteringMode = .linear
        return t
    }
    
    /// Even-odd “donut” with a smooth dark-to-transparent gradient from the outer edge toward the inner edge.
    private static func makeRingAOTexture(outerSize: CGSize, innerSize: CGSize, outerAlpha: CGFloat) -> SKTexture {
        let w = max(2, Int(ceil(outerSize.width)))
        let h = max(2, Int(ceil(outerSize.height)))
        let img = UIGraphicsImageRenderer(size: CGSize(width: w, height: h)).image { ctx in
            let cg = ctx.cgContext
            cg.saveGState()
            
            // Build even-odd ring path (outer oval minus inner oval)
            let outerR = CGRect(x: 0, y: 0, width: CGFloat(w), height: CGFloat(h))
            let innerR = CGRect(
                x: (CGFloat(w) - innerSize.width) * 0.5,
                y: (CGFloat(h) - innerSize.height) * 0.5,
                width: innerSize.width, height: innerSize.height
            )
            
            let ring = UIBezierPath(ovalIn: outerR)
            ring.append(UIBezierPath(ovalIn: innerR))
            ring.usesEvenOddFillRule = true
            ring.addClip() // clip drawing to the ring
            
            // Radial gradient: darker at the very outside → transparent near the inner edge
            let colors = [UIColor(white: 0, alpha: outerAlpha).cgColor,
                          UIColor(white: 0, alpha: 0.0).cgColor] as CFArray
            let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1])!
            
            let c = CGPoint(x: CGFloat(w)/2, y: CGFloat(h)/2)
            let startRadius = min(innerSize.width, innerSize.height) * 0.50 * 0.98
            let endRadius   = max(outerSize.width, outerSize.height) * 0.50
            
            cg.drawRadialGradient(
                grad,
                startCenter: c, startRadius: startRadius,
                endCenter:   c, endRadius: endRadius,
                options: [.drawsAfterEndLocation]
            )
            
            cg.restoreGState()
        }
        let t = SKTexture(image: img)
        t.filteringMode = .linear
        return t
    }
}

extension SKScene {
    /// True if `p` is within any HillNode's top (inner ellipse).
    func isInsideAnyHill(_ p: CGPoint) -> Bool {
        var inside = false
        enumerateChildNodes(withName: "hill") { node, stop in
            if let hill = node as? HillNode, hill.containsTop(p, in: self) {
                inside = true
                stop.pointee = true
            }
        }
        return inside
    }
}

extension SKPhysicsBody {
    /// Enable/disable collision against Category.wall without touching other bits.
    func enableWallCollision(_ on: Bool) {
        if on {
            collisionBitMask |= Category.wall
        } else {
            collisionBitMask &= ~Category.wall
        }
    }
}
