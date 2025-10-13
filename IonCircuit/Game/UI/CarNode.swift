//
//  CarNode.swift
//  IonCircuit
//
//  Created by Barak Ben Hur on 12/10/2025.
//

import SpriteKit
import UIKit
import ObjectiveC

// Delegates back to the scene for FX & spawn logic.
protocol CarNodeDelegate: AnyObject {
    func carNodeDidExplode(_ car: CarNode, at position: CGPoint)
    func carNodeRequestRespawnPoint(_ car: CarNode) -> CGPoint
}

final class CarNode: SKNode {
    private enum Assoc {
        static var g: UInt8 = 0
        static var z: UInt8 = 0
        static var v: UInt8 = 0
        static var a: UInt8 = 0
        static var m: UInt8 = 0
        static var s: UInt8 = 0
        static var combat = 0
        static var delegate = 0
    }
    
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
    
    // MARK: Air / launch tuning
    private let airDragCoef: CGFloat = 1.8     // per-second horizontal drag while airborne
    private let launchLossMax: CGFloat = 0.60  // cap the immediate speed loss on takeoff
    
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
        pb.restitution = 0
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
    
    // NOTE: requires on CarNode:
    // var speedCapBonus: CGFloat = 0     // scene can raise the forward cap temporarily
    // var isAirborne: Bool               // you already have this with your vertical model
    
