//
//  CarNode.swift
//  IonCircuit
//
//  Created by Barak Ben Hur on 12/10/2025.
//

import SpriteKit
import UIKit
import ObjectiveC

// MARK: - Scene callbacks
protocol CarNodeDelegate: AnyObject {
    func carNodeDidExplode(_ car: CarNode, at position: CGPoint)
    func carNodeRequestRespawnPoint(_ car: CarNode) -> CGPoint
    // NEW: called when the car has no lives left
    func carNodeDidRunOutOfLives(_ car: CarNode)
}

// Optional HUD hooks; the scene may implement these.
@objc protocol CarShieldReporting { @objc optional func onShieldChanged(_ value: Int) }
@objc protocol CarWeaponReporting { @objc optional func onWeaponChanged(_ name: String) }
@objc protocol CarStatusReporting {
    @objc optional func onControlBoostChanged(_ active: Bool)
    @objc optional func onMiniModeChanged(_ active: Bool)
}

// GameScene calls this on death to clear everything.
@objc protocol CarEnhancementResetting { func resetEnhancements() }

private struct LivesCB { static var cb = 0 }

// MARK: - CarNode
final class CarNode: SKNode {
    
    private enum Assoc {
        static var g: UInt8 = 0, z: UInt8 = 0, v: UInt8 = 0, a: UInt8 = 0
        static var m: UInt8 = 0, s: UInt8 = 0
        static var delegate = 0
    }
    
    // ---- Tuning ----
    var acceleration: CGFloat = 540.0
    var maxSpeed: CGFloat     = 1520.0
    var reverseSpeedFactor: CGFloat = 0.55
    var turnRate: CGFloat     = 4.2          // used for control boost
    var traction: CGFloat     = 12.0         // used for control boost
    var drag: CGFloat         = 1.0
    var brakeForce: CGFloat   = 1300.0
    var speedCapBonus: CGFloat = 0
    
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
    
    private var exhaustMixLP: CGFloat = 0
    private let exhaustFadeTau: CGFloat = 0.35
    
    // Palette
    private let bodyColor  = UIColor(hue: 0.58, saturation: 0.60, brightness: 0.98, alpha: 1)
    private let bodyEdge   = UIColor(white: 0.08, alpha: 1)
    private let roofColor  = UIColor(white: 0.96, alpha: 1)
    private let glassColor = UIColor(hue: 0.58, saturation: 0.20, brightness: 1.0, alpha: 0.75)
    private let tireColor  = UIColor(white: 0.15, alpha: 1)
    
    // MARK: Air / launch tuning
    private let airDragCoef: CGFloat = 1.8
    private let launchLossMax: CGFloat = 0.60
    
    var onLivesChanged: ((Int, Int) -> Void)? {
        get { objc_getAssociatedObject(self, &LivesCB.cb) as? (Int, Int) -> Void }
        set { objc_setAssociatedObject(self, &LivesCB.cb, newValue, .OBJC_ASSOCIATION_COPY_NONATOMIC) }
    }
    
    // MARK: - Init
    override init() {
        super.init()
        
        // ---- Geometry (face +Y = front)
        let W: CGFloat = 32
        let H: CGFloat = 41
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
        self.baseChassisPath = p.copy()!
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
        
        // Wheels
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
        let flameTex = Self.makeFlameTextureMedium()
        exhaustL = Self.makeExhaustEmitter(texture: flameTex)
        exhaustR = Self.makeExhaustEmitter(texture: flameTex)
        
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
        pb.allowsRotation = false
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
}

// MARK: - Exhaust helpers
extension CarNode {
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
        e.particleBirthRate = 0
        e.particleLifetime = 0.20
        e.particleLifetimeRange = 0.05
        e.particleSpeed = 140
        e.particleSpeedRange = 50
        e.particlePositionRange = CGVector(dx: 2.0, dy: 0)
        e.particleAlpha = 0.85
        e.particleAlphaSpeed = -2.6
        e.particleScale = 0.18
        e.particleScaleRange = 0.08
        e.particleScaleSpeed = 0.45
        e.particleRotation = 0
        e.particleRotationSpeed = 2
        let colors: [UIColor] = [.white, .orange,
                                 UIColor(red: 1, green: 0.35, blue: 0, alpha: 1),
                                 UIColor(red: 1, green: 0.10, blue: 0, alpha: 0)]
        let times: [NSNumber] = [0.0, 0.3, 0.7, 1.0]
        e.particleColorSequence = SKKeyframeSequence(keyframeValues: colors, times: times)
        e.particleBlendMode = .add
        e.emissionAngle = -CGFloat.pi/2
        e.emissionAngleRange = CGFloat.pi/18
        e.zPosition = 1.5
        return e
    }
    
