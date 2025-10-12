//
//  CarNode.swift
//  IonCircuit
//
//  Created by Barak Ben Hur on 12/10/2025.
//

import SpriteKit
import UIKit

final class CarNode: SKNode {
    // ---- Tuning ----
    var acceleration: CGFloat = 540.0      // was 560
    var maxSpeed: CGFloat     = 1520.0     // was 900
    var reverseSpeedFactor: CGFloat = 0.55
    var turnRate: CGFloat     = 4.2
    var traction: CGFloat     = 12.0
    var drag: CGFloat         = 1.0
    var brakeForce: CGFloat   = 1300.0
    var speedCapBonus: CGFloat = 0   // forward-only extra cap, controlled by GameScene
    
    // Controls [-1, 1]
    var throttle: CGFloat = 0
    var steer: CGFloat    = 0
    
    // Visual refs
    private var headL: SKShapeNode!
    private var headR: SKShapeNode!
    private var tailL: SKShapeNode!
    private var tailR: SKShapeNode!
    
    // Exhaust VFX
    private var exhaustL: SKEmitterNode!
    private var exhaustR: SKEmitterNode!
    
    private var exhaustMixLP: CGFloat = 0            // smoothed 0…1 intensity
    private let exhaustFadeTau: CGFloat = 0.35       // fade time constant (s)
    
    // Palette
    private let bodyColor  = UIColor(hue: 0.58, saturation: 0.60, brightness: 0.98, alpha: 1)
    private let bodyEdge   = UIColor(white: 0.08, alpha: 1)
    private let roofColor  = UIColor(white: 0.96, alpha: 1)
    private let glassColor = UIColor(hue: 0.58, saturation: 0.20, brightness: 1.0, alpha: 0.75)
    private let tireColor  = UIColor(white: 0.15, alpha: 1)
    
