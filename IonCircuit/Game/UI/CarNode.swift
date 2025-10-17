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
    func carNodeDidRunOutOfLives(_ car: CarNode)
}

// Optional HUD hooks in the scene
@objc protocol CarShieldReporting { @objc optional func onShieldChanged(_ value: Int) }
@objc protocol CarWeaponReporting { @objc optional func onWeaponChanged(_ name: String) }
@objc protocol CarStatusReporting {
    @objc optional func onControlBoostChanged(_ active: Bool)
    @objc optional func onMiniModeChanged(_ active: Bool)
}

// GameScene cleans these
@objc protocol CarEnhancementResetting { func resetEnhancements() }

private struct LivesCB { static var cb = 0 }

// Store user callbacks (so we can wrap them to refresh mini HUD first)
private struct HUDAssoc {
    static var hpUserCB = 0
    static var livesUserCB = 0
}

final class CarNode: SKNode {
    
    private enum Assoc {
        static var g: UInt8 = 0, z: UInt8 = 0, v: UInt8 = 0, a: UInt8 = 0
        static var m: UInt8 = 0, s: UInt8 = 0
        static var delegate = 0
        static var shield: UInt8 = 0
        static var wpn:    UInt8 = 0
        static var ctrlOn: UInt8 = 0
        static var miniOn: UInt8 = 0
    }
    
    // ---- Tuning ----
    var acceleration: CGFloat = 1240.0
    var maxSpeed: CGFloat     = 2720.0
    var reverseSpeedFactor: CGFloat = 0.55
    var turnRate: CGFloat     = 4.2
    var traction: CGFloat     = 12.0
    var drag: CGFloat         = 1.0
    var brakeForce: CGFloat   = 2200.0
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
    
    // Anyone else may read it later
    var baseChassisPath: CGPath = CGMutablePath()
    
    // MARK: - Mini UI (attached to the car)
    private let miniHUD = SKNode()
    private let miniHPBack = SKShapeNode()
    private let miniHPBar  = SKShapeNode()
    private let miniShieldBar  = SKShapeNode()    // overlay (blue) above HP
    private let miniLivesNode = SKNode()
    private var heartNodes: [SKShapeNode] = []
    
    private struct MiniUI {
        static let hpW: CGFloat = 60
        static let hpH: CGFloat = 8
        static let hpCorner: CGFloat = 4
        static let overlayInset: CGFloat = 1      // shield overlay inset
    }
    
    private func installMiniUIIfNeeded() {
        guard miniHUD.parent == nil else { return }
        // Keep the chip just above the car and centered
        miniHUD.zPosition = 150
        miniHUD.position = CGPoint(x: 0, y: 48)   // centered above car
        addChild(miniHUD)
        
        // Background capsule
        let backRect = CGRect(x: -MiniUI.hpW/2, y: 0, width: MiniUI.hpW, height: MiniUI.hpH)
        miniHPBack.path = CGPath(roundedRect: backRect,
                                 cornerWidth: MiniUI.hpCorner,
                                 cornerHeight: MiniUI.hpCorner,
                                 transform: nil)
        miniHPBack.fillColor = UIColor(white: 0, alpha: 0.25)
        miniHPBack.strokeColor = UIColor(white: 1, alpha: 0.16)
        miniHPBack.lineWidth = 1
        miniHUD.addChild(miniHPBack)
        
        // HP bar
        miniHPBar.strokeColor = .clear
        miniHUD.addChild(miniHPBar)
        
        // Shield overlay (sits ON the HP bar region)
        miniShieldBar.strokeColor = .clear
        miniShieldBar.zPosition = miniHPBar.zPosition + 1
        miniShieldBar.alpha = 0.95
        miniHUD.addChild(miniShieldBar)
        
        // Lives row above the bar
        miniHUD.addChild(miniLivesNode)
        miniLivesNode.position = CGPoint(x: 0, y: MiniUI.hpH + 8)
        
        refreshMiniHUD()
    }
    