    private func updateExhaust(speed: CGFloat, fwdMag: CGFloat, dt: CGFloat) {
        let moving = speed > 2.0 || throttle > 0.02
        let speedNorm = CGFloat.clamp(speed / max(maxSpeed, 1), 0, 1)
        let throttleBoost = max(0, throttle)
        let targetMix: CGFloat = moving ? (0.35 * speedNorm + 0.65 * throttleBoost) : 0.0
        
        let a = 1 - exp(-Double(dt / max(exhaustFadeTau, 0.001)))
        exhaustMixLP += (targetMix - exhaustMixLP) * CGFloat(a)
        let mix = CGFloat.clamp(exhaustMixLP, 0, 1)
        
        let maxBR: CGFloat = 320
        let br = maxBR * mix
        let basePS: CGFloat = 120
        let addPS:  CGFloat = 160
        let ps = basePS + addPS * mix
        let scale = 0.16 + 0.22 * mix + 0.10 * (mix * mix)
        let baseLT: CGFloat = 0.30
        let addLT:  CGFloat = 0.10
        let lt = baseLT + addLT * (mix * mix)
        let ltRange = lt * 0.15
        let alphaSpeed = -1.00 + 0.25 * mix
        
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

// MARK: - Air / Verticality
extension CarNode {
    private struct LandAssoc { static var t = 0 }
    private var _lastLandingT: TimeInterval {
        get { (objc_getAssociatedObject(self, &LandAssoc.t) as? TimeInterval) ?? 0 }
        set { objc_setAssociatedObject(self, &LandAssoc.t, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC) }
    }
    
    private struct LifeAssoc { static var max = 0, left = 0 }
    var maxLives: Int {
        get { (objc_getAssociatedObject(self, &LifeAssoc.max) as? Int) ?? 3 }
        set {
            let v = max(1, newValue)
            objc_setAssociatedObject(self, &LifeAssoc.max, v, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
            if livesLeft > v { livesLeft = v }
            onLivesChanged?(livesLeft, v)
        }
    }

    var livesLeft: Int {
        get { (objc_getAssociatedObject(self, &LifeAssoc.left) as? Int) ?? 3 }
        set {
            let v = max(0, newValue)
            objc_setAssociatedObject(self, &LifeAssoc.left, v, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
            onLivesChanged?(v, maxLives)
        }
    }

    func resetLives(_ to: Int? = nil) {
        maxLives = to ?? maxLives
        livesLeft = maxLives
        onLivesChanged?(livesLeft, maxLives)
    }
    
    private struct GhostAssoc { static var g = 0 }
    private var _airGhosting: Bool {
        get { (objc_getAssociatedObject(self, &GhostAssoc.g) as? Bool) ?? false }
        set { objc_setAssociatedObject(self, &GhostAssoc.g, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC) }
    }
    
    var gravity: CGFloat {
        get { objc_getAssociatedObject(self, &Assoc.g) as? CGFloat ?? -1800 }
        set { objc_setAssociatedObject(self, &Assoc.g, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC) }
    }
    var zLift: CGFloat {
        get { objc_getAssociatedObject(self, &Assoc.z) as? CGFloat ?? 0 }
        set { objc_setAssociatedObject(self, &Assoc.z, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC) }
    }
    var vz: CGFloat {
        get { objc_getAssociatedObject(self, &Assoc.v) as? CGFloat ?? 0 }
        set { objc_setAssociatedObject(self, &Assoc.v, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC) }
    }
    var isAirborne: Bool {
        get { objc_getAssociatedObject(self, &Assoc.a) as? Bool ?? false }
        set { objc_setAssociatedObject(self, &Assoc.a, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC) }
    }
    
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
        
        // Altitude ghosting with hysteresis
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
        
        // Landing energy handling
        if wasAir && !isAirborne, let pb = physicsBody {
            if groundHeight < 16 {
                let keep = exp(-dt * 2.0)
                var v = pb.velocity
                v.dx *= keep; v.dy *= keep
                pb.velocity = v
            } else {
                let heading = zRotation + .pi/2
                let f = CGVector(dx: cos(heading),  dy: sin(heading))
                let s = CGVector(dx: -f.dy,         dy: f.dx)
                let v  = pb.velocity
                let vf = v.dx * f.dx + v.dy * f.dy
                let vs = v.dx * s.dx + v.dy * s.dy
                
                let impact = min(1, abs(vzAtLanding) / 1100)
                
                var alignDown: CGFloat = 0
                if let scn = scene as? GameScene {
                    let g = scn.groundGradient(at: position)   // uphill
                    var down = CGVector(dx: -g.dx, dy: -g.dy)
                    let len = max(1e-6, hypot(down.dx, down.dy))
                    down.dx /= len; down.dy /= len
                    alignDown = max(0, f.dx * down.dx + f.dy * down.dy)
                }
                
                let baseKeepF: CGFloat = 0.65 - 0.35 * impact
                let boostF:    CGFloat = 0.35 * alignDown
                let keepFwd = CGFloat.clamp(baseKeepF + boostF, 0.25, 0.95)
                let keepSide = max(0.28, 0.50 - 0.30 * impact)
                
                let newV = CGVector(
                    dx: f.dx * (vf * keepFwd) + s.dx * (vs * keepSide),
                    dy: f.dy * (vf * keepFwd) + s.dy * (vs * keepSide)
                )
                pb.velocity = newV
            }
            
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
    
    /// `heading` is the ramp forward direction.
    func applyRampImpulse(vzAdd: CGFloat, forwardBoost: CGFloat, heading: CGFloat) {
        guard let pb = physicsBody else { return }
        isAirborne = true
        vz += vzAdd
        _airGhosting = true
        pb.collisionBitMask = 0
        speedCapBonus = 0
        
        let f = CGVector(dx: cos(heading), dy: sin(heading))      // ramp forward
        let s = CGVector(dx: -f.dy,          dy: f.dx)            // right
        let v = pb.velocity
        let vf = v.dx * f.dx + v.dy * f.dy
        let vs = v.dx * s.dx + v.dy * s.dy
        
        let steep = min(1.0, max(0.0, vzAdd / 1100.0))
        let loss  = min(launchLossMax, 0.12 + 0.32 * steep)
        let newVf = max(0, vf * (1 - loss)) + forwardBoost
        let newVs = vs * (1 - loss * 0.25)
        
        pb.velocity = CGVector(dx: f.dx * newVf + s.dx * newVs,
                               dy: f.dy * newVf + s.dy * newVs)
    }
}

// MARK: - Shooting (uses BulletNode.ShotStyle API)
extension CarNode {
    // Tuning
    private var bulletSpeed: CGFloat { 1200 }   // world units / s
    private var singleTapCooldown: TimeInterval {
        switch weaponMod { case .rapid: return 0.12; default: return 0.22 }
    }
    private var autoFireInterval:  TimeInterval {
        switch weaponMod { case .rapid: return 0.12; default: return 0.24 }
    }
    private var currentBulletDamage: Int {
        switch weaponMod { case .damage: return 3; default: return 1 }
    }
    private var muzzleOffset: CGFloat { 26 }
    
    // Keys & state
    private var fireArmKey:  String { "car.fire.arm" }
    private var fireLoopKey: String { "car.fire.loop" }
    private struct FireAssoc { static var last: UInt8 = 0 }
    private var _lastShot: TimeInterval {
        get { (objc_getAssociatedObject(self, &FireAssoc.last) as? TimeInterval) ?? 0 }
        set { objc_setAssociatedObject(self, &FireAssoc.last, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC) }
    }
    
    private func currentShotStyle() -> ShotStyle {
        switch weaponMod {
        case .rapid:  return .rapid
        case .damage: return .damage
        case .spread: return .spread
        case .none:   return .rapid
        }
    }
    
    func stopAutoFire() {
        removeAction(forKey: fireArmKey)
        removeAction(forKey: fireLoopKey)
    }
    
    func fireOnce(on scene: SKScene) {
        let now = CACurrentMediaTime()
        if now - _lastShot < singleTapCooldown { return }
        _lastShot = now

        guard let pb = physicsBody else { return }
        let style = currentShotStyle()
        let heading = zRotation + .pi/2

        func spawn(angle: CGFloat) {
            // 1) get a proper muzzle point in WORLD space
            let muzzleWorld = convert(CGPoint(x: 0, y: muzzleOffset), to: scene)
            let dir = CGVector(dx: cos(angle), dy: sin(angle))

            // 2) create bullet centered at .zero (BulletNode below)
            let b = BulletNode(style: style, damage: currentBulletDamage)
            b.zRotation = angle
            b.position  = muzzleWorld              // centered spawn point
            scene.addChild(b)

            // 3) give it velocity, inheriting the car's velocity
            let vCar = pb.velocity
            b.physicsBody?.velocity = CGVector(
                dx: vCar.dx + dir.dx * bulletSpeed,
                dy: vCar.dy + dir.dy * bulletSpeed
            )
        }

        if weaponMod == .spread {
            let off: CGFloat = .pi/26
            spawn(angle: heading)
            spawn(angle: heading - off)
            spawn(angle: heading + off)
        } else {
            spawn(angle: heading)
        }

        muzzleFlash()
    }
    
    func startAutoFire(on scene: SKScene) {
        if action(forKey: fireArmKey) != nil || action(forKey: fireLoopKey) != nil { return }
        fireOnce(on: scene)
        let arm = SKAction.sequence([
            .wait(forDuration: 0.18),
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
    
    private func muzzleFlash() {
        let d: CGFloat = 8
        let flash = SKShapeNode(circleOfRadius: d/2)
        flash.fillColor = .white
        flash.strokeColor = UIColor.white.withAlphaComponent(0.25)
        flash.lineWidth = 1
        flash.zPosition = 10
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

// MARK: - Health (HUD + death/respawn)
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
    
    var hp: Int {
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
    
    func enableCrashContacts() {
        guard let pb = physicsBody else { return }
        pb.contactTestBitMask |= (Category.obstacle | Category.wall)
    }
    
    // Contact → damage
    func handleCrash(contact: SKPhysicsContact, other: SKPhysicsBody) {
        if (other.categoryBitMask & Category.ramp) != 0 { return }
        if other.node is HillNode { return }
        
        if isDead { return }
        let now = CACurrentMediaTime()
        let iFrame: TimeInterval = 0.12
        if now - lastHitTime < iFrame { return }
        lastHitTime = now
        
        let hitPoint = contact.contactPoint
        applyDamage(10, hitWorldPoint: hitPoint)
    }
    
    private func playHitFX(at worldPoint: CGPoint?) {
        removeAction(forKey: "hitFX")
        let bumpUp = SKAction.scale(to: 1.08, duration: 0.08); bumpUp.timingMode = .easeOut
        let bumpDn = SKAction.scale(to: 1.0,  duration: 0.12); bumpDn.timingMode = .easeIn
        let flashOut = SKAction.fadeAlpha(to: 0.65, duration: 0.04)
        let flashIn  = SKAction.fadeAlpha(to: 1.00, duration: 0.12)
        run(.sequence([.group([bumpUp, flashOut]), bumpDn, flashIn]), withKey: "hitFX")
        
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

        // Freeze collisions
        if let pb = physicsBody {
            pb.velocity = .zero
            pb.angularVelocity = 0
            pb.categoryBitMask = 0
            pb.collisionBitMask = 0
            pb.contactTestBitMask = 0
        }

        // Tell scene (shake/FX + camera freeze already happen there)
        delegate?.carNodeDidExplode(self, at: worldPoint)

        // Consume a life
        livesLeft = max(0, livesLeft - 1)

        // Hide the car sprite while “dead”
        isHidden = true

        // Out of lives → stop here and let the scene show Game Over
        if livesLeft == 0 {
            // Tell the scene so it can show the overlay
            delegate?.carNodeDidRunOutOfLives(self)
            // Don’t auto-respawn — scene will call restartAfterGameOver(...)
            return
        }

        // Still have lives → auto-respawn after a short delay
        run(.sequence([
            .wait(forDuration: 1.0),
            .run { [weak self] in
                guard let self else { return }
                let spawn = self.delegate?.carNodeRequestRespawnPoint(self) ?? .zero
                self.position = spawn
                self.zRotation = 0
                self.physicsBody?.velocity = .zero

                if let pb = self.physicsBody {
                    pb.categoryBitMask = Category.car
                    pb.collisionBitMask = Category.wall | Category.obstacle
                    pb.contactTestBitMask = Category.hole | Category.obstacle | Category.ramp
                    self.enableCrashContacts()
                }

                self.resetHP()
                self.resetEnhancements()
                self.isHidden = false
                self.isDead = false
            }
        ]))
    }
    
    func restartAfterGameOver(at spawn: CGPoint) {
        // reset counters/state
        resetLives()         // back to maxLives (default 3)
        resetHP()
        resetEnhancements()
        isDead = false
        isHidden = false

        // restore physics masks
        if let pb = physicsBody {
            pb.velocity = .zero
            pb.angularVelocity = 0
            pb.categoryBitMask = Category.car
            pb.collisionBitMask = Category.wall | Category.obstacle
            pb.contactTestBitMask = Category.hole | Category.obstacle | Category.ramp
            enableCrashContacts()
        }

        position = spawn
        zRotation = 0
        
        onHPChanged?(hp, maxHP)
    }
}

// MARK: - Hills (per-frame multipliers used by GameScene)
extension CarNode {
    private struct HillAssoc { static var spd = 0, acc = 0, drg = 0 }
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

// MARK: - Simple HUD
final class CarHealthHUDNode: SKNode {
    
    private let livesRow = SKNode()
    private var heartNodes: [SKLabelNode] = []

    // public API ---------------------------------------------------------------
    func set(hp: Int, maxHP: Int, shield: Int) {
        let hpC = max(0, min(hp, maxHP))
        let shC = max(0, min(shield, 100)) // cap 100

        // numbers
        hpValueLabel.text = "\(hpC)/\(maxHP)"
        if shC > 0 {
            shieldChip.isHidden = false
            shieldValueLabel.text = "\(shC)"
        } else {
            shieldChip.isHidden = true
        }

        // bars
        let fracHP = CGFloat(hpC) / max(1, CGFloat(maxHP))
        let fracSH = CGFloat(shC) / 100.0

        let hpW = barWidth * fracHP
        hpBar.path = CGPath(roundedRect: CGRect(x: -barWidth/2, y: -barH/2, width: hpW, height: barH),
                            cornerWidth: barH/2, cornerHeight: barH/2, transform: nil)

        let shW = barWidth * fracSH
        shieldOverlay.path = CGPath(roundedRect: CGRect(x: -barWidth/2, y: -barH/2, width: shW, height: barH),
                                    cornerWidth: barH/2, cornerHeight: barH/2, transform: nil)
    }

    func place(at worldPos: CGPoint) { position = worldPos }

    // internals ----------------------------------------------------------------
    private let card     = SKShapeNode()
    private let hpTitle  = SKLabelNode(fontNamed: "Menlo-Bold")
    private let hpValueLabel = SKLabelNode(fontNamed: "Menlo")
    private let shieldChip = SKShapeNode()
    private let shieldLabel = SKLabelNode(fontNamed: "Menlo-Bold")
    private let shieldValueLabel = SKLabelNode(fontNamed: "Menlo")

    private let barBase = SKShapeNode()
    private let hpBar   = SKShapeNode()
    private let shieldOverlay = SKShapeNode()

    private let barWidth: CGFloat = 160
    private let barH: CGFloat = 12

    override init() {
        super.init()
        zPosition = 700

        let w: CGFloat = 180, h: CGFloat = 44
        card.path = CGPath(roundedRect: CGRect(x: -w/2, y: -h/2 - 15, width: w, height: h),
                           cornerWidth: 14, cornerHeight: 14, transform: nil)
        card.fillColor   = UIColor(white: 0, alpha: 0.28)
        card.strokeColor = UIColor(white: 1, alpha: 0.10)
        card.lineWidth   = 1
        addChild(card)

        hpTitle.text = "HP"
        hpTitle.fontSize = 13
        hpTitle.fontColor = UIColor.white.withAlphaComponent(0.9)
        hpTitle.horizontalAlignmentMode = .left
        hpTitle.verticalAlignmentMode = .center
        hpTitle.position = CGPoint(x: -w/2 + 44, y: h/2 - 35.5)
        addChild(hpTitle)

        hpValueLabel.text = "0/0"
        hpValueLabel.fontSize = 13
        hpValueLabel.fontColor = UIColor.white.withAlphaComponent(0.9)
        hpValueLabel.horizontalAlignmentMode = .left
        hpValueLabel.verticalAlignmentMode = .center
        hpValueLabel.position = CGPoint(x: -w/2 + 64, y: h/2 - 36)
        addChild(hpValueLabel)

        let chipH: CGFloat = 18
        let chipW: CGFloat = 90
        shieldChip.path = CGPath(roundedRect: CGRect(x: -chipW/2, y: -chipH/2, width: chipW, height: chipH),
                                 cornerWidth: chipH/2, cornerHeight: chipH/2, transform: nil)
        shieldChip.fillColor   = UIColor.systemBlue.withAlphaComponent(0.25)
        shieldChip.strokeColor = UIColor.systemBlue.withAlphaComponent(0.8)
        shieldChip.lineWidth   = 1
        shieldChip.position = CGPoint(x: -w/2 + 160, y: h/2 - 15)
        addChild(shieldChip)

        shieldLabel.text = "Shield"
        shieldLabel.fontSize = 12
        shieldLabel.fontColor = UIColor.white
        shieldLabel.verticalAlignmentMode = .center
        shieldLabel.horizontalAlignmentMode = .center
        shieldLabel.position = CGPoint(x: -18, y: 0)
        shieldChip.addChild(shieldLabel)

        shieldValueLabel.text = "0"
        shieldValueLabel.fontSize = 12
        shieldValueLabel.fontColor = UIColor.white
        shieldValueLabel.verticalAlignmentMode = .center
        shieldValueLabel.horizontalAlignmentMode = .center
        shieldValueLabel.position = CGPoint(x: 26, y: 0)
        shieldChip.addChild(shieldValueLabel)

        barBase.path = CGPath(roundedRect: CGRect(x: -barWidth/2, y: -barH/2, width: barWidth, height: barH),
                              cornerWidth: barH/2, cornerHeight: barH/2, transform: nil)
        barBase.fillColor = UIColor.white.withAlphaComponent(0.10)
        barBase.strokeColor = UIColor.white.withAlphaComponent(0.08)
        barBase.lineWidth = 1
        barBase.position = CGPoint(x: 0, y: -14)
        addChild(barBase)

        hpBar.fillColor = UIColor.systemGreen.withAlphaComponent(0.9)
        hpBar.strokeColor = .clear
        hpBar.position = barBase.position
        addChild(hpBar)

        shieldOverlay.fillColor = UIColor.systemBlue.withAlphaComponent(0.85)
        shieldOverlay.strokeColor = .clear
        shieldOverlay.position = barBase.position
        shieldOverlay.zPosition = 1
        addChild(shieldOverlay)
        
        livesRow.position = CGPoint(x: 0, y: 14) // above the bar
        addChild(livesRow)
        setLives(left: 3, max: 3)

        shieldChip.isHidden = true
        set(hp: 0, maxHP: 100, shield: 0)
    }

    required init?(coder: NSCoder) { fatalError() }
    
    func setLives(left: Int, max: Int) {
        rebuildLives(left: left, max: max)
    }

    private func rebuildLives(left: Int, max: Int) {
        livesRow.removeAllChildren()
        heartNodes.removeAll()
        
        // layout
        let spacing: CGFloat = 16
        let totalW = spacing * CGFloat(max - 1)
        let startX = -totalW / 2.0
        
        for i in 0..<max {
            let lbl = SKLabelNode(fontNamed: "Menlo-Bold")
            lbl.fontSize = 14
            lbl.verticalAlignmentMode = .center
            lbl.horizontalAlignmentMode = .center
            let filled = i < left
            lbl.text = filled ? "♥︎" : "♡"
            lbl.fontColor = filled ? UIColor.systemRed : UIColor.white.withAlphaComponent(0.6)
            lbl.position = CGPoint(x: startX + CGFloat(i) * spacing, y: 0)
            livesRow.addChild(lbl)
            heartNodes.append(lbl)
        }
    }
}

// MARK: - Enhancements (real gameplay effects, persistent)
private final class CGPathBox: NSObject { let value: CGPath; init(_ v: CGPath) { value = v } }

extension CarNode {
    
    // Store the original chassis for physics rebuilds after Mini Mode.
    private struct EnhAssoc {
        static var basePath = 0
        static var shield = 0
        static var weapon = 0
        static var control = 0
        static var mini = 0
        static var baseTurn = 0
        static var baseTraction = 0
    }
    
    // Keep the raw path boxed to avoid CF bridging warnings.
    var baseChassisPath: CGPath? {
        get { (objc_getAssociatedObject(self, &EnhAssoc.basePath) as? CGPathBox)?.value }
        set {
            if let p = newValue {
                objc_setAssociatedObject(self, &EnhAssoc.basePath, CGPathBox(p), .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
            } else {
                objc_setAssociatedObject(self, &EnhAssoc.basePath, nil, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
            }
        }
    }
    
    // MARK: Shield (0…100). Absorbs damage before HP.
    var shield: Int {
        get { (objc_getAssociatedObject(self, &EnhAssoc.shield) as? Int) ?? 0 }
        set {
            let clamped = max(0, min(100, newValue))
            objc_setAssociatedObject(self, &EnhAssoc.shield, clamped, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
            (scene as? CarShieldReporting)?.onShieldChanged?(clamped)
        }
    }
    
    // MARK: Weapon mod (one at a time)
    enum WeaponMod: Int { case none = 0, rapid, damage, spread
        var display: String {
            switch self {
            case .none: return "None"
            case .rapid: return "Rapid Fire"
            case .damage: return "Damage Boost"
            case .spread: return "Spread Shot"
            }
        }
    }
    var weaponMod: WeaponMod {
        get { WeaponMod(rawValue: (objc_getAssociatedObject(self, &EnhAssoc.weapon) as? Int) ?? 0) ?? .none }
        set {
            objc_setAssociatedObject(self, &EnhAssoc.weapon, newValue.rawValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
            (scene as? CarWeaponReporting)?.onWeaponChanged?(newValue.display)
        }
    }
    
    // MARK: Control boost (persistent; non-stacking)
    var controlBoostActive: Bool {
        get { (objc_getAssociatedObject(self, &EnhAssoc.control) as? Bool) ?? false }
        set {
            let was = controlBoostActive
            objc_setAssociatedObject(self, &EnhAssoc.control, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
            if newValue == was { return }
            if objc_getAssociatedObject(self, &EnhAssoc.baseTurn) == nil {
                objc_setAssociatedObject(self, &EnhAssoc.baseTurn, self.turnRate, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
            }
            if objc_getAssociatedObject(self, &EnhAssoc.baseTraction) == nil {
                objc_setAssociatedObject(self, &EnhAssoc.baseTraction, self.traction, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
            }
            if newValue {
                self.turnRate = (objc_getAssociatedObject(self, &EnhAssoc.baseTurn) as? CGFloat ?? self.turnRate) * 1.22
                self.traction = (objc_getAssociatedObject(self, &EnhAssoc.baseTraction) as? CGFloat ?? self.traction) * 1.18
            } else {
                if let base = objc_getAssociatedObject(self, &EnhAssoc.baseTurn) as? CGFloat { self.turnRate = base }
                if let base = objc_getAssociatedObject(self, &EnhAssoc.baseTraction) as? CGFloat { self.traction = base }
            }
            (scene as? CarStatusReporting)?.onControlBoostChanged?(newValue)
        }
    }
    
    // MARK: Mini Mode (persistent; non-stacking)
    var miniModeActive: Bool {
        get { (objc_getAssociatedObject(self, &EnhAssoc.mini) as? Bool) ?? false }
        set {
            let was = miniModeActive
            objc_setAssociatedObject(self, &EnhAssoc.mini, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
            if newValue == was { return }
            
            let targetScale: CGFloat = newValue ? 0.94 : 1.0
            let act = SKAction.group([
                .scaleX(to: targetScale, duration: 0.32),
                .scaleY(to: targetScale, duration: 0.32)
            ])
            act.timingMode = .easeInEaseOut
            run(act)
            rebuildBody(scale: targetScale)
            (scene as? CarStatusReporting)?.onMiniModeChanged?(newValue)
        }
    }
    
    private func rebuildBody(scale: CGFloat) {
        guard let base = baseChassisPath, let old = physicsBody else { return }
        var t = CGAffineTransform(scaleX: scale, y: scale)
        let scaled = base.copy(using: &t) ?? base
        
        let saveCat = old.categoryBitMask
        let saveCol = old.collisionBitMask
        let saveCon = old.contactTestBitMask
        let dyn = old.isDynamic
        let precise = old.usesPreciseCollisionDetection
        
        let pb = SKPhysicsBody(polygonFrom: scaled)
        pb.isDynamic = dyn
        pb.allowsRotation = false
        pb.friction = 0
        pb.linearDamping = drag
        pb.angularDamping = 2
        pb.affectedByGravity = false
        pb.usesPreciseCollisionDetection = precise
        pb.categoryBitMask = saveCat
        pb.collisionBitMask = saveCol
        pb.contactTestBitMask = saveCon
        self.physicsBody = pb
        
        _groundMask = pb.collisionBitMask
    }
    
    // MARK: Enhancement application (GameScene calls this when picking up)
    @discardableResult
    func applyEnhancement(_ kind: EnhancementKind) -> Bool {
        switch kind {
        case .hp20:
            if hp >= maxHP { return false }
            hp = min(maxHP, hp + 20); onHPChanged?(hp, maxHP); return true
            
        case .shield20:
            if shield >= 100 { return false }
            shield = min(100, shield + 20); return true
            
        case .weaponRapid:   weaponMod = .rapid;  return true
        case .weaponDamage:  weaponMod = .damage; return true
        case .weaponSpread:  weaponMod = .spread; return true
        case .control:       if controlBoostActive { return false }; controlBoostActive = true; return true
        case .shrink:        if miniModeActive { return false }; miniModeActive = true; return true
            
        @unknown default: return false
        }
    }
    
    // Damage helpers routed through shield
    func applyDamage(_ raw: Int, hitWorldPoint: CGPoint? = nil) {
        var dmg = max(0, raw)
        if shield > 0, dmg > 0 {
            let used = min(shield, dmg)
            shield -= used
            dmg    -= used
        }
        if dmg > 0 { hp = max(0, hp - dmg) }
        onHPChanged?(hp, maxHP)
        playHitFX(at: hitWorldPoint)
        if hp == 0 {
            let world = hitWorldPoint
            ?? (scene.flatMap { self.convert(.zero, to: $0) })
            ?? .zero
            explode(at: world)
        }
    }
    
    @objc func resetEnhancements() {
        controlBoostActive = false
        miniModeActive = false
        weaponMod = .none
        shield = 0
    }
    
    @discardableResult
    func applyIncomingCrashImpulse(_ impulse: CGFloat) -> Int {
        let raw = max(0, impulse - 30) * 0.28
        let dmg = Int(raw.rounded())
        guard dmg > 0 else { return 0 }
        return applyIncomingDamage(dmg)
    }
    
    @discardableResult
    func applyIncomingDamage(_ amount: Int) -> Int {
        var remaining = max(0, amount)
        if shield > 0 {
            let absorbed = min(shield, remaining)
            shield -= absorbed
            remaining -= absorbed
        }
        if remaining > 0 {
            let was = hp
            hp = max(0, hp - remaining)
            onHPChanged?(hp, maxHP)
            return was - hp
        }
        return 0
    }
}

// MARK: - Driving update
extension CarNode {
    func update(_ dt: CGFloat) {
        guard let pb = physicsBody else { return }
        let heading = zRotation + .pi/2
        let fwd     = CGVector(dx: cos(heading),  dy: sin(heading))
        let right   = CGVector(dx: -sin(heading), dy: cos(heading))
        
        if isAirborne {
            let retain = exp(-dt * 2.3)
            var vv = pb.velocity
            vv.dx *= retain; vv.dy *= retain
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
        
        var v      = pb.velocity
        let fwdMag = v.dx * fwd.dx + v.dy * fwd.dy
        let latMag = v.dx * right.dx + v.dy * right.dy
        
        let latKill = 1 - exp(-dt * traction * 4.0)
        v.dx -= right.dx * latMag * latKill
        v.dy -= right.dy * latMag * latKill
        pb.velocity = v
        
        if hillDragK > 0 {
            let keep = exp(-dt * hillDragK)
            var vv = pb.velocity
            vv.dx *= keep; vv.dy *= keep
            pb.velocity = vv
        }
        
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
        
        // drive
        let input = throttle.clamped(-1, 1)
        let opposes = (input > 0 && fwdMag < 0) || (input < 0 && fwdMag > 0)
        if opposes {
            let sign: CGFloat = fwdMag >= 0 ? 1 : -1
            pb.applyForce(fwd.scaled(-sign * brakeForce))
        } else {
            pb.applyForce(fwd.scaled(input * acceleration * max(0, hillAccelMul)))
        }
        
        let capForwardBase = maxSpeed + max(0, speedCapBonus)
        let capForward     = capForwardBase * max(0.1, hillSpeedMul)
        let cap = (fwdMag >= 0 ? capForward : maxSpeed * reverseSpeedFactor)
        let speed = hypot(pb.velocity.dx, pb.velocity.dy)
        if speed > cap {
            let s = cap / max(speed, 0.001)
            pb.velocity = CGVector(dx: pb.velocity.dx * s, dy: pb.velocity.dy * s)
        }
        
        let speedScale = 0.50 + 0.50 * CGFloat.clamp(abs(fwdMag) / 240.0, 0, 1)
        let slowAssist = 1.0 + CGFloat.clamp(80 - abs(fwdMag), 0, 80) / 90.0
        let commandedYaw = steer.clamped(-1, 1) * turnRate * speedScale * slowAssist
        let maxYaw: CGFloat = 4.0
        let yaw = CGFloat.clamp(commandedYaw, -maxYaw, maxYaw)
        zRotation += yaw * dt
        pb.angularVelocity = 0
        
        updateExhaust(speed: hypot(pb.velocity.dx, pb.velocity.dy), fwdMag: fwdMag, dt: dt)
    }
}