    // MARK: - Init
    override init() {
        super.init()
        
        // ---- Geometry (face +Y = front) ----
        // Slightly bigger model, same proportions (~+14%)
        let W: CGFloat = 32        // was 28
        let H: CGFloat = 41        // was 36
        let noseY  =  H * 0.50
        let neckY  =  H * 0.18
        let midY   = -H * 0.15
        let tailY  = -H * 0.50
        
        let halfRearW: CGFloat  = W * 0.46
        let halfNeckW: CGFloat  = W * 0.22
        
        // Wedge chassis path (narrow)
        let p = CGMutablePath()
        p.move(to: CGPoint(x: 0, y: noseY))
        p.addLine(to: CGPoint(x:  halfNeckW, y: neckY))
        p.addLine(to: CGPoint(x:  halfRearW, y: midY))
        p.addLine(to: CGPoint(x:  halfRearW, y: tailY))
        p.addLine(to: CGPoint(x: -halfRearW, y: tailY))
        p.addLine(to: CGPoint(x: -halfRearW, y: midY))
        p.addLine(to: CGPoint(x: -halfNeckW, y: neckY))
        p.closeSubpath()
        
        let chassis = SKShapeNode(path: p)
        chassis.fillColor = bodyColor
        chassis.strokeColor = bodyEdge
        chassis.lineWidth = 1.2
        chassis.zPosition = 2
        addChild(chassis)
        
        // Shadow
        let shadow = SKShapeNode(ellipseOf: CGSize(width: W * 0.9, height: H * 0.55))
        shadow.fillColor = .black
        shadow.strokeColor = .clear
        shadow.alpha = 0.20
        shadow.position = CGPoint(x: 0, y: -2)
        shadow.zPosition = 0
        addChild(shadow)
        
        // Wheels (narrower & tucked in)
        func wheel(_ pos: CGPoint, _ rot: CGFloat) -> SKShapeNode {
            let w = SKShapeNode(rectOf: CGSize(width: 6, height: 16), cornerRadius: 2)
            w.fillColor = tireColor
            w.strokeColor = UIColor(white: 0.05, alpha: 1)
            w.lineWidth = 1
            w.position = pos
            w.zRotation = rot
            w.zPosition = 1
            return w
        }
        let wx = halfRearW - 6
        let wy = H * 0.33
        [
            wheel(CGPoint(x: -wx, y:  wy),  .pi/24),
            wheel(CGPoint(x:  wx, y:  wy), -.pi/24),
            wheel(CGPoint(x: -wx, y: -wy), -.pi/24),
            wheel(CGPoint(x:  wx, y: -wy),  .pi/24)
        ].forEach(addChild)
        
        // Roof / cabin
        let roof = SKShapeNode(rectOf: CGSize(width: W * 0.52, height: H * 0.48), cornerRadius: 6)
        roof.fillColor = roofColor
        roof.strokeColor = bodyEdge.withAlphaComponent(0.6)
        roof.lineWidth = 1
        roof.position = CGPoint(x: 0, y: -H * 0.10)
        roof.zPosition = 3
        addChild(roof)
        
        // Windows
        let winFront = SKShapeNode(rectOf: CGSize(width: roof.frame.width * 0.82,
                                                  height: roof.frame.height * 0.34),
                                   cornerRadius: 4)
        winFront.fillColor = glassColor
        winFront.strokeColor = .clear
        winFront.position = CGPoint(x: 0, y: roof.position.y + roof.frame.height * 0.22)
        winFront.zPosition = 3.1
        let winRear = winFront.copy() as! SKShapeNode
        winRear.position = CGPoint(x: 0, y: roof.position.y - roof.frame.height * 0.22)
        addChild(winFront); addChild(winRear)
        
        // Front chevron
        let chev = SKShapeNode()
        let cpath = CGMutablePath()
        cpath.move(to: CGPoint(x: 0, y: H * 0.44))
        cpath.addLine(to: CGPoint(x:  W * 0.18, y: H * 0.28))
        cpath.addLine(to: CGPoint(x: 0, y: H * 0.34))
        cpath.addLine(to: CGPoint(x: -W * 0.18, y: H * 0.28))
        cpath.closeSubpath()
        chev.path = cpath
        chev.fillColor = bodyEdge.withAlphaComponent(0.25)
        chev.strokeColor = .clear
        chev.zPosition = 3.2
        addChild(chev)
        
        // Spoiler
        let spoiler = SKShapeNode(rectOf: CGSize(width: W * 0.68, height: 3), cornerRadius: 1.5)
        spoiler.fillColor = bodyEdge.withAlphaComponent(0.5)
        spoiler.strokeColor = .clear
        spoiler.position = CGPoint(x: 0, y: tailY + 2)
        spoiler.zPosition = 3.2
        addChild(spoiler)
        
        // Lights
        headL = SKShapeNode(circleOfRadius: 2.4)
        headL.fillColor = .yellow; headL.strokeColor = .clear
        headL.position = CGPoint(x: -W * 0.18, y: H * 0.47); headL.zPosition = 4
        headR = (headL.copy() as! SKShapeNode)
        headR.position = CGPoint(x:  W * 0.18, y: H * 0.47)
        
        tailL = SKShapeNode(rectOf: CGSize(width: 3.8, height: 2.0))
        tailL.fillColor = .red; tailL.strokeColor = .clear
        tailL.position = CGPoint(x: -W * 0.20, y: tailY - 0.5); tailL.zPosition = 4
        tailR = (tailL.copy() as! SKShapeNode)
        tailR.position = CGPoint(x:  W * 0.20, y: tailY - 0.5)
        
        [headL, headR, tailL, tailR].forEach(addChild)
        
        // ---- Exhaust emitters (left/right) ----
        let flameTex = Self.makeFlameTextureMedium()          // medium size (a bit smaller than “old big”)
        exhaustL = Self.makeExhaustEmitter(texture: flameTex)
        exhaustR = Self.makeExhaustEmitter(texture: flameTex)
        
        // Place slightly behind the tail, near the corners
        let exX = W * 0.22
        let exY = tailY - 2.0
        exhaustL.position = CGPoint(x: -exX, y: exY)
        exhaustR.position = CGPoint(x:  exX, y: exY)
        addChild(exhaustL)
        addChild(exhaustR)
        
        // Physics — polygon matching wedge outline
        let pb = SKPhysicsBody(polygonFrom: p)
        pb.isDynamic = true
        pb.allowsRotation = false              // heading controlled kinematically
        pb.friction = 0.0
        pb.linearDamping = drag
        pb.angularDamping = 2.0
        pb.affectedByGravity = false
        pb.usesPreciseCollisionDetection = true
        pb.categoryBitMask = Category.car
        pb.collisionBitMask = Category.wall | Category.obstacle
        pb.contactTestBitMask = Category.hole | Category.obstacle | Category.ramp
        self.physicsBody = pb
        
        // Forward points to +Y
        zRotation = 0
    }
    
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    
    // NOTE: requires: var speedCapBonus: CGFloat = 0 on CarNode
    func update(_ dt: CGFloat) {
        guard let pb = physicsBody else { return }
        
        let heading = zRotation + .pi/2
        let fwd     = CGVector(dx: cos(heading),  dy: sin(heading))
        let right   = CGVector(dx: -sin(heading), dy: cos(heading))
        
        // Current velocity decomposition
        var v      = pb.velocity
        let fwdMag = v.dx * fwd.dx + v.dy * fwd.dy
        let latMag = v.dx * right.dx + v.dy * right.dy
        
        // 1) Kill lateral slip deterministically (no forces → no oscillations)
        let latKill = 1 - exp(-dt * traction * 4.0)
        v.dx -= right.dx * latMag * latKill
        v.dy -= right.dy * latMag * latKill
        pb.velocity = v
        
        // 2) Parking brake when no input (no creep)
        if abs(throttle) < 0.001 && abs(steer) < 0.001 {
            let lin = exp(-dt * 14.0)
            var vv = pb.velocity
            vv.dx *= lin; vv.dy *= lin
            if hypot(vv.dx, vv.dy) < 1.0 { vv = .zero }
            pb.velocity = vv
            pb.angularVelocity = 0
            // Exhaust off when not moving
            updateExhaust(speed: 0, fwdMag: 0, dt: dt)
            return
        }
        
        // 3) Power: forward only unless braking
        let input = throttle.clamped(-1, 1)
        let opposes = (input > 0 && fwdMag < 0) || (input < 0 && fwdMag > 0)
        if opposes {
            let sign: CGFloat = fwdMag >= 0 ? 1 : -1
            pb.applyForce(fwd.scaled(-sign * brakeForce))
        } else {
            pb.applyForce(fwd.scaled(input * acceleration))
        }
        
        // 4) Speed cap (forward cap can be temporarily boosted by GameScene)
        let capForward = maxSpeed + max(0, speedCapBonus)     // <-- boost applied here
        let cap = (fwdMag >= 0 ? capForward : maxSpeed * reverseSpeedFactor)
        let speed = hypot(pb.velocity.dx, pb.velocity.dy)
        if speed > cap {
            let s = cap / max(speed, 0.001)
            pb.velocity = CGVector(dx: pb.velocity.dx * s, dy: pb.velocity.dy * s)
        }
        
        // 5) Steering (no reverse flip, yaw-clamped, physics yaw disabled)
        let speedScale = 0.50 + 0.50 * CGFloat.clamp(abs(fwdMag) / 240.0, 0, 1)
        let slowAssist = 1.0 + CGFloat.clamp(80 - abs(fwdMag), 0, 80) / 90.0
        let commandedYaw = steer.clamped(-1, 1) * turnRate * speedScale * slowAssist
        
        // hard clamp max yaw rate to prevent “spin-outs”
        let maxYaw: CGFloat = 4.0 // rad/s
        let yaw = CGFloat.clamp(commandedYaw, -maxYaw, maxYaw)
        
        zRotation += yaw * dt
        pb.angularVelocity = 0
        
        // ---- VFX update (after physics changes) ----
        let newSpeed = hypot(pb.velocity.dx, pb.velocity.dy)
        updateExhaust(speed: newSpeed, fwdMag: fwdMag, dt: dt)
    }

    
    // MARK: - Exhaust helpers
    
