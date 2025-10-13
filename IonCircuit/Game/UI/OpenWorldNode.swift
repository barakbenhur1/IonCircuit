//
//  OpenWorldNode.swift
//  IonCircuit
//
//  Created by Barak Ben Hur on 12/10/2025.
//

import SpriteKit
import UIKit

final class OpenWorldNode: SKNode {
    struct Config {
        var size: CGSize
        var cornerJitter: CGFloat = 120   // kept for compatibility, not used now
        var holeCount: Int = 8
        var holeRadius: ClosedRange<CGFloat> = 40...80
        var holeMinSpacing: CGFloat = 160
    }
    
    private let cfg: Config
    private var holeNodes: [SKShapeNode] = []
    
    init(config: Config) {
        self.cfg = config
        super.init()
        buildGroundAndEdges()
    }
    required init?(coder: NSCoder) { fatalError() }
    
    /// Ground + physics edges exactly at the map bounds, rounded like the visuals, no gray border.
    private func buildGroundAndEdges() {
        let W = cfg.size.width, H = cfg.size.height
        let bounds = CGRect(x: -W/2, y: -H/2, width: W, height: H)
        
        // Ground base (no stroke)
        let ground = SKShapeNode(rectOf: cfg.size, cornerRadius: 40)
        ground.fillColor = .init(white: 0.12, alpha: 1)
        ground.strokeColor = .clear
        addChild(ground)
        
        // ---- Floor texture (tiled neon circuit) ----
        let cell: CGFloat = 80
        let line: CGFloat = 2
        let tileGroup = makeCircuitTileGroup(cell: cell, line: line)
        let tileSet = SKTileSet(tileGroups: [tileGroup], tileSetType: .grid)
        
        let cols = Int(ceil(W / cell))
        let rows = Int(ceil(H / cell))
        let map = SKTileMapNode(tileSet: tileSet,
                                columns: cols,
                                rows: rows,
                                tileSize: CGSize(width: cell, height: cell))
        for c in 0..<cols { for r in 0..<rows { map.setTileGroup(tileGroup, forColumn: c, row: r) } }
        map.zPosition = 0.5
        map.alpha = 0.30
        addChild(map)
        
        // Optional soft “hills” for depth
        for _ in 0..<14 {
            let r = CGFloat.random(in: 120...320)
            let blob = SKShapeNode(circleOfRadius: r)
            blob.fillColor = .init(white: 0.18, alpha: 1)
            blob.strokeColor = .clear
            blob.alpha = 0.20
            blob.position = CGPoint(x: CGFloat.random(in: bounds.minX...bounds.maxX),
                                    y: CGFloat.random(in: bounds.minY...bounds.maxY))
            blob.zPosition = 0.25
            addChild(blob)
        }
        
        // Physics boundary: rounded to match visuals
        let rounded = CGPath(roundedRect: bounds, cornerWidth: 40, cornerHeight: 40, transform: nil)
        let edge = SKPhysicsBody(edgeLoopFrom: rounded)
        edge.categoryBitMask = Category.wall
        edge.collisionBitMask = UInt32.max
        edge.friction = 0
        edge.restitution = 0
        physicsBody = edge
    }
    