    private func layoutMiniHearts() {
        // Build enough hearts
        while heartNodes.count < maxLives {
            let h = SKShapeNode(path: makeHeartPath(size: 7)) // bigger & clearer
            h.fillColor = .systemRed
            h.strokeColor = UIColor.black.withAlphaComponent(0.25)
            h.lineWidth = 0.6
            h.zPosition = 2
            h.name = "lifeHeart"                 // helps the name check
            if h.userData == nil { h.userData = NSMutableDictionary() }
            h.userData?["noTint"] = true         // hard guard used above
            miniLivesNode.addChild(h)
            heartNodes.append(h)
        }
        // Position & on/off by lives
        let n = maxLives
        let spacing: CGFloat = 12
        let width = spacing * CGFloat(max(0, n - 1))
        for (i, node) in heartNodes.enumerated() {
            node.isHidden = i >= n
            node.alpha = (i < livesLeft) ? 1.0 : 0.25
            node.position = CGPoint(x: -width/2 + CGFloat(i) * spacing, y: 0)
        }
    }
    
    private func makeHeartPath(size r: CGFloat) -> CGPath {
        // classic heart
        let p = CGMutablePath()
        p.move(to: CGPoint(x: 0, y: -r))
        p.addCurve(to: CGPoint(x: -r, y: 0),
                   control1: CGPoint(x: -0.6*r, y: -1.4*r),
                   control2: CGPoint(x: -r,     y: -0.2*r))
        p.addArc(center: CGPoint(x: -r/2, y: 0.2*r), radius: r/2,
                 startAngle: .pi, endAngle: 0, clockwise: false)
        p.addArc(center: CGPoint(x:  r/2, y: 0.2*r), radius: r/2,
                 startAngle: .pi, endAngle: 0, clockwise: false)
        p.addCurve(to: CGPoint(x: 0, y: -r),
                   control1: CGPoint(x: r,     y: -0.2*r),
                   control2: CGPoint(x: 0.6*r, y: -1.4*r))
        p.closeSubpath()
        return p
    }
    
    // MARK: lives callback (wrap to also refresh mini HUD)
    var onLivesChanged: ((Int, Int) -> Void)? {
        get { objc_getAssociatedObject(self, &LivesCB.cb) as? (Int, Int) -> Void }
        set {
            objc_setAssociatedObject(self, &HUDAssoc.livesUserCB, newValue, .OBJC_ASSOCIATION_COPY_NONATOMIC)
            let wrapper: (Int, Int) -> Void = { [weak self] left, max in
                guard let self else { return }
                self.refreshMiniHUD()
                if let user = objc_getAssociatedObject(self, &HUDAssoc.livesUserCB) as? (Int, Int) -> Void {
                    user(left, max)
                }
            }
            objc_setAssociatedObject(self, &LivesCB.cb, wrapper, .OBJC_ASSOCIATION_COPY_NONATOMIC)
        }
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
        pb.categoryBitMask      = Category.car
        pb.collisionBitMask     = Category.wall | Category.obstacle | Category.car   // ← add .car
        pb.contactTestBitMask   = Category.hole | Category.obstacle | Category.ramp | Category.car // ← add .car
        self.physicsBody = pb
        
        zRotation = 0
        
        // Mount the mini HUD chip
        installMiniUIIfNeeded()
        refreshMiniHUD()
    }
    
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    
    // MARK: Mini HUD rendering
    private func refreshMiniHP() {
        // 0…1 HP fraction
        let frac = max(0, min(1, CGFloat(hp) / CGFloat(maxHP)))
        var w = MiniUI.hpW * frac
        if w < 1 { w = 1 }
        
        let x0 = -MiniUI.hpW/2
        let rect = CGRect(x: x0, y: 0, width: w, height: MiniUI.hpH)
        let cw = min(MiniUI.hpCorner, rect.width * 0.5)
        
        let p = CGMutablePath()
        p.addRoundedRect(in: rect, cornerWidth: cw, cornerHeight: cw)
        miniHPBar.path = p
        
        let col: UIColor
        switch frac {
        case ..<0.25: col = .systemRed
        case ..<0.55: col = .systemOrange
        default:      col = .systemGreen
        }
        miniHPBar.fillColor = col.withAlphaComponent(0.95)
    }
    