    // Medium flame texture (~30px): looks like the previous large size
    // but trimmed a little; device-independent.
    private static func makeFlameTextureMedium() -> SKTexture {
        let px: CGFloat = 30
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
        let tex = SKTexture(image: img)
        tex.filteringMode = .linear
        return tex
    }
    
    private static func makeExhaustEmitter(texture: SKTexture) -> SKEmitterNode {
        let e = SKEmitterNode()
        e.particleTexture = texture
        
        // Start off; we drive birthRate dynamically
        e.particleBirthRate = 0
        e.particleLifetime = 0.20
        e.particleLifetimeRange = 0.05
        
        e.particleSpeed = 140
        e.particleSpeedRange = 50
        
        e.particlePositionRange = CGVector(dx: 2.0, dy: 0)
        e.particleAlpha = 0.85
        e.particleAlphaSpeed = -2.6
        
        // Slightly bigger than the previous “too small”, still smaller than original big
        e.particleScale = 0.18
        e.particleScaleRange = 0.08
        e.particleScaleSpeed = 0.45
        
        e.particleRotation = 0
        e.particleRotationSpeed = 2
        
        let colors: [UIColor] = [
            .white,
            .orange,
            UIColor(red: 1.0, green: 0.35, blue: 0.0, alpha: 1.0),
            UIColor(red: 1.0, green: 0.10, blue: 0.0, alpha: 0.0)
        ]
        let times: [NSNumber] = [0.0, 0.3, 0.7, 1.0]
        e.particleColorSequence = SKKeyframeSequence(keyframeValues: colors, times: times)
        
        e.particleBlendMode = .add
        e.emissionAngle = -CGFloat.pi/2                 // back of car (local -Y)
        e.emissionAngleRange = CGFloat.pi/18
        e.zPosition = 1.5
        return e
    }
    