    // MARK: - New floor: neon circuit tile (seamless)
    private func makeCircuitTileGroup(cell: CGFloat, line: CGFloat) -> SKTileGroup {
        let size = CGSize(width: cell, height: cell)
        let img = UIGraphicsImageRenderer(size: size).image { ctx in
            // Transparent tile; blends over the dark ground
            UIColor.clear.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
            
            // Palette
            let base = UIColor(hue: 0.55, saturation: 0.65, brightness: 0.75, alpha: 1) // cyan-ish
            let glow = base.withAlphaComponent(0.22)
            let stroke = base.withAlphaComponent(0.85)
            let seam  = UIColor(white: 1, alpha: 0.06)
            
            // --- Glow pads (two fixed positions so tiling stays consistent) ---
            func drawPad(center: CGPoint, radius r: CGFloat) {
                // soft radial "glow" behind a crisp ring
                let colors = [glow.cgColor, UIColor.clear.cgColor] as CFArray
                let locs: [CGFloat] = [0, 1]
                let space = CGColorSpaceCreateDeviceRGB()
                if let grad = CGGradient(colorsSpace: space, colors: colors, locations: locs) {
                    ctx.cgContext.drawRadialGradient(
                        grad,
                        startCenter: center, startRadius: 0,
                        endCenter: center, endRadius: r * 1.6,
                        options: [.drawsAfterEndLocation]
                    )
                }
                let ring = UIBezierPath(ovalIn: CGRect(x: center.x - r, y: center.y - r, width: r*2, height: r*2))
                stroke.setStroke()
                ring.lineWidth = 1.2
                ring.stroke()
            }
            drawPad(center: CGPoint(x: size.width * 0.70, y: size.height * 0.72), radius: cell * 0.12)
            drawPad(center: CGPoint(x: size.width * 0.28, y: size.height * 0.34), radius: cell * 0.09)
            
            // --- Traces (glow pass + crisp pass) ---
            let y = size.height * 0.30
            let x = size.width  * 0.38
            
            // glow pass
            ctx.cgContext.setLineCap(.round)
            ctx.cgContext.setStrokeColor(glow.cgColor)
            ctx.cgContext.setLineWidth(line * 2.0)
            // horizontal
            ctx.cgContext.move(to: CGPoint(x: 0, y: y))
            ctx.cgContext.addLine(to: CGPoint(x: size.width, y: y))
            // vertical branch
            ctx.cgContext.move(to: CGPoint(x: x, y: y))
            ctx.cgContext.addLine(to: CGPoint(x: x, y: size.height))
            ctx.cgContext.strokePath()
            
            // crisp pass
            ctx.cgContext.setStrokeColor(stroke.cgColor)
            ctx.cgContext.setLineWidth(1.4)
            // horizontal
            ctx.cgContext.move(to: CGPoint(x: 0, y: y))
            ctx.cgContext.addLine(to: CGPoint(x: size.width, y: y))
            // vertical
            ctx.cgContext.move(to: CGPoint(x: x, y: y))
            ctx.cgContext.addLine(to: CGPoint(x: x, y: size.height))
            ctx.cgContext.strokePath()
            
            // vias (small dots) along the line
            func via(_ p: CGPoint, r: CGFloat = 1.6) {
                let rect = CGRect(x: p.x - r, y: p.y - r, width: r*2, height: r*2)
                ctx.cgContext.setFillColor(stroke.withAlphaComponent(0.9).cgColor)
                ctx.cgContext.fillEllipse(in: rect)
            }
            via(CGPoint(x: size.width * 0.15, y: y))
            via(CGPoint(x: size.width * 0.52, y: y))
            via(CGPoint(x: x, y: size.height * 0.58))
            
            // --- Tile seams (left & bottom) to guarantee seamless tiling ---
            ctx.cgContext.setStrokeColor(seam.cgColor)
            ctx.cgContext.setLineWidth(1)
            // left seam
            ctx.cgContext.move(to: CGPoint(x: 0, y: 0))
            ctx.cgContext.addLine(to: CGPoint(x: 0, y: size.height))
            // bottom seam
            ctx.cgContext.move(to: CGPoint(x: 0, y: 0))
            ctx.cgContext.addLine(to: CGPoint(x: size.width, y: 0))
            ctx.cgContext.strokePath()
        }
        
        let tex = SKTexture(image: img)
        tex.filteringMode = .nearest
        let def = SKTileDefinition(texture: tex, size: size)
        return SKTileGroup(tileDefinition: def)
    }
    
    // Remove any existing holes
    func clearHoles() {
        holeNodes.forEach { $0.removeFromParent() }
        holeNodes.removeAll()
    }
    
    /// Place spaced holes avoiding the car.
    func populateHoles(keepOutCenter: CGPoint,
                       keepOutRadius: CGFloat,
                       count: Int? = nil,
                       minSpacing: CGFloat? = nil) {
        clearHoles()
        
        let count = count ?? cfg.holeCount
        let spacing = minSpacing ?? cfg.holeMinSpacing
        let W = cfg.size.width, H = cfg.size.height
        let rect = CGRect(x: -W/2, y: -H/2, width: W, height: H)
        
        var placed: [(CGPoint, CGFloat)] = []
        let maxAttempts = count * 80
        
        for _ in 0..<maxAttempts {
            if placed.count >= count { break }
            let r = CGFloat.random(in: cfg.holeRadius)
            let inner = rect.insetBy(dx: r + 16, dy: r + 16)
            let p = CGPoint(x: .random(in: inner.minX...inner.maxX),
                            y: .random(in: inner.minY...inner.maxY))
            
            // Keep-out around car
            if p.distance(to: keepOutCenter) < keepOutRadius + r { continue }
            
            // Poisson-like spacing
            var ok = true
            for (q, rq) in placed {
                if p.distance(to: q) < (rq + r + spacing) { ok = false; break }
            }
            if !ok { continue }
            
            placed.append((p, r))
            
            let hole = SKShapeNode(circleOfRadius: r)
            hole.fillColor = .black
            hole.strokeColor = .clear
            hole.position = p
            
            let pb = SKPhysicsBody(circleOfRadius: r)
            pb.isDynamic = false
            pb.categoryBitMask = Category.hole
            pb.collisionBitMask = 0
            pb.contactTestBitMask = Category.car
            hole.physicsBody = pb
            
            addChild(hole)
            holeNodes.append(hole)
        }
    }
}