    private func refreshMiniShield() {
        // Draw a blue overlay on top of HP bar region, width by 0…1 of shield
        let sFrac = max(0, min(1, CGFloat(shield) / 100.0))
        miniShieldBar.isHidden = sFrac <= 0
        
        guard sFrac > 0 else { return }
        
        let inset = MiniUI.overlayInset
        let baseRect = CGRect(x: -MiniUI.hpW/2 + inset,
                              y: inset,
                              width: (MiniUI.hpW - inset*2) * sFrac,
                              height: MiniUI.hpH - inset*2)
        let cw = min(MiniUI.hpCorner - inset, baseRect.width * 0.5)
        let p = CGMutablePath()
        p.addRoundedRect(in: baseRect, cornerWidth: cw, cornerHeight: cw)
        miniShieldBar.path = p
        miniShieldBar.fillColor = UIColor.systemBlue.withAlphaComponent(0.80)
        miniShieldBar.blendMode = .alpha
    }
}

// Keep the chip synced & upright
extension CarNode {
    func refreshMiniHUD() {
        miniHUD.isHidden = isHidden || isDead
        refreshMiniHP()
        refreshMiniShield()
        layoutMiniHearts()
        // Counter-rotate so the bar stays horizontal on screen
        miniHUD.zRotation = -zRotation
    }
}