    func update(_ dt: CGFloat) {
        guard let pb = physicsBody else { return }
        
        let heading = zRotation + .pi/2
        let fwd     = CGVector(dx: cos(heading),  dy: sin(heading))
        let right   = CGVector(dx: -sin(heading), dy: cos(heading))
        
        // ───────────────────────────
        // AIRBORNE
        // ───────────────────────────
        if isAirborne {
            let retain = exp(-dt * 2.3)
            var vv = pb.velocity
            vv.dx *= retain
            vv.dy *= retain
            
            let airCap = (maxSpeed + max(0, speedCapBonus)) * 0.78
            let sp = hypot(vv.dx, vv.dy)
            if sp > airCap {
                let k = airCap / max(sp, 0.001)
                vv.dx *= k; vv.dy *= k
            }
            pb.velocity = vv
            
            let yaw = steer.clamped(-1, 1) * (turnRate * 0.35)
            zRotation += yaw * dt
            pb.angularVelocity = 0
            
            let fwdMag  = vv.dx * fwd.dx + vv.dy * fwd.dy
            updateExhaust(speed: sp, fwdMag: fwdMag, dt: dt)
            return
        }
        
        // ───────────────────────────
        // GROUND
        // ───────────────────────────
        var v      = pb.velocity
        let fwdMag = v.dx * fwd.dx + v.dy * fwd.dy
        let latMag = v.dx * right.dx + v.dy * right.dy
        
        // Kill lateral slip
        let latKill = 1 - exp(-dt * traction * 4.0)
        v.dx -= right.dx * latMag * latKill
        v.dy -= right.dy * latMag * latKill
        pb.velocity = v
        
        // Extra hill drag (rolling resistance on hills)
        if hillDragK > 0 {
            let keep = exp(-dt * hillDragK)
            var vv = pb.velocity
            vv.dx *= keep
            vv.dy *= keep
            pb.velocity = vv
        }
        
        // Parking brake when no input
        if abs(throttle) < 0.001 && abs(steer) < 0.001 {
            let lin = exp(-dt * 14.0)
            var vv = pb.velocity
            vv.dx *= lin; vv.dy *= lin
            if hypot(vv.dx, vv.dy) < 1.0 { vv = .zero }
            pb.velocity = vv
            pb.angularVelocity = 0
            updateExhaust(speed: 0, fwdMag: 0, dt: dt)
            return
        }
        
        // Power
        let input = throttle.clamped(-1, 1)
        let opposes = (input > 0 && fwdMag < 0) || (input < 0 && fwdMag > 0)
        if opposes {
            let sign: CGFloat = fwdMag >= 0 ? 1 : -1
            pb.applyForce(fwd.scaled(-sign * brakeForce))
        } else {
            pb.applyForce(fwd.scaled(input * acceleration * max(0, hillAccelMul)))
        }
        
        // Speed cap (with hill multiplier)
        let capForwardBase = maxSpeed + max(0, speedCapBonus)
        let capForward     = capForwardBase * max(0.1, hillSpeedMul)
        let cap = (fwdMag >= 0 ? capForward : maxSpeed * reverseSpeedFactor)
        let speed = hypot(pb.velocity.dx, pb.velocity.dy)
        if speed > cap {
            let s = cap / max(speed, 0.001)
            pb.velocity = CGVector(dx: pb.velocity.dx * s, dy: pb.velocity.dy * s)
        }
        
        // Steering
        let speedScale = 0.50 + 0.50 * CGFloat.clamp(abs(fwdMag) / 240.0, 0, 1)
        let slowAssist = 1.0 + CGFloat.clamp(80 - abs(fwdMag), 0, 80) / 90.0
        let commandedYaw = steer.clamped(-1, 1) * turnRate * speedScale * slowAssist
        let maxYaw: CGFloat = 4.0
        let yaw = CGFloat.clamp(commandedYaw, -maxYaw, maxYaw)
        
        zRotation += yaw * dt
        pb.angularVelocity = 0
        
        updateExhaust(speed: hypot(pb.velocity.dx, pb.velocity.dy),
                      fwdMag: fwdMag, dt: dt)
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

// MARK: - Air / Verticality for CarNode
extension CarNode {
    private struct LandAssoc { static var t = 0 }
    private var _lastLandingT: TimeInterval {
        get { (objc_getAssociatedObject(self, &LandAssoc.t) as? TimeInterval) ?? 0 }
        set { objc_setAssociatedObject(self, &LandAssoc.t, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC) }
    }
    
    private struct GhostAssoc { static var g = 0 }
    private var _airGhosting: Bool {
        get { (objc_getAssociatedObject(self, &GhostAssoc.g) as? Bool) ?? false }
        set { objc_setAssociatedObject(self, &GhostAssoc.g, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC) }
    }
    // Public-ish tuning
    var gravity: CGFloat { get { objc_getAssociatedObject(self, &Assoc.g) as? CGFloat ?? -1800 }
        set { objc_setAssociatedObject(self, &Assoc.g, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC) } }
    var zLift: CGFloat { get { objc_getAssociatedObject(self, &Assoc.z) as? CGFloat ?? 0 }
        set { objc_setAssociatedObject(self, &Assoc.z, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC) } }
    var vz: CGFloat { get { objc_getAssociatedObject(self, &Assoc.v) as? CGFloat ?? 0 }
        set { objc_setAssociatedObject(self, &Assoc.v, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC) } }
    var isAirborne: Bool { get { objc_getAssociatedObject(self, &Assoc.a) as? Bool ?? false }
        set { objc_setAssociatedObject(self, &Assoc.a, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC) } }
    
    private var _groundMask: UInt32 {
        get { objc_getAssociatedObject(self, &Assoc.m) as? UInt32 ?? (physicsBody?.collisionBitMask ?? 0) }
        set { objc_setAssociatedObject(self, &Assoc.m, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC) }
    }
    private var shadowNode: SKShapeNode? {
        get { objc_getAssociatedObject(self, &Assoc.s) as? SKShapeNode }
        set { objc_setAssociatedObject(self, &Assoc.s, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC) }
    }
    
    /// Call once after the car is created (e.g. in GameScene.didMove)
    func enableAirPhysics() {
        _groundMask = physicsBody?.collisionBitMask ?? 0
        
        // soft oval shadow
        let sh = SKShapeNode(ellipseOf: CGSize(width: 44, height: 18))
        sh.fillColor = .black
        sh.strokeColor = .clear
        sh.alpha = 0.35
        sh.zPosition = -1
        addChild(sh)
        shadowNode = sh
    }
    
    func stepVertical(dt: CGFloat, groundHeight: CGFloat) {
        let wasAir = isAirborne
        
        // Integrate vertical
        vz += gravity * dt
        zLift += vz * dt
        
        var vzAtLanding: CGFloat = 0
        if zLift <= groundHeight {
            vzAtLanding = vz
            zLift = groundHeight
            if vz < 0 { vz = 0 }
            isAirborne = false
        } else {
            isAirborne = true
        }
        
        // ── Altitude ghosting with hysteresis (unchanged behavior) ───────────────
        let clearance = zLift - groundHeight
        let ghostOn:  CGFloat = 14
        let ghostOff: CGFloat = 8
        if isAirborne {
            if !_airGhosting, clearance > ghostOn { _airGhosting = true }
            if  _airGhosting, clearance < ghostOff { _airGhosting = false }
        } else {
            _airGhosting = false
        }
        if let pb = physicsBody { pb.collisionBitMask = _airGhosting ? 0 : _groundMask }
        
        // ── Landing energy handling (soft at hill base / downhill) ───────────────
        if wasAir && !isAirborne, let pb = physicsBody {
            // Tiny residual height near the base? Don’t nuke speed there.
            if groundHeight < 16 {
                // Very gentle settle only
                let keep = exp(-dt * 2.0)
                var v = pb.velocity
                v.dx *= keep; v.dy *= keep
                pb.velocity = v
            } else {
                // Scale retention by impact AND by downhill alignment
                let heading = zRotation + .pi/2
                let f = CGVector(dx: cos(heading),  dy: sin(heading))
                let s = CGVector(dx: -f.dy,         dy: f.dx)
                let v  = pb.velocity
                let vf = v.dx * f.dx + v.dy * f.dy
                let vs = v.dx * s.dx + v.dy * s.dy
                
                let impact = min(1, abs(vzAtLanding) / 1100)   // 0…1
                
                var alignDown: CGFloat = 0
                if let scn = scene as? GameScene {
                    let g = scn.groundGradient(at: position)   // uphill
                    var down = CGVector(dx: -g.dx, dy: -g.dy)
                    let len = max(1e-6, hypot(down.dx, down.dy))
                    down.dx /= len; down.dy /= len
                    alignDown = max(0, f.dx * down.dx + f.dy * down.dy) // 0…1 if pointing downhill
                }
                
                // More retention when pointing downhill, less when uphill, never clamp to zero
                let baseKeepF: CGFloat = 0.65 - 0.35 * impact       // 0.30…0.65
                let boostF:    CGFloat = 0.35 * alignDown           // up to +0.35 when aligned downhill
                let keepFwd = CGFloat.clamp(baseKeepF + boostF, 0.25, 0.95)
                
                let keepSide = max(0.28, 0.50 - 0.30 * impact)      // keep some lateral too
                
                let newV = CGVector(
                    dx: f.dx * (vf * keepFwd) + s.dx * (vs * keepSide),
                    dy: f.dy * (vf * keepFwd) + s.dy * (vs * keepSide)
                )
                pb.velocity = newV
            }
            
            // Debounce repeated “mini-landings” on the base
            let now = CACurrentMediaTime()
            if now - _lastLandingT > 0.08 {
                removeAction(forKey: "landPop")
                run(.sequence([.scale(to: 1.03, duration: 0.05),
                               .scale(to: 1.00, duration: 0.08)]), withKey: "landPop")
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                _lastLandingT = now
            }
        }
    }
    
    /// `heading` is the ramp forward direction (same convention you already use).
    func applyRampImpulse(vzAdd: CGFloat, forwardBoost: CGFloat, heading: CGFloat) {
        guard let pb = physicsBody else { return }
        isAirborne = true
        vz += vzAdd
        _airGhosting = true            // ← NEW: start ghosted; hysteresis will turn it off when low
        pb.collisionBitMask = 0
        speedCapBonus = 0
        
        // Decompose current velocity into ramp axes
        let f = CGVector(dx: cos(heading), dy: sin(heading))      // ramp forward
        let s = CGVector(dx: -f.dy,          dy: f.dx)            // right
        let v = pb.velocity
        let vf = v.dx * f.dx + v.dy * f.dy
        let vs = v.dx * s.dx + v.dy * s.dy
        
        // Immediate loss: keep some momentum but never a full carry-over.
        let steep = min(1.0, max(0.0, vzAdd / 1100.0))
        let loss  = min(launchLossMax, 0.12 + 0.32 * steep)   // softer than before
        let newVf = max(0, vf * (1 - loss)) + forwardBoost
        let newVs = vs * (1 - loss * 0.25)
        
        pb.velocity = CGVector(dx: f.dx * newVf + s.dx * newVs,
                               dy: f.dy * newVf + s.dy * newVs)
    }
}

// MARK: - Shooting (owned by CarNode)
extension CarNode {
    // Tuning
    private var bulletSpeed: CGFloat { 2200 }
    private var bulletLife:  CGFloat { 1.0 }
    
    private var singleTapCooldown: TimeInterval { 0.22 }
    private var autoFireInterval:  TimeInterval { 0.24 }
    private var autoFireArmDelay:  TimeInterval { 0.18 }
    private var muzzleOffset: CGFloat { 26 }
    
    // Keys & state
    private var fireArmKey:  String { "car.fire.arm" }
    private var fireLoopKey: String { "car.fire.loop" }
    private struct FireAssoc { static var last: UInt8 = 0 }
    private var _lastShot: TimeInterval {
        get { (objc_getAssociatedObject(self, &FireAssoc.last) as? TimeInterval) ?? 0 }
        set { objc_setAssociatedObject(self, &FireAssoc.last, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC) }
    }
    
    /// One bullet, respects a small cooldown.
    func fireOnce(on scene: SKScene) {
        let now = CACurrentMediaTime()
        if now - _lastShot < singleTapCooldown { return }
        _lastShot = now
        
        guard let pb = physicsBody else { return }
        let heading = zRotation + .pi/2
        let fwd = CGVector(dx: cos(heading), dy: sin(heading))
        let origin = CGPoint(x: position.x + fwd.dx * muzzleOffset,
                             y: position.y + fwd.dy * muzzleOffset)
        let vel = CGVector(dx: pb.velocity.dx + fwd.dx * bulletSpeed,
                           dy: pb.velocity.dy + fwd.dy * bulletSpeed)
        
        let bullet = BulletNode(velocity: vel, life: CGFloat(bulletLife))
        bullet.name = "bullet" // keep existing culling compatible
        bullet.position = origin
        bullet.zPosition = 900    // above world + car
        scene.addChild(bullet)
        bullet.attach(to: scene)
        muzzleFlash()
    }
    
    /// Hold-to-fire loop. Starts with an immediate shot, then repeats.
    func startAutoFire(on scene: SKScene) {
        // already armed/looping?
        if action(forKey: fireArmKey) != nil || action(forKey: fireLoopKey) != nil { return }
        fireOnce(on: scene)
        
        let arm = SKAction.sequence([
            .wait(forDuration: autoFireArmDelay),
            .run { [weak self, weak scene] in
                guard let self, let scene else { return }
                let loop = SKAction.sequence([
                    .wait(forDuration: self.autoFireInterval),
                    .run { [weak self, weak scene] in
                        guard let self, let scene else { return }
                        self.fireOnce(on: scene)
                    }
                ])
                self.run(.repeatForever(loop), withKey: self.fireLoopKey)
            }
        ])
        run(arm, withKey: fireArmKey)
    }
    
    func stopAutoFire() {
        removeAction(forKey: fireArmKey)
        removeAction(forKey: fireLoopKey)
    }
    
    // Small visual at the nose.
    private func muzzleFlash() {
        let d: CGFloat = 8
        let flash = SKShapeNode(circleOfRadius: d/2)
        flash.fillColor = .white
        flash.strokeColor = UIColor.white.withAlphaComponent(0.25)
        flash.lineWidth = 1
        flash.zPosition = 10  // above car parts
        
        // IMPORTANT: local space (front of car is +Y)
        flash.position = CGPoint(x: 0, y: muzzleOffset)
        
        addChild(flash)
        flash.run(.sequence([
            .group([.scale(to: 1.6, duration: 0.06),
                    .fadeOut(withDuration: 0.06)]),
            .removeFromParent()
        ]))
    }
}

// MARK: - Delegate storage
extension CarNode {
    weak var delegate: CarNodeDelegate? {
        get { objc_getAssociatedObject(self, &Assoc.delegate) as? CarNodeDelegate }
        set { objc_setAssociatedObject(self, &Assoc.delegate, newValue, .OBJC_ASSOCIATION_ASSIGN) }
    }
}

// MARK: - Health (unified: drives HUD + death/respawn)
extension CarNode {
    var maxHP: Int {
        get { _maxHP }
        set { _maxHP = max(1, newValue); hp = min(hp, _maxHP); onHPChanged?(hp, _maxHP) }
    }
    private struct Holder {
        static var hpKey = 0, maxHPKey = 0, lastHitKey = 0, isDeadKey = 0
        static var cbKey = 0
    }
    
    private var _maxHP: Int {
        get { (objc_getAssociatedObject(self, &Holder.maxHPKey) as? Int) ?? 100 }
        set { objc_setAssociatedObject(self, &Holder.maxHPKey, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC) }
    }
    private(set) var hp: Int {
        get { (objc_getAssociatedObject(self, &Holder.hpKey) as? Int) ?? 100 }
        set { objc_setAssociatedObject(self, &Holder.hpKey, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC) }
    }
    private var lastHitTime: TimeInterval {
        get { (objc_getAssociatedObject(self, &Holder.lastHitKey) as? TimeInterval) ?? 0 }
        set { objc_setAssociatedObject(self, &Holder.lastHitKey, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC) }
    }
    
    var isDead: Bool {
        get { (objc_getAssociatedObject(self, &Holder.isDeadKey) as? Bool) ?? false }
        set { objc_setAssociatedObject(self, &Holder.isDeadKey, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC) }
    }
    
    /// Called whenever HP changes: (hp, maxHP)
    var onHPChanged: ((Int, Int) -> Void)? {
        get { objc_getAssociatedObject(self, &Holder.cbKey) as? (Int, Int) -> Void }
        set { objc_setAssociatedObject(self, &Holder.cbKey, newValue, .OBJC_ASSOCIATION_COPY_NONATOMIC) }
    }
    
    func resetHP() {
        hp = maxHP
        isDead = false
        onHPChanged?(hp, maxHP)
    }
    
    /// Ensure we actually receive crash contacts.
    func enableCrashContacts() {
        guard let pb = physicsBody else { return }
        pb.contactTestBitMask |= (Category.obstacle | Category.wall)
    }
    
    // MARK: - Damage pipeline
    // CarNode.swift — handleCrash(contact:other:)
    func handleCrash(contact: SKPhysicsContact, other: SKPhysicsBody) {
        // Never take damage from ramps or hills
        if (other.categoryBitMask & Category.ramp) != 0 { return }
        if other.node is HillNode { return }
        
        if isDead { return }
        let now = CACurrentMediaTime()
        let iFrame: TimeInterval = 0.12
        if now - lastHitTime < iFrame { return }
        lastHitTime = now
        
        // Compute impact point (scene space) for FX
        let hitPoint = contact.contactPoint
        applyDamage(10, at: hitPoint)
    }
    
    /// Single, unified damage entry. Triggers HUD via onHPChanged.
    func applyDamage(_ amount: Int, at worldPoint: CGPoint) {
        if isDead { return }
        hp = max(0, hp - max(1, amount))
        onHPChanged?(hp, maxHP)
        playHitFX(at: worldPoint)
        
        if hp == 0 {
            explode(at: worldPoint)
        }
    }
    
    // MARK: - FX
    private func playHitFX(at worldPoint: CGPoint?) {
        // quick bump + flash
        removeAction(forKey: "hitFX")
        let bumpUp = SKAction.scale(to: 1.08, duration: 0.08); bumpUp.timingMode = .easeOut
        let bumpDn = SKAction.scale(to: 1.0,  duration: 0.12); bumpDn.timingMode = .easeIn
        let flashOut = SKAction.fadeAlpha(to: 0.65, duration: 0.04)
        let flashIn  = SKAction.fadeAlpha(to: 1.00, duration: 0.12)
        run(.sequence([.group([bumpUp, flashOut]), bumpDn, flashIn]), withKey: "hitFX")
        
        // little ring at contact
        if let scene = scene, let p = worldPoint {
            let ring = SKShapeNode(circleOfRadius: 8)
            ring.position = p
            ring.strokeColor = UIColor.white.withAlphaComponent(0.85)
            ring.lineWidth = 3
            ring.fillColor = .clear
            ring.zPosition = zPosition + 100
            scene.addChild(ring)
            ring.run(.sequence([
                .group([.scale(to: 5.5, duration: 0.28), .fadeOut(withDuration: 0.28)]),
                .removeFromParent()
            ]))
        }
        (scene as? GameScene)?.shakeCamera(intensity: 5, duration: 0.12)
    }
    
    private func explode(at worldPoint: CGPoint) {
        guard !isDead else { return }
        isDead = true
        
        // stop motion & gate collisions while "dead"
        if let pb = physicsBody {
            pb.velocity = .zero
            pb.angularVelocity = 0
            pb.categoryBitMask = 0
            pb.collisionBitMask = 0
            pb.contactTestBitMask = 0
        }
        
        // Inform scene (does camera freeze + world pause + FX)
        delegate?.carNodeDidExplode(self, at: worldPoint)
        
        // Hide briefly, then respawn (keep node; don't remove permanently)
        isHidden = true
        run(.sequence([
            .wait(forDuration: 1.0),
            .run { [weak self] in
                guard let self else { return }
                let spawn = self.delegate?.carNodeRequestRespawnPoint(self) ?? .zero
                self.position = spawn
                self.zRotation = 0
                self.physicsBody?.velocity = .zero
                
                // restore physics masks
                if let pb = self.physicsBody {
                    pb.categoryBitMask = Category.car
                    pb.collisionBitMask = Category.wall | Category.obstacle
                    pb.contactTestBitMask = Category.hole | Category.obstacle | Category.ramp
                    self.enableCrashContacts()
                }
                
                self.resetHP()              // <- HUD updates here
                self.isHidden = false
                self.isDead = false
            }
        ]))
    }
}

extension CarNode {
    private struct HillAssoc {
        static var spd = 0, acc = 0, drg = 0
    }
    /// Multiply forward/reverse speed cap while on hills (0…1, default 1).
    var hillSpeedMul: CGFloat {
        get { objc_getAssociatedObject(self, &HillAssoc.spd) as? CGFloat ?? 1 }
        set { objc_setAssociatedObject(self, &HillAssoc.spd, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC) }
    }
    /// Multiply acceleration while on hills (0…1, default 1).
    var hillAccelMul: CGFloat {
        get { objc_getAssociatedObject(self, &HillAssoc.acc) as? CGFloat ?? 1 }
        set { objc_setAssociatedObject(self, &HillAssoc.acc, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC) }
    }
    /// Extra per-second horizontal drag applied on hills (0 = none).
    var hillDragK: CGFloat {
        get { objc_getAssociatedObject(self, &HillAssoc.drg) as? CGFloat ?? 0 }
        set { objc_setAssociatedObject(self, &HillAssoc.drg, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC) }
    }
}

final class CarHealthHUDNode: SKNode {
    private let card = SKShapeNode()
    private let barBG = SKShapeNode()
    private let barFG = SKShapeNode()
    private let label = SKLabelNode(fontNamed: "Menlo-Bold")
    
    private let cardSize = CGSize(width: 160, height: 40)
    
    override init() {
        super.init()
        zPosition = 500
        
        let rect = CGRect(x: -cardSize.width/2, y: -cardSize.height/2, width: cardSize.width, height: cardSize.height)
        card.path = CGPath(roundedRect: rect, cornerWidth: 12, cornerHeight: 12, transform: nil)
        card.fillColor = UIColor(white: 0, alpha: 0.28)
        card.strokeColor = UIColor(white: 1, alpha: 0.10)
        card.lineWidth = 1.0
        addChild(card)
        
        let bgRect = CGRect(x: rect.minX + 10, y: rect.midY - 5, width: rect.width - 20, height: 10)
        barBG.path = CGPath(roundedRect: bgRect, cornerWidth: 5, cornerHeight: 5, transform: nil)
        barBG.fillColor = UIColor.white.withAlphaComponent(0.12)
        barBG.strokeColor = .clear
        addChild(barBG)
        
        barFG.fillColor = UIColor.systemGreen.withAlphaComponent(0.9)
        barFG.strokeColor = .clear
        addChild(barFG)
        
        label.fontSize = 14
        label.verticalAlignmentMode = .center
        label.horizontalAlignmentMode = .center
        label.fontColor = UIColor.white.withAlphaComponent(0.95)
        label.position = CGPoint(x: 0, y: rect.midY - 16)
        addChild(label)
        
        set(hp: 100, maxHP: 100)
    }
    
    required init?(coder: NSCoder) { fatalError() }
    
    func set(hp: Int, maxHP: Int) {
        let rect = card.frame
        let bgRect = CGRect(x: rect.minX + 10, y: rect.midY - 5, width: rect.width - 20, height: 10)
        let frac = max(0, min(1, CGFloat(hp) / CGFloat(max(1, maxHP))))
        let w = max(1, bgRect.width * frac)
        let fgRect = CGRect(x: bgRect.minX, y: bgRect.minY, width: w, height: bgRect.height)
        barFG.path = CGPath(roundedRect: fgRect, cornerWidth: 5, cornerHeight: 5, transform: nil)
        
        // color shift (green→yellow→red)
        let c: UIColor
        if frac > 0.66 { c = .systemGreen }
        else if frac > 0.33 { c = .systemYellow }
        else { c = .systemRed }
        barFG.fillColor = c.withAlphaComponent(0.9)
        
        label.text = "HP \(hp)/\(maxHP)"
    }
}