    private func updateExhaust(speed: CGFloat, fwdMag: CGFloat, dt: CGFloat) {
        // Compute a *target* intensity (0…1) from speed/throttle
        let moving = speed > 2.0 || throttle > 0.02
        let speedNorm = CGFloat.clamp(speed / max(maxSpeed, 1), 0, 1)
        let throttleBoost = max(0, throttle)
        let targetMix: CGFloat = moving ? (0.35 * speedNorm + 0.65 * throttleBoost) : 0.0
        
        // Low-pass filter → gradual fade when targetMix goes to 0
        let a = 1 - exp(-Double(dt / max(exhaustFadeTau, 0.001)))   // 0…1
        exhaustMixLP += (targetMix - exhaustMixLP) * CGFloat(a)
        let mix = CGFloat.clamp(exhaustMixLP, 0, 1)
        
        // Drive emitters from the smoothed mix
        let maxBR: CGFloat = 320                      // 80 + 240 from before
        let br = maxBR * mix
        
        let basePS: CGFloat = 120
        let addPS:  CGFloat = 160
        let ps = basePS + addPS * mix
        
        let scale = 0.16 + 0.22 * mix + 0.10 * (mix * mix)
        
        let baseLT: CGFloat = 0.30
        let addLT:  CGFloat = 0.10
        let lt = baseLT + addLT * (mix * mix)
        let ltRange = lt * 0.15
        
        // Fade a bit slower at higher mix so trails read nicer
        let alphaSpeed = -1.00 + 0.25 * mix          // -1.00 … -0.75
        
        [exhaustL, exhaustR].forEach { e in
            e.particleBirthRate = br
            e.particleSpeed = ps
            e.particleScale = scale
            e.particleAlpha = 0.70 + 0.20 * mix
            e.particleLifetime = lt
            e.particleLifetimeRange = ltRange
            e.particleAlphaSpeed = alphaSpeed
        }
    }
}