// MARK: - Exhaust helpers
extension CarNode {
    static func makeFlameTextureMedium() -> SKTexture {
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
    
    static func makeExhaustEmitter(texture: SKTexture) -> SKEmitterNode {
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
    
    func updateExhaust(speed: CGFloat, fwdMag: CGFloat, dt: CGFloat) {
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

// MARK: - Damage / enhancements plumbing used by GameScene
extension CarNode {
    
    /// Applies incoming damage. Uses shield first, then HP, triggers FX & death.
    func applyDamage(_ amount: Int, hitWorldPoint: CGPoint?) {
        guard amount > 0, !isDead else { return }
        
        var remaining = amount
        
        // Shield absorbs first
        if shield > 0 {
            let absorbed = min(shield, remaining)
            shield -= absorbed
            remaining -= absorbed
        }
        
        // HP next
        if remaining > 0 {
            hp = max(0, hp - remaining)
            onHPChanged?(hp, maxHP)
            refreshMiniHP()
        }
        
        // Hit feedback
        playHitFX(at: hitWorldPoint)
        
        // Death
        if hp <= 0 { explode(at: hitWorldPoint ?? position) }
    }
}

extension CarNode {
    
    /// Called by GameScene when a pickup is touched. Returns true if consumed.
    @discardableResult
    func applyEnhancement(_ kind: EnhancementKind) -> Bool {
        switch kind {
        case .hp20:
            let before = hp
            hp = min(maxHP, hp + 20)
            if hp != before { onHPChanged?(hp, maxHP); refreshMiniHP() }
            return hp > before
            
        case .shield20:
            let before = shield
            shield = min(100, shield + 20)   // refreshMiniShield is called by setter
            return shield > before
            
        case .weaponRapid:  weaponMod = .rapid;  return true
        case .weaponDamage: weaponMod = .damage; return true
        case .weaponSpread: weaponMod = .spread; return true
            
        case .control:
            if controlBoostActive { return false }
            controlBoostActive = true
            return true
            
        case .shrink:
            if miniModeActive { return false }
            miniModeActive = true
            return true
            
        @unknown default:
            return false
        }
    }
}

// MARK: - Enhancements state (shield / weapon / status flags)
extension CarNode {
    
    enum WeaponMod: Int { case none = 0, rapid, damage, spread }
    
    var weaponMod: WeaponMod {
        get { WeaponMod(rawValue: (objc_getAssociatedObject(self, &Assoc.wpn) as? Int) ?? 0) ?? .none }
        set {
            objc_setAssociatedObject(self, &Assoc.wpn, newValue.rawValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
            (scene as? CarWeaponReporting)?.onWeaponChanged?("\(newValue)")
        }
    }
    
    /// 0…100. Absorbs damage before HP.
    var shield: Int {
        get { (objc_getAssociatedObject(self, &Assoc.shield) as? Int) ?? 0 }
        set {
            let v = max(0, min(100, newValue))
            objc_setAssociatedObject(self, &Assoc.shield, v, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
            refreshMiniShield()
            (scene as? CarShieldReporting)?.onShieldChanged?(v)
        }
    }
    
    /// Permanent until reset (no TTL).
    var controlBoostActive: Bool {
        get { (objc_getAssociatedObject(self, &Assoc.ctrlOn) as? Bool) ?? false }
        set {
            objc_setAssociatedObject(self, &Assoc.ctrlOn, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
            (scene as? CarStatusReporting)?.onControlBoostChanged?(newValue)
        }
    }
    
    /// Permanent until reset. Visual scale for feedback only.
    var miniModeActive: Bool {
        get { (objc_getAssociatedObject(self, &Assoc.miniOn) as? Bool) ?? false }
        set {
            let old = miniModeActive
            objc_setAssociatedObject(self, &Assoc.miniOn, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
            (scene as? CarStatusReporting)?.onMiniModeChanged?(newValue)
            if old != newValue {
                removeAction(forKey: "cn.mini.scale")
                let target: CGFloat = newValue ? 0.9 : 1.0
                let act = SKAction.scale(to: target, duration: 0.18)
                act.timingMode = .easeOut
                run(act, withKey: "cn.mini.scale")
            }
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
    
    struct GhostAssoc { static var g = 0 }
    
    var _airGhosting: Bool {
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
    
    var _groundMask: UInt32 {
        get { objc_getAssociatedObject(self, &Assoc.m) as? UInt32 ?? (physicsBody?.collisionBitMask ?? 0) }
        set { objc_setAssociatedObject(self, &Assoc.m, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC) }
    }
    
    var shadowNode: SKShapeNode? {
        get { objc_getAssociatedObject(self, &Assoc.s) as? SKShapeNode }
        set { objc_setAssociatedObject(self, &Assoc.s, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC) }
    }
    
    /// Call once after creation
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
    private var bulletSpeed: CGFloat { 1200 }
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
            let muzzleWorld = convert(CGPoint(x: 0, y: muzzleOffset), to: scene)
            let dir = CGVector(dx: cos(angle), dy: sin(angle))
            let b = BulletNode(style: style, damage: currentBulletDamage)
            b.name = "bullet"
            b.zRotation = angle
            b.position  = muzzleWorld
            
            b.physicsBody?.categoryBitMask      = Category.bullet
            b.physicsBody?.collisionBitMask     = 0               // usually no physical push
            b.physicsBody?.contactTestBitMask   = Category.obstacle | Category.wall | Category.ramp | Category.car
            // Optional: tag the shooter so you can ignore self-hits (see userData read above)
            b.userData = (b.userData ?? NSMutableDictionary())
            b.userData?["owner"] = self
            
            scene.addChild(b)
            
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
        set {
            objc_setAssociatedObject(self, &HUDAssoc.hpUserCB, newValue, .OBJC_ASSOCIATION_COPY_NONATOMIC)
            let wrapper: (Int, Int) -> Void = { [weak self] hp, maxHP in
                guard let self else { return }
                self.refreshMiniHUD()
                if let user = objc_getAssociatedObject(self, &HUDAssoc.hpUserCB) as? (Int, Int) -> Void {
                    user(hp, maxHP)
                }
            }
            objc_setAssociatedObject(self, &Holder.cbKey, wrapper, .OBJC_ASSOCIATION_COPY_NONATOMIC)
        }
    }
    
    func resetHP() {
        hp = maxHP
        isDead = false
        onHPChanged?(hp, maxHP)
    }
    
    func enableCrashContacts() {
        guard let pb = physicsBody else { return }
        pb.contactTestBitMask |= (Category.obstacle | Category.wall | Category.car) // ← add .car
    }
    
    func handleCrash(contact: SKPhysicsContact, other: SKPhysicsBody, damage: Int) {
        guard let pb = physicsBody, !isDead else { return }

         // --- Always do a small bounce (walls, hills, obstacles, cars) ---
         let hitPoint = contact.contactPoint

         // outward-ish normal
         var n = CGVector(dx: position.x - hitPoint.x, dy: position.y - hitPoint.y)
         var len = hypot(n.dx, n.dy)
         if len < 1e-5 {
             // fallback: opposite relative velocity
             let rel = CGVector(dx: pb.velocity.dx - other.velocity.dx,
                                dy: pb.velocity.dy - other.velocity.dy)
             n = CGVector(dx: -rel.dx, dy: -rel.dy)
             len = max(1e-5, hypot(n.dx, n.dy))
         }
         n.dx /= len; n.dy /= len

         // scale with approach speed a bit
         let rel = CGVector(dx: pb.velocity.dx - other.velocity.dx,
                            dy: pb.velocity.dy - other.velocity.dy)
         let approach = max(0, -(rel.dx * n.dx + rel.dy * n.dy))
         var j = 15 + 0.25 * approach                  // tune feel
         j = CGFloat.clamp(j, 5, 20)
         pb.applyImpulse(CGVector(dx: n.dx * j, dy: n.dy * j))

         // trim inward component so we don't stick
         var v = pb.velocity
         let inward = -(v.dx * n.dx + v.dy * n.dy)
         if inward > 0 {
             v.dx += n.dx * inward
             v.dy += n.dy * inward
             pb.velocity = v
         }

         // --- Damage rules: walls & hills (and ramps) do NOT damage ---
         let isWall = (other.categoryBitMask & Category.wall) != 0
         let isRamp = (other.categoryBitMask & Category.ramp) != 0
         let isHill = (other.node is HillNode)
         let noDamage = isWall || isHill || isRamp
         if noDamage { return }

         // i-frames for damaging hits only
         let now = CACurrentMediaTime()
         let iFrame: TimeInterval = 0.12
         if now - lastHitTime < iFrame { return }
         lastHitTime = now
        applyDamage(damage, hitWorldPoint: hitPoint)
    }
    
    func handleCrash(contact: SKPhysicsContact, other: SKPhysicsBody) {
        handleCrash(contact: contact, other: other, damage: 10)
    }

    func playHitFX(at worldPoint: CGPoint?) {
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
    
    func explode(at worldPoint: CGPoint) {
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
        
        delegate?.carNodeDidExplode(self, at: worldPoint)
        
        // Consume a life
        livesLeft = max(0, livesLeft - 1)
        
        // Hide while “dead”
        isHidden = true
        miniHUD.isHidden = true
        
        if livesLeft == 0 {
            delegate?.carNodeDidRunOutOfLives(self)
            return
        }
        
        // Auto-respawn
        run(.sequence([
            .wait(forDuration: 1.0),
            .run { [weak self] in
                guard let self else { return }
                let spawn = self.delegate?.carNodeRequestRespawnPoint(self) ?? .zero
                self.position = spawn
                self.zRotation = 0
                self.physicsBody?.velocity = .zero
                
                if let pb = self.physicsBody {
                    pb.categoryBitMask    = Category.car
                    pb.collisionBitMask   = Category.wall | Category.obstacle | Category.car      // ← add .car
                    pb.contactTestBitMask = Category.hole | Category.obstacle | Category.ramp | Category.car // ← add .car
                    self.enableCrashContacts()
                }
                
                self.resetHP()
                self.resetEnhancements()
                self.isHidden = false
                self.isDead = false
                self.refreshMiniHUD()
                self.miniHUD.isHidden = false
            }
        ]))
    }
    
    func restartAfterGameOver(at spawn: CGPoint) {
        resetLives()
        resetHP()
        resetEnhancements()
        isDead = false
        isHidden = false
        
        if let pb = physicsBody {
            pb.velocity = .zero
            pb.angularVelocity = 0
            pb.categoryBitMask    = Category.car
            pb.collisionBitMask   = Category.wall | Category.obstacle | Category.car      // ← add .car
            pb.contactTestBitMask = Category.hole | Category.obstacle | Category.ramp | Category.car // ← add .car
            enableCrashContacts()
        }
        
        position = spawn
        zRotation = 0
        
        onHPChanged?(hp, maxHP)
        refreshMiniHUD()
        miniHUD.isHidden = false
    }
}

// MARK: - Hills (per-frame multipliers used by GameScene)
extension CarNode {
    private struct HillAssoc { static var spd = 0, acc = 0, drg = 0 }
    var hillSpeedMul: CGFloat {
        get { objc_getAssociatedObject(self, &HillAssoc.spd) as? CGFloat ?? 1 }
        set { objc_setAssociatedObject(self, &HillAssoc.spd, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC) }
    }
    var hillAccelMul: CGFloat {
        get { objc_getAssociatedObject(self, &HillAssoc.acc) as? CGFloat ?? 1 }
        set { objc_setAssociatedObject(self, &HillAssoc.acc, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC) }
    }
    var hillDragK: CGFloat {
        get { objc_getAssociatedObject(self, &HillAssoc.drg) as? CGFloat ?? 0 }
        set { objc_setAssociatedObject(self, &HillAssoc.drg, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC) }
    }
}

// MARK: - Role & Simple AI
extension CarNode {
    
    enum Kind: Int { case player = 0, enemy = 1 }
    
    private struct RoleAssoc { static var k = 0, tgt = 0, wander = 0 }
    
    var kind: Kind {
        get { Kind(rawValue: (objc_getAssociatedObject(self, &RoleAssoc.k) as? Int) ?? 0) ?? .player }
        set { objc_setAssociatedObject(self, &RoleAssoc.k, newValue.rawValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC) }
    }
    
    weak var aiTarget: CarNode? {
        get { objc_getAssociatedObject(self, &RoleAssoc.tgt) as? CarNode }
        set { objc_setAssociatedObject(self, &RoleAssoc.tgt, newValue, .OBJC_ASSOCIATION_ASSIGN) }
    }
    
    private var _wander: CGFloat {
        get { (objc_getAssociatedObject(self, &RoleAssoc.wander) as? CGFloat) ?? 0 }
        set { objc_setAssociatedObject(self, &RoleAssoc.wander, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC) }
    }
    
    func configure(kind: Kind, target: CarNode? = nil) {
        self.kind = kind
        self.aiTarget = target
        if kind == .enemy { enableCrashContacts() }
        // scale chip a bit smaller on enemies
        miniHUD.setScale(kind == .player ? 0.85 : 0.65)
    }
    
    @inline(__always) private func clamp(_ v: CGFloat, _ a: CGFloat, _ b: CGFloat) -> CGFloat {
        return max(a, min(b, v))
    }
    
    @inline(__always) private func shortestAngle(from: CGFloat, to: CGFloat) -> CGFloat {
        var d = to - from
        while d > .pi { d -= (.pi * 2) }
        while d < -.pi { d += (.pi * 2) }
        return d
    }
    
    func runEnemyAI(_ dt: CGFloat) {
        if isDead { throttle = 0; steer = 0.001; return }
        guard physicsBody != nil else { return }
        // (basic AI intentionally left commented out for now)
    }
}

// HSB utilities + visual distance
extension UIColor {
    func hsb() -> (h: CGFloat, s: CGFloat, b: CGFloat) {
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard getHue(&h, saturation: &s, brightness: &b, alpha: &a) else { return (0,0,0) }
        return (h,s,b)
    }
    func isVisuallyClose(to other: UIColor,
                         hueThresh: CGFloat = 0.08,
                         satThresh: CGFloat = 0.18,
                         brightThresh: CGFloat = 0.22) -> Bool {
        let a = self.hsb(), b = other.hsb()
        let dhRaw = abs(a.h - b.h)
        let dh = min(dhRaw, 1 - dhRaw)
        return dh < hueThresh && abs(a.s - b.s) < satThresh && abs(a.b - b.b) < brightThresh
    }
}

// Random color distinct from `avoid`
func randomDistinctColor(avoid: UIColor) -> UIColor {
    let avoidHSB = avoid.hsb()
    for _ in 0..<12 {
        let h = CGFloat.random(in: 0..<1)
        let s = CGFloat.random(in: 0.60...0.95)
        let b = CGFloat.random(in: 0.70...0.98)
        let candidate = UIColor(hue: h, saturation: s, brightness: b, alpha: 1)
        if !candidate.isVisuallyClose(to: avoid) { return candidate }
    }
    let h2 = fmod(avoidHSB.h + 0.5, 1.0)
    let s2 = max(avoidHSB.s, 0.75)
    let b2 = max(avoidHSB.b, 0.85)
    return UIColor(hue: h2, saturation: s2, brightness: b2, alpha: 1)
}

func tintCar(_ car: SKNode, to color: UIColor) {
    func visit(_ n: SKNode) {
        // If this node (or any ancestor) is marked as no-tint, skip its subtree.
        if (n.userData?["noTint"] as? Bool) == true { return }
        if let name = n.name?.lowercased(),
           name.contains("heart") || name.contains("life") || name.contains("hud") {
            return
        }

        if let sh = n as? SKShapeNode,
           sh.zPosition == 2,                 // your original “car body” filter
           sh.fillColor != .clear {
            sh.fillColor = color
        }
        for c in n.children { visit(c) }
    }
    visit(car)
}


extension CarNode {
    /// Simple kinematic controller
    func update(_ dt: CGFloat) {
        guard let pb = physicsBody, dt > 0 else { return }
        
        // Heading (forward = +Y)
        let heading = zRotation + .pi/2
        let f = CGVector(dx: cos(heading), dy: sin(heading))
        let r = CGVector(dx: -f.dy, dy: f.dx)
        
        var v = pb.velocity
        let fwd = v.dx * f.dx + v.dy * f.dy
        let lat = v.dx * r.dx + v.dy * r.dy
        
        // Control boost
        let steerGain   = (controlBoostActive ? turnRate * 1.25 : turnRate)
        let tractionK   = (controlBoostActive ? traction * 1.25 : traction)
        
        // Steering (body rotation locked)
        zRotation += steer * steerGain * dt
        
        // Caps
        let capFwd   = (maxSpeed + speedCapBonus) * hillSpeedMul
        let capRev   = -capFwd * reverseSpeedFactor
        
        // Throttle → forward accel
        let accel    = acceleration * hillAccelMul
        let df       = accel * throttle * dt
        var newFwd   = CGFloat.clamp(fwd + df, capRev, capFwd)
        
        // Drag & lateral bleed
        let keepLat  = CGFloat(exp(-Double(tractionK * dt)))
        let newLat   = lat * keepLat
        
        // Extra hill drag
        let extraD   = max(0, 1 - hillDragK * dt * 0.002)
        newFwd      *= extraD
        
        v = CGVector(dx: f.dx * newFwd + r.dx * newLat,
                     dy: f.dy * newFwd + r.dy * newLat)
        pb.velocity = v
        
        // Lights + exhaust
        let speed = hypot(v.dx, v.dy)
        updateExhaust(speed: speed, fwdMag: newFwd, dt: dt)
        tailL.alpha = throttle < -0.2 ? 1.0 : 0.2
        
        // Keep the mini HUD aligned each frame
        miniHUD.zRotation = -zRotation
    }
}

extension CarNode {
    /// Applies projectile damage (shield soaks first).
    /// Keep it simple; the node already owns the HP/shield rules + death flow.
    @objc func receiveProjectile(damage: Int, at point: CGPoint) {
        applyDamage(damage, hitWorldPoint: point)
    }
}

