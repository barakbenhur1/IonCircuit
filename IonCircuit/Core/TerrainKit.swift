
//  TerrainKit.swift
//  IonCircuit
//
//  2.5D Hills & Ramps — professional, game-ready visuals with soft shadows, bevels, and sheen.
//  Drop this file into your project. Then replace your `spawnHillsAndRamps(...)` in GameScene.swift
//  with the version at the bottom of this file (copy-paste).
//
//  Notes:
//  - Uses SKShapeNode + procedural textures for gradients (no external assets).
//  - Physics: static bodies sized to visuals. Collide as `.wall` so car rides around/over.
//  - Ramp exposes `heading` to align with your HUD arrow logic.
//  - If you already have HillNode/RampNode types, remove or rename to avoid duplication.

import SpriteKit
import UIKit
import CoreImage

// MARK: - Tunables

let enablePhysicsForHills = false

enum Light {
    static var dir: CGVector = CGVector(dx: -0.6, dy: 1.0).normalized
}

// Procedural gradient textures -------------------------------------------------

func radialGradientTexture(size: CGSize,
                                   inner: UIColor,
                                   outer: UIColor,
                                   falloff: CGFloat = 1.0) -> SKTexture {
    let scale: CGFloat = UIScreen.main.scale
    let w = max(2, Int(size.width * scale))
    let h = max(2, Int(size.height * scale))
    UIGraphicsBeginImageContextWithOptions(CGSize(width: w, height: h), false, 1.0)
    guard let ctx = UIGraphicsGetCurrentContext() else {
        UIGraphicsEndImageContext()
        return SKTexture()
    }
    let colors = [inner.cgColor, outer.cgColor] as CFArray
    let locs: [CGFloat] = [0.0, 1.0]
    let space = CGColorSpaceCreateDeviceRGB()
    let grad = CGGradient(colorsSpace: space, colors: colors, locations: locs)!
    let center = CGPoint(x: CGFloat(w)/2, y: CGFloat(h)/2)
    let r = hypot(center.x, center.y) * falloff
    ctx.drawRadialGradient(grad,
                           startCenter: center, startRadius: 0,
                           endCenter: center, endRadius: r,
                           options: .drawsBeforeStartLocation)
    let img = UIGraphicsGetImageFromCurrentImageContext()!
    UIGraphicsEndImageContext()
    return SKTexture(image: img)
}

func linearGradientTexture(size: CGSize,
                                   from: CGPoint,
                                   to: CGPoint,
                                   colors: [UIColor],
                                   locations: [CGFloat]? = nil) -> SKTexture {
    let scale: CGFloat = UIScreen.main.scale
    let w = max(2, Int(size.width * scale))
    let h = max(2, Int(size.height * scale))
    UIGraphicsBeginImageContextWithOptions(CGSize(width: w, height: h), false, 1.0)
    guard let ctx = UIGraphicsGetCurrentContext() else {
        UIGraphicsEndImageContext()
        return SKTexture()
    }
    let cgColors = colors.map { $0.cgColor } as CFArray
    let locs = locations ?? stride(from: 0.0, through: 1.0, by: 1.0 / Double(colors.count - 1)).map { CGFloat($0) }
    let space = CGColorSpaceCreateDeviceRGB()
    let grad = CGGradient(colorsSpace: space, colors: cgColors, locations: locs)!
    ctx.drawLinearGradient(grad,
                           start: CGPoint(x: from.x * CGFloat(w), y: from.y * CGFloat(h)),
                           end:   CGPoint(x: to.x   * CGFloat(w), y: to.y   * CGFloat(h)),
                           options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    let img = UIGraphicsGetImageFromCurrentImageContext()!
    UIGraphicsEndImageContext()
    return SKTexture(image: img)
}

func addShadow(to shape: SKShapeNode, offset: CGPoint, radius: CGFloat, alpha: CGFloat) -> SKNode {
    let shadow = shape.copy() as! SKShapeNode
    shadow.fillColor = .black
    shadow.strokeColor = .clear
    shadow.alpha = alpha
    shadow.position = CGPoint(x: offset.x, y: offset.y)
    shadow.zPosition = shape.zPosition - 1
    let effect = shadow.wrappedInGlow(blurRadius: 6) // pick your radius
    shape.parent?.addChild(effect)
    return shadow
}
