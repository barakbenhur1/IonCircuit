//
//  GameScene.swift
//  IonCircuit
//
//  Created by Barak Ben Hur on 12/10/2025.
//

import SpriteKit
import UIKit

final class GameScene: SKScene, SKPhysicsContactDelegate {
    // MARK: - STREAMED Obstacles =================================================
    
    // Deterministic RNG per chunk/cell (SplitMix64)
    private struct SplitMix64 {
        private(set) var state: UInt64
        init(seed: UInt64) { state = seed &+ 0x9E3779B97F4A7C15 }
        mutating func next() -> UInt64 {
            state &+= 0x9E3779B97F4A7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
            z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
            return z ^ (z >> 31)
        }
        mutating func unit() -> CGFloat { CGFloat(Double(next()) / Double(UInt64.max)) }
        mutating func range(_ r: ClosedRange<CGFloat>) -> CGFloat {
            r.lowerBound + (r.upperBound - r.lowerBound) * unit()
        }
        mutating func chance(_ p: CGFloat) -> Bool { unit() < p }
        mutating func int(_ r: ClosedRange<Int>) -> Int {
            let u = Double(next()) / Double(UInt64.max)
            let lo = r.lowerBound, hi = r.upperBound
            return lo + Int(floor(u * Double(hi - lo + 1)))
        }
    }
    
    // ==== World & Car ====
    private let car = CarNode()
    private var openWorld: OpenWorldNode?
    
    // ==== Time ====
    private var lastUpdate: TimeInterval = 0
    
    // ==== Input ====
    private var isTouching = false
    private var controlArmed = false           // first touch must start on the car
    private var fingerCam: CGPoint?            // finger in camera space
    
    // Angle smoothing (wrap-safe); we compute directly from finger every frame
    private var angleLP: CGFloat = 0
    private var hasAngleLP = false
    private var lockAngleUntilExitDeadzone = false
    
    // Natural stop (coast) after release
    private var isCoasting = false
    
    // ==== Speed Ring HUD (camera child → overlay) ====
    private let ringGroup = SKNode()
    private var ringBands: [SKShapeNode] = []
    private let ringHandle = SKShapeNode()
    private let activeHalo = SKShapeNode()
    
    // Ring sizes & visuals
    private let baseInnerR: CGFloat = 34
    private let baseOuterR: CGFloat = 124
    private let ringAlphaOnTouch: CGFloat = 0.16
    private let ringAlphaIdle: CGFloat = 0.0
    private let ringPalette: [UIColor] = [.white, .systemGreen, .systemYellow, .systemOrange, .systemRed]
    private var activeBand: Int = -1
    
    // ==== Speed HUD (km/h) ====
    private let speedHUD = SKNode()
    private let speedCard = SKShapeNode()
    private let speedLabel  = SKLabelNode(fontNamed: "Menlo")
    private let unitLabel   = SKLabelNode(fontNamed: "Menlo")
    private let speedBar    = SKShapeNode()
    private var speedEMA: CGFloat = 0
    private let speedTau: CGFloat = 0.15
    private var lastHUDSample: TimeInterval = 0
    private var kmhMaxShown: CGFloat = 0          // set in didMove
    private let pixelsPerMeter: CGFloat = 20.0
    private var kmhPerPointPerSecond: CGFloat { (1.0 / pixelsPerMeter) * 3.6 }
    
    // ==== Heading HUD (bottom-right, camera overlay) ====
    private let headingHUD = SKNode()
    private let headingDial = SKShapeNode()
    private let headingGlass = SKShapeNode()
    private let headingTicks = SKNode()
    private let headingNeedleTarget = SKShapeNode()
    private let headingNeedleActual = SKShapeNode()
    private let headingDot = SKShapeNode()
    private let headingN = SKLabelNode(text: "N")
    private let headingE = SKLabelNode(text: "E")
    private let headingS = SKLabelNode(text: "S")
    private let headingW = SKLabelNode(text: "W")
    private let headingPaletteIdle = UIColor.white.withAlphaComponent(0.75)
    private let headingPaletteActive = UIColor.white
    private let headingSize: CGFloat = 92   // diameter of dial
    
    // ==== Fire (button / bullets) ====
    private let fireButton = SKNode()
    private let fireBase = SKShapeNode()
    private let fireIcon = SKShapeNode()
    
    // Tap = singles; Hold = rapid
    private var lastManualShot: TimeInterval = 0
    private let singleTapCooldown: TimeInterval = 0.22   // tap spam limiter
    private let autoFireInterval: TimeInterval = 0.24    // hold rate (fast)
    private let autoFireArmDelay: TimeInterval = 0.18    // how long to hold before burst
    
    private var driveTouch: UITouch?
    private var fireTouch: UITouch?
    private var firing = false
    private let autoFireKey = "autoFireLoop"
    private let autoArmKey  = "autoFireArm"
    
    private let bulletSpeed: CGFloat = 2200
    private let bulletLife: TimeInterval = 1.0
    
    // World bounds used to cull bullets
    private var worldBounds: CGRect = .zero
    
    // ==== Obstacle placement (blue-noise grid + patterns) ====
    private let obstacleCell: CGFloat = 380          // was 280 → fewer anchors overall
    private let obstacleEdgeMargin: CGFloat = 160    // a bit more margin from walls
    private let obstacleKeepOutFromCar: CGFloat = 300
    private let obstacleClearanceMajor: CGFloat = 80 // wider clearance from walls/ramps/etc
    
    // NEW: hard minimum spacing between *any* placed obstacles (cross-chunk)
    private let minNeighborSpacing: CGFloat = 320
    
    // Cones slightly farther apart and fewer in a row
    private let coneSpacing: CGFloat = 32
    private let coneCountRange = 4...6
    
    // Rarer patterns
    private let rampChance: CGFloat = 0.08           // was 0.12
    private let coneRowChance: CGFloat = 0.16        // was 0.22
    
    // Spawn / walls
    private let spawnClearance: CGFloat = 80
    private let blockedMask: UInt32 = Category.wall
    
    // ==== Obstacle streaming (JIT spawn/despawn) ====
    private let chunkSize: CGFloat = 2048        // spatial streaming chunk size
    private let preloadMargin: CGFloat = 600     // spawn just outside the screen
    private var loadedChunks: [Int64: [SKNode]] = [:]
    private var lastStreamUpdateTime: TimeInterval = 0
    private let streamUpdateInterval: TimeInterval = 0.12
    private var worldSeed: UInt64 = 0            // deterministic layout across runs
    private let obstacleRoot = SKNode()          // parent for streamed obstacles
    
    // MARK: - Scene lifecycle
    override func didMove(to view: SKView) {
        backgroundColor = .black
        physicsWorld.contactDelegate = self
        
        view.isMultipleTouchEnabled = true
        
        // World
        let worldSize = CGSize(width: size.width * 100.0,
                               height: size.height * 100.0)
        let world = OpenWorldNode(config: .init(size: worldSize))
        addChild(world)
        openWorld = world
        
        // Centered world: (-W/2,-H/2) .. (+W/2,+H/2)
        worldBounds = CGRect(x: -worldSize.width * 0.5,
                             y: -worldSize.height * 0.5,
                             width: worldSize.width,
                             height: worldSize.height)
        
        // Car
        let searchRect = frame.insetBy(dx: 160, dy: 160)
        car.position = safeSpawnPoint(in: searchRect, radius: spawnClearance)
        car.zRotation = 0
        addChild(car)
        
        // --- STREAMED obstacles (NOT all at once) ---
        worldSeed = UInt64.random(in: 1...UInt64.max)
        obstacleRoot.zPosition = 1
        addChild(obstacleRoot)
        refreshObstacleStreaming(force: true)   // initial load
        
        // Camera (locks to car)
        let cam = SKCameraNode()
        camera = cam
        addChild(cam)
        cam.position = car.position
        
        // HUD ring (camera-space)
        ringGroup.zPosition = 200
        ringGroup.alpha = ringAlphaIdle
        ringGroup.isHidden = true
        ringGroup.position = .zero
        cam.addChild(ringGroup)
        buildSpeedRing()
        
        // Speed HUD (camera-space overlay)
        buildSpeedHUD()
        cam.addChild(speedHUD)
        
        // Heading HUD (camera-space overlay)
        buildHeadingHUD()
        cam.addChild(headingHUD)
        
        // Correct top-speed for speed bar (car.maxSpeed is pts/s)
        kmhMaxShown = car.maxSpeed * kmhPerPointPerSecond
        
        // Fire button
        buildFireButton()
        cam.addChild(fireButton)
        placeFireButton()
        
        placeHUD() // place both HUDs
    }
    
    override func didChangeSize(_ oldSize: CGSize) {
        super.didChangeSize(oldSize)
        placeHUD()
        placeFireButton()
    }
    
    // MARK: - Speed ring build
    private func buildSpeedRing() {
        ringGroup.removeAllChildren()
        ringBands.removeAll()
        
        // 5 translucent donut bands (stop = white → red)
        let bands = 5
        for i in 0..<bands {
            let t0 = CGFloat(i) / CGFloat(bands)
            let t1 = CGFloat(i + 1) / CGFloat(bands)
            let r0 = baseInnerR + (baseOuterR - baseInnerR) * t0
            let r1 = baseInnerR + (baseOuterR - baseInnerR) * t1
            
            let path = CGMutablePath()
            path.addArc(center: .zero, radius: r1, startAngle: 0, endAngle: .pi * 2, clockwise: false)
            path.addArc(center: .zero, radius: r0, startAngle: 0, endAngle: .pi * 2, clockwise: true)
            
            let band = SKShapeNode(path: path)
            let baseA: CGFloat = (i == 0) ? 0.10 : (0.10 + 0.015 * CGFloat(i))
            band.fillColor = ringPalette[i].withAlphaComponent(baseA)
            band.strokeColor = UIColor.white.withAlphaComponent(0.06)
            band.lineWidth = 0.75
            band.zPosition = 0
            ringGroup.addChild(band)
            ringBands.append(band)
        }
        
        // Active halo (glows at current band radius)
        let initialR: CGFloat = (baseInnerR + baseOuterR) * 0.5
        activeHalo.path = CGPath(ellipseIn: CGRect(x: -initialR, y: -initialR, width: initialR * 2, height: initialR * 2), transform: nil)
        activeHalo.strokeColor = UIColor.white.withAlphaComponent(0.0)
        activeHalo.lineWidth = 10
        activeHalo.glowWidth = 20
        activeHalo.fillColor = .clear
        activeHalo.zPosition = 0.6
        ringGroup.addChild(activeHalo)
        
        // Outer outline + soft glow
        let outline = SKShapeNode(circleOfRadius: baseOuterR)
        outline.strokeColor = UIColor.white.withAlphaComponent(0.12)
        outline.lineWidth = 2
        outline.glowWidth = 4
        outline.fillColor = .clear
        outline.zPosition = 0.1
        ringGroup.addChild(outline)
        
        // Handle (the draggable dot)
        ringHandle.path = CGPath(ellipseIn: CGRect(x: -7, y: -7, width: 14, height: 14), transform: nil)
        ringHandle.fillColor = UIColor.white.withAlphaComponent(0.95)
        ringHandle.strokeColor = UIColor.black.withAlphaComponent(0.30)
        ringHandle.lineWidth = 1.5
        ringHandle.position = .zero
        ringHandle.zPosition = 1
        ringGroup.addChild(ringHandle)
    }
    
    private func currentRadii() -> (inner: CGFloat, outer: CGFloat) {
        (baseInnerR * ringGroup.xScale, baseOuterR * ringGroup.xScale)
    }
    
    private func setActiveBand(index i: Int) {
        guard i != activeBand else { return }
        activeBand = i
        
        for (idx, band) in ringBands.enumerated() {
            if idx == i {
                band.lineWidth = 2.0
                band.strokeColor = UIColor.white.withAlphaComponent(0.22)
                band.fillColor = ringPalette[idx].withAlphaComponent(0.28)
                band.zPosition = 0.5
                
                let t0 = CGFloat(idx)   / 5.0
                let t1 = CGFloat(idx+1) / 5.0
                let r0 = baseInnerR + (baseOuterR - baseInnerR) * t0
                let r1 = baseInnerR + (baseOuterR - baseInnerR) * t1
                let mid = (r0 + r1) * 0.5
                let thick = max(6, (r1 - r0) * 0.8)
                
                activeHalo.path = CGPath(ellipseIn: CGRect(x: -mid, y: -mid, width: mid*2, height: mid*2), transform: nil)
                activeHalo.lineWidth = thick
                activeHalo.strokeColor = ringPalette[idx].withAlphaComponent(0.55)
                activeHalo.removeAllActions()
                let popIn = SKAction.fadeAlpha(to: 0.65, duration: 0.06)
                let settle = SKAction.fadeAlpha(to: 0.35, duration: 0.18)
                activeHalo.run(.sequence([popIn, settle]))
                
                ringHandle.fillColor = ringPalette[idx].withAlphaComponent(0.95)
            } else {
                let baseA: CGFloat = (idx == 0) ? 0.10 : (0.10 + 0.015 * CGFloat(idx))
                band.lineWidth = 0.75
                band.strokeColor = UIColor.white.withAlphaComponent(0.06)
                band.fillColor = ringPalette[idx].withAlphaComponent(baseA)
                band.zPosition = 0
            }
        }
    }
    
    // MARK: - Speed HUD (top-left overlay)
    private func buildSpeedHUD() {
        speedHUD.zPosition = 400
        
        let cardW: CGFloat = 150
        let cardH: CGFloat = 64
        let cardRect = CGRect(x: -cardW/2, y: -cardH/2, width: cardW, height: cardH)
        speedCard.path = CGPath(roundedRect: cardRect, cornerWidth: 14, cornerHeight: 14, transform: nil)
        speedCard.fillColor = UIColor(white: 0, alpha: 0.28)
        speedCard.strokeColor = UIColor(white: 1, alpha: 0.10)
        speedCard.lineWidth = 1.0
        speedCard.glowWidth = 2
        speedHUD.addChild(speedCard)
        
        // number
        speedLabel.fontSize = 34
        speedLabel.horizontalAlignmentMode = .center
        speedLabel.verticalAlignmentMode = .center
        speedLabel.position = CGPoint(x: 0, y: 10)
        speedLabel.fontColor = UIColor.white.withAlphaComponent(0.95)
        speedLabel.text = "0"
        speedHUD.addChild(speedLabel)
        
        // unit
        unitLabel.fontSize = 12
        unitLabel.horizontalAlignmentMode = .center
        unitLabel.verticalAlignmentMode = .center
        unitLabel.position = CGPoint(x: 0, y: -14)
        unitLabel.fontColor = UIColor.white.withAlphaComponent(0.75)
        unitLabel.text = "km/h"
        speedHUD.addChild(unitLabel)
        
        // progress bar background
        let barBase = SKShapeNode(rectOf: CGSize(width: cardW - 24, height: 6), cornerRadius: 3)
        barBase.fillColor = UIColor.white.withAlphaComponent(0.10)
        barBase.strokeColor = .clear
        barBase.position = CGPoint(x: 0, y: -24)
        speedHUD.addChild(barBase)
        
        // progress bar (PROPERTY, not local)
        speedBar.removeFromParent()
        speedBar.fillColor = UIColor.systemTeal.withAlphaComponent(0.85)
        speedBar.strokeColor = .clear
        speedBar.position = CGPoint(x: 0, y: -24)
        // tiny valid path to avoid rounded-rect assertion at width==0
        let eps: CGFloat = 0.001
        let p0 = CGMutablePath()
        p0.addRect(CGRect(x: -(cardW-24)/2, y: -3, width: eps, height: 6))
        speedBar.path = p0
        speedHUD.addChild(speedBar)
    }
    
    // MARK: - Heading HUD (bottom-right overlay)
    private func buildHeadingHUD() {
        headingHUD.zPosition = 400
        headingHUD.alpha = 0.82   // subtle when idle; we brighten on touch
        
        // Dial background (soft glass)
        let r = headingSize * 0.5
        headingDial.path = CGPath(ellipseIn: CGRect(x: -r, y: -r, width: headingSize, height: headingSize), transform: nil)
        headingDial.fillColor = UIColor(white: 0, alpha: 0.28)
        headingDial.strokeColor = UIColor(white: 1, alpha: 0.10)
        headingDial.lineWidth = 1.0
        headingDial.glowWidth = 2
        headingHUD.addChild(headingDial)
        
        // Inner glass ring for polish
        let g = SKShapeNode(circleOfRadius: r - 6)
        g.strokeColor = UIColor.white.withAlphaComponent(0.08)
        g.lineWidth = 2
        g.fillColor = .clear
        headingGlass.path = g.path
        headingHUD.addChild(headingGlass)
        
        // Ticks (12 ticks, bold on cardinals)
        headingTicks.removeAllChildren()
        for i in 0..<12 {
            let tick = SKShapeNode()
            let a = CGFloat(i) / 12.0 * .pi * 2
            let isCardinal = (i % 3 == 0)
            let len: CGFloat = isCardinal ? 10 : 6
            let w: CGFloat = isCardinal ? 2.2 : 1.2
            
            let p0 = CGPoint(x: cos(a) * (r - 12 - len), y: sin(a) * (r - 12 - len))
            let p1 = CGPoint(x: cos(a) * (r - 12),        y: sin(a) * (r - 12))
            
            let path = CGMutablePath()
            path.move(to: p0); path.addLine(to: p1)
            tick.path = path
            tick.strokeColor = UIColor.white.withAlphaComponent(isCardinal ? 0.55 : 0.28)
            tick.lineWidth = w
            tick.lineCap = .round
            headingTicks.addChild(tick)
        }
        headingHUD.addChild(headingTicks)
        
        // Cardinal letters
        func styleCardinal(_ l: SKLabelNode, _ text: String, _ a: CGFloat, _ dist: CGFloat) {
            l.fontName = "Menlo-Bold"
            l.fontSize = 12
            l.fontColor = UIColor.white.withAlphaComponent(0.85)
            l.verticalAlignmentMode = .center
            l.horizontalAlignmentMode = .center
            l.text = text
            l.position = CGPoint(x: cos(a) * dist, y: sin(a) * dist)
        }
        styleCardinal(headingN, "N", .pi/2, r - 18)
        styleCardinal(headingE, "E", 0,    r - 18)
        styleCardinal(headingS, "S", -.pi/2, r - 18)
        styleCardinal(headingW, "W", .pi,  r - 18)
        [headingN, headingE, headingS, headingW].forEach { headingHUD.addChild($0) }
        
        // Needles: target (fat triangle), actual (thin triangle)
        headingNeedleTarget.path = makeNeedlePath(length: r - 20, width: 12, tipRadius: 2)
        headingNeedleTarget.fillColor = UIColor.systemTeal.withAlphaComponent(0.95)
        headingNeedleTarget.strokeColor = UIColor.black.withAlphaComponent(0.25)
        headingNeedleTarget.lineWidth = 1.0
        headingNeedleTarget.zPosition = 1
        headingHUD.addChild(headingNeedleTarget)
        
        headingNeedleActual.path = makeNeedlePath(length: r - 26, width: 7, tipRadius: 1.5)
        headingNeedleActual.fillColor = UIColor.white.withAlphaComponent(0.85)
        headingNeedleActual.strokeColor = UIColor.black.withAlphaComponent(0.20)
        headingNeedleActual.lineWidth = 1.0
        headingNeedleActual.zPosition = 1
        headingHUD.addChild(headingNeedleActual)
        
        // Center dot
        let d: CGFloat = 6
        headingDot.path = CGPath(ellipseIn: CGRect(x: -d/2, y: -d/2, width: d, height: d), transform: nil)
        headingDot.fillColor = UIColor.white.withAlphaComponent(0.95)
        headingDot.strokeColor = UIColor.black.withAlphaComponent(0.3)
        headingDot.lineWidth = 1
        headingHUD.addChild(headingDot)
    }
    
    private func makeNeedlePath(length: CGFloat, width: CGFloat, tipRadius: CGFloat) -> CGPath {
        let half = width * 0.5
        let tip = CGPoint(x: 0, y: length)
        let left = CGPoint(x: -half, y: 0)
        let right = CGPoint(x: half, y: 0)
        let p = CGMutablePath()
        p.move(to: left)
        p.addLine(to: right)
        p.addLine(to: tip)
        p.closeSubpath()
        return p
    }
    
    // MARK: - HUD placement
    private func placeHUD() {
        // Camera-local coords: origin center; top-left (-w/2,+h/2), bottom-right (+w/2,-h/2)
        let margin: CGFloat = 16
        let drop: CGFloat   = 30   // speed card top-left, 30px lower
        
        let halfW = speedCard.frame.width  * 0.5
        let halfH = speedCard.frame.height * 0.5
        
        // Speed HUD — top-left, 30 px down
        speedHUD.position = CGPoint(
            x: -size.width  * 0.5 + margin + halfW,
            y:  size.height * 0.5 - (margin + drop) - halfH
        )
        
        // Heading HUD — top-right, aligned to the same top edge as the speed HUD
        let r = headingSize * 0.5
        headingHUD.position = CGPoint(
            x:  size.width  * 0.5 - margin - r,
            y:  size.height * 0.5 - (margin + drop) - r
        )
    }
    
    private func updateSpeedHUD(kmh: CGFloat) {
        let now = CACurrentMediaTime()
        let dt  = lastHUDSample == 0 ? 1.0/60.0 : max(1e-3, now - lastHUDSample)
        lastHUDSample = now
        
        let alpha = 1 - exp(-dt / Double(max(0.001, speedTau)))   // 0..1
        speedEMA += (kmh - speedEMA) * CGFloat(alpha)
        
        let shown = max(0, speedEMA)
        speedLabel.text = String(format: "%3.0f", shown)
        
        let maxW: CGFloat = max(1, speedCard.frame.width - 24)
        let frac = min(1, max(0, shown / max(kmhMaxShown, 1)))
        var w = maxW * frac
        
        let x0 = -maxW / 2
        let h: CGFloat = 6
        let path = CGMutablePath()
        if w <= 0.0001 {
            w = 0.0001
            path.addRect(CGRect(x: x0, y: -h/2, width: w, height: h))
        } else {
            let cw = min(3, w * 0.5)
            path.addRoundedRect(in: CGRect(x: x0, y: -h/2, width: w, height: h),
                                cornerWidth: cw, cornerHeight: cw)
        }
        speedBar.path = path
    }
    
    private func normalizeAngle(_ a: CGFloat) -> CGFloat {
        var x = a.truncatingRemainder(dividingBy: (.pi * 2))
        if x <= -.pi { x += .pi * 2 }
        if x >   .pi { x -= .pi * 2 }
        return x
    }
    
    private func shortestAngle(from: CGFloat, to: CGFloat) -> CGFloat {
        var d = (to - from).truncatingRemainder(dividingBy: .pi * 2)
        if d >= .pi { d -= .pi * 2 }
        if d <= -.pi { d += .pi * 2 }
        return d
    }
    
    private func updateHeadingHUD(desired angDesired: CGFloat, actual angActual: CGFloat) {
        let desiredRot = normalizeAngle(angDesired - .pi/2)
        let actualRot  = normalizeAngle(angActual  - .pi/2)
        
        let color: UIColor = (activeBand >= 0 && activeBand < ringPalette.count)
        ? ringPalette[activeBand]
        : UIColor.systemTeal
        headingNeedleTarget.fillColor = color.withAlphaComponent(isTouching ? 0.95 : 0.75)
        headingNeedleActual.fillColor = UIColor.white.withAlphaComponent(0.85)
        
        headingNeedleTarget.zRotation = desiredRot
        headingNeedleActual.zRotation = actualRot
        
        if isTouching && headingHUD.action(forKey: "pulse") == nil {
            let up = SKAction.fadeAlpha(to: 1.0, duration: 0.15)
            let down = SKAction.fadeAlpha(to: 0.82, duration: 0.35)
            headingHUD.run(.repeatForever(.sequence([up, down])), withKey: "pulse")
        } else if !isTouching {
            headingHUD.removeAction(forKey: "pulse")
            headingHUD.alpha = 0.82
        }
    }
    
    // MARK: - Touch helpers
    private func isTouchOnCarScene(_ pScene: CGPoint) -> Bool {
        for n in nodes(at: pScene) where (n === car || n.inParentHierarchy(car)) { return true }
        return car.position.distance(to: pScene) <= 26
    }
    
    // MARK: - SKPhysicsContactDelegate
    func didBegin(_ contact: SKPhysicsContact) {
        // Normalize order for convenience
        let bodyA = contact.bodyA
        let bodyB = contact.bodyB
        
        @inline(__always) func isBullet(_ b: SKPhysicsBody) -> Bool {
            (b.categoryBitMask & Category.bullet) != 0
        }
        @inline(__always) func isObstacle(_ b: SKPhysicsBody) -> Bool {
            (b.categoryBitMask & Category.obstacle) != 0
        }
        @inline(__always) func isWall(_ b: SKPhysicsBody) -> Bool {
            (b.categoryBitMask & Category.wall) != 0
        }
        @inline(__always) func killBullet(_ b: SKPhysicsBody) {
            b.node?.removeAllActions()
            b.node?.removeFromParent()
        }
        
        // ------ Bullet ↔ Obstacle ------
        if (isBullet(bodyA) && isObstacle(bodyB)) || (isBullet(bodyB) && isObstacle(bodyA)) {
            let bullet   = isBullet(bodyA) ? bodyA : bodyB
            let obstacle = isObstacle(bodyA) ? bodyA : bodyB
            
            if let ob = obstacle.node as? ObstacleNode {
                // Convert hit point to obstacle's local space for nicer FX placement
                let hitScene = contact.contactPoint
                let hitLocal = ob.convert(hitScene, from: self)
                ob.applyDamage(1, impact: hitLocal)   // handles steel (no HP loss + pulse) internally
            }
            // Remove the bullet on any obstacle hit
            killBullet(bullet)
            return
        }
        
        // ------ Bullet ↔ Wall ------
        if (isBullet(bodyA) && isWall(bodyB)) || (isBullet(bodyB) && isWall(bodyA)) {
            let bullet = isBullet(bodyA) ? bodyA : bodyB
            killBullet(bullet)
            return
        }
        
        // Add other contact pairs as needed...
    }
    
    // MARK: - Touches
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let cam = camera else { return }
        
        for t in touches {
            let pCam = t.location(in: cam)
            
            // --- Fire button (start auto-fire; do not block driving) ---
            if fireTouch == nil, pointInsideFireButton(pCam) {
                fireTouch = t
                startAutoFire()
                continue
            }
            
            // --- Driving (first drive touch must begin on the car) ---
            if driveTouch == nil {
                let pScene = t.location(in: self)
                if isTouchOnCarScene(pScene) {
                    driveTouch = t
                    isTouching = true
                    controlArmed = true
                    isCoasting = false
                    
                    fingerCam = .zero
                    hasAngleLP = true
                    angleLP = car.zRotation + .pi/2
                    lockAngleUntilExitDeadzone = true
                    
                    showRing()
                    ringHandle.position = .zero
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                }
            }
        }
    }
    
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let cam = camera else { return }
        
        if let dt = driveTouch, touches.contains(dt) {
            isTouching = true
            fingerCam = dt.location(in: cam)
            guard controlArmed, let f = fingerCam else { return }
            
            let v = CGVector(dx: f.x, dy: f.y)
            let dRaw = hypot(v.dx, v.dy)
            let (innerR, outerR) = currentRadii()
            let dClamp = CGFloat.clamp(dRaw, innerR, outerR)
            let angRaw = atan2(v.dy, v.dx)
            
            ringHandle.position = CGPoint(x: cos(angRaw) * dClamp, y: sin(angRaw) * dClamp)
            
            let tNorm = (dClamp - innerR) / max(outerR - innerR, 1)
            let idx = max(0, min(4, Int(floor(tNorm * 5))))
            setActiveBand(index: idx)
            
            if lockAngleUntilExitDeadzone, dRaw > innerR + 4 {
                lockAngleUntilExitDeadzone = false
            }
        }
    }
    
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        for t in touches {
            if let ft = fireTouch, t === ft {
                fireTouch = nil
                stopAutoFire()
            }
            if let dt = driveTouch, t === dt {
                driveTouch = nil
                isTouching = false
                controlArmed = false
                fingerCam = nil
                hideRing()
                isCoasting = true
            }
        }
    }
    
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        touchesEnded(touches, with: event)
    }
    
    // MARK: - Ring show/hide with polished animation
    private func showRing() {
        ringGroup.removeAllActions()
        ringGroup.isHidden = false
        ringGroup.alpha = 0
        ringGroup.setScale(0.86)
        
        let fadeIn = SKAction.fadeAlpha(to: ringAlphaOnTouch, duration: 0.18)
        fadeIn.timingMode = .easeOut
        let up = SKAction.scale(to: 1.08, duration: 0.16); up.timingMode = .easeOut
        let settle1 = SKAction.scale(to: 0.98, duration: 0.10); settle1.timingMode = .easeInEaseOut
        let settle2 = SKAction.scale(to: 1.00, duration: 0.08); settle2.timingMode = .easeOut
        ringGroup.run(.group([fadeIn, .sequence([up, settle1, settle2])]))
        
        ringHandle.removeAllActions()
        ringHandle.setScale(0.8)
        let hp1 = SKAction.scale(to: 1.15, duration: 0.10); hp1.timingMode = .easeOut
        let hp2 = SKAction.scale(to: 1.00, duration: 0.08); hp2.timingMode = .easeIn
        ringHandle.run(.sequence([hp1, hp2]))
    }
    
    private func hideRing() {
        ringGroup.removeAllActions()
        ringHandle.removeAllActions()
        ringHandle.setScale(1.0)
        ringGroup.run(.sequence([.fadeAlpha(to: ringAlphaIdle, duration: 0.10), .hide()]))
        setActiveBand(index: -1)
        activeHalo.removeAllActions()
        activeHalo.alpha = 0
    }
    
    // MARK: - Fire button build/placement
    private func buildFireButton() {
        fireButton.zPosition = 500
        
        // Base circle
        let R: CGFloat = 40
        fireBase.path = CGPath(ellipseIn: CGRect(x: -R, y: -R, width: R*2, height: R*2), transform: nil)
        fireBase.fillColor = UIColor(red: 0.95, green: 0.18, blue: 0.25, alpha: 0.90)
        fireBase.strokeColor = UIColor.white.withAlphaComponent(0.18)
        fireBase.lineWidth = 1.5
        fireBase.glowWidth = 2
        fireButton.addChild(fireBase)
        
        // Crosshair icon
        let p = CGMutablePath()
        p.addEllipse(in: CGRect(x: -10, y: -10, width: 20, height: 20))
        p.move(to: CGPoint(x: 0, y: 14));  p.addLine(to: CGPoint(x: 0, y: 22))
        p.move(to: CGPoint(x: 0, y: -14)); p.addLine(to: CGPoint(x: 0, y: -22))
        p.move(to: CGPoint(x: 14, y: 0));  p.addLine(to: CGPoint(x: 22, y: 0))
        p.move(to: CGPoint(x: -14, y: 0)); p.addLine(to: CGPoint(x: -22, y: 0))
        fireIcon.path = p
        fireIcon.strokeColor = .white
        fireIcon.lineWidth = 2.0
        fireIcon.lineCap = .round
        fireIcon.fillColor = .clear
        fireButton.addChild(fireIcon)
    }
    
    private func placeFireButton() {
        let margin: CGFloat = 20
        let R: CGFloat = 40
        fireButton.position = CGPoint(
            x:  size.width * 0.5 - margin - R,
            y: -size.height * 0.5 + margin + R
        )
    }
    
    private func pointInsideFireButton(_ pCam: CGPoint) -> Bool {
        let local = CGPoint(x: pCam.x - fireButton.position.x, y: pCam.y - fireButton.position.y)
        return hypot(local.x, local.y) <= 44
    }
    
    private func cullBulletsOutsideWorld() {
        guard worldBounds.width > 0 && worldBounds.height > 0 else { return }
        enumerateChildNodes(withName: "bullet") { node, _ in
            if !self.worldBounds.contains(node.position) {
                node.removeAllActions()
                node.removeFromParent()
            }
        }
    }
    
    private func animateFireTap() {
        fireButton.removeAction(forKey: "press")
        let down = SKAction.scale(to: 0.94, duration: 0.05)
        let up   = SKAction.scale(to: 1.00, duration: 0.08)
        fireButton.run(.sequence([down, up]), withKey: "press")
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
    
    @discardableResult
    private func spawnBullet() -> SKNode {
        // From car nose, along its forward (+Y in car space)
        let heading = car.zRotation + .pi/2
        let fwd = CGVector(dx: cos(heading), dy: sin(heading))
        let muzzleOffset: CGFloat = 26
        let origin = CGPoint(x: car.position.x + fwd.dx * muzzleOffset,
                             y: car.position.y + fwd.dy * muzzleOffset)
        
        // Bullet velocity = car velocity + projectile speed
        let carVel = car.physicsBody?.velocity ?? .zero
        let vel = CGVector(dx: carVel.dx + fwd.dx * bulletSpeed,
                           dy: carVel.dy + fwd.dy * bulletSpeed)
        
        let bullet = SKShapeNode(circleOfRadius: 3.5)
        bullet.name = "bullet"
        bullet.fillColor = .white
        bullet.strokeColor = UIColor.white.withAlphaComponent(0.25)
        bullet.lineWidth = 0.8
        bullet.glowWidth = 2.0
        bullet.position = origin
        
        let pb = SKPhysicsBody(circleOfRadius: 3.5)
        pb.isDynamic = true
        pb.affectedByGravity = false
        pb.allowsRotation = false
        pb.linearDamping = 0
        pb.friction = 0
        
        pb.categoryBitMask = Category.bullet
        pb.contactTestBitMask = Category.obstacle       // notify when touching obstacles
        pb.collisionBitMask = Category.obstacle         // <— allow collision so contact is guaranteed
        pb.usesPreciseCollisionDetection = true         // <— prevents tunneling at high speed
        
        pb.velocity = vel
        bullet.physicsBody = pb
        
        addChild(bullet)
        bullet.run(.sequence([.wait(forDuration: bulletLife), .removeFromParent()]))
        return bullet
    }
    
    private func fireOnceManual() {
        let now = CACurrentMediaTime()
        if now - lastManualShot < singleTapCooldown { return }
        lastManualShot = now
        _ = spawnBullet()
        animateFireTap()
    }
    
    private func startAutoFire() {
        guard !firing else { return }
        firing = true
        
        // Single shot immediately on press
        fireOnceManual()
        
        // Arm burst only if held beyond the delay
        removeAction(forKey: autoArmKey)
        let arm = SKAction.sequence([
            .wait(forDuration: autoFireArmDelay),
            .run { [weak self] in
                guard let self, self.firing else { return }
                // Rapid loop; not throttled by tap cooldown
                let loop = SKAction.sequence([
                    .wait(forDuration: self.autoFireInterval),
                    .run { [weak self] in _ = self?.spawnBullet() }
                ])
                self.run(.repeatForever(loop), withKey: self.autoFireKey)
            }
        ])
        run(arm, withKey: autoArmKey)
    }
    
    private func stopAutoFire() {
        firing = false
        removeAction(forKey: autoArmKey)
        removeAction(forKey: autoFireKey)
    }
    
    private func hash2(_ x: Int, _ y: Int, seed: UInt64) -> UInt64 {
        var h = seed &+ UInt64(bitPattern: Int64(x)) &* 0x9E3779B97F4A7C15
        h ^= UInt64(bitPattern: Int64(y)) &* 0xBF58476D1CE4E5B9
        h ^= (h >> 27)
        return h
    }
    
    private func cameraWorldRect(margin: CGFloat) -> CGRect {
        let camPos = camera?.position ?? .zero
        return CGRect(x: camPos.x - size.width/2  - margin,
                      y: camPos.y - size.height/2 - margin,
                      width:  size.width  + margin * 2,
                      height: size.height + margin * 2)
    }
    
    private func chunkRange(for rect: CGRect) -> (cx0: Int, cx1: Int, cy0: Int, cy1: Int) {
        func toCX(_ x: CGFloat) -> Int { Int(floor((x - worldBounds.minX) / chunkSize)) }
        func toCY(_ y: CGFloat) -> Int { Int(floor((y - worldBounds.minY) / chunkSize)) }
        let cx0 = toCX(rect.minX), cx1 = toCX(rect.maxX)
        let cy0 = toCY(rect.minY), cy1 = toCY(rect.maxY)
        return (min(cx0,cx1), max(cx0,cx1), min(cy0,cy1), max(cy0,cy1))
    }
    
    private func chunkRect(cx: Int, cy: Int) -> CGRect {
        CGRect(x: worldBounds.minX + CGFloat(cx) * chunkSize,
               y: worldBounds.minY + CGFloat(cy) * chunkSize,
               width: chunkSize, height: chunkSize)
    }
    
    private func chunkKey(cx: Int, cy: Int) -> Int64 {
        (Int64(cx) << 32) ^ Int64(cy & 0xFFFF_FFFF)
    }
    
    private func maybeUpdateObstacleStreaming(_ now: TimeInterval) {
        if now - lastStreamUpdateTime < streamUpdateInterval { return }
        lastStreamUpdateTime = now
        refreshObstacleStreaming(force: false)
    }
    
    private func refreshObstacleStreaming(force: Bool) {
        let target = cameraWorldRect(margin: preloadMargin)
        let r = chunkRange(for: target)
        
        var want: Set<Int64> = []
        for cy in r.cy0...r.cy1 {
            for cx in r.cx0...r.cx1 {
                let key = chunkKey(cx: cx, cy: cy)
                want.insert(key)
                if loadedChunks[key] == nil || force {
                    spawnChunk(cx: cx, cy: cy)
                }
            }
        }
        
        // Despawn far-away chunks
        if !force {
            for (key, nodes) in loadedChunks where !want.contains(key) {
                for n in nodes { n.removeAllActions(); n.removeFromParent() }
                loadedChunks.removeValue(forKey: key)
            }
        }
    }
    
    private func spawnChunk(cx: Int, cy: Int) {
        let key = chunkKey(cx: cx, cy: cy)
        guard loadedChunks[key] == nil else { return }
        let rect = chunkRect(cx: cx, cy: cy)
        
        var nodes: [SKNode] = []
        spawnObstacles(in: rect, nodesOut: &nodes, cx: cx, cy: cy)
        loadedChunks[key] = nodes
    }
    
    // Lower density, better spacing, deterministic per chunk
    // Lower density, better spacing, deterministic per chunk,
    // with steel (indestructible), barrier (replaces ramp),
    // and per-cone spacing checks.
    private func spawnObstacles(in rect: CGRect, nodesOut: inout [SKNode], cx: Int, cy: Int) {
        // Tunables local to this function (safe defaults)
        let barrierChance: CGFloat = 0.10         // rarity of barrier patterns
        let coneRowChanceLocal: CGFloat = 0.16    // rarity of cone rows
        let steelChanceSingle: CGFloat = 0.15     // chance for steel in single-scatter
        
        // Anchor sampling parameters
        let pad: CGFloat = max(28, obstacleCell * 0.08)   // keep anchors off cell edges
        let cols = Int(ceil(rect.width / obstacleCell))
        let rows = Int(ceil(rect.height / obstacleCell))
        
        let worldCenter = CGPoint(x: worldBounds.midX, y: worldBounds.midY)
        
        for j in 0..<rows {
            for i in 0..<cols {
                // Deterministic RNG for this anchor
                var rng = SplitMix64(seed: hash2(cx*10_000 + i, cy*10_000 + j, seed: worldSeed))
                
                // Cell rect and jittered anchor
                let cellRect = CGRect(
                    x: rect.minX + CGFloat(i) * obstacleCell,
                    y: rect.minY + CGFloat(j) * obstacleCell,
                    width: obstacleCell, height: obstacleCell
                )
                let jitterX = rng.range(pad...(obstacleCell - pad))
                let jitterY = rng.range(pad...(obstacleCell - pad))
                let a = CGPoint(x: cellRect.minX + jitterX, y: cellRect.minY + jitterY)
                
                // Bounds & spawn keep-outs
                if !worldBounds.insetBy(dx: obstacleEdgeMargin, dy: obstacleEdgeMargin).contains(a) { continue }
                if a.distance(to: car.position) < obstacleKeepOutFromCar { continue }
                
                // Density shaping: fewer near center, more at outskirts (overall reduced)
                let toCenter = hypot(a.x - worldCenter.x, a.y - worldCenter.y)
                let maxR = 0.5 * hypot(worldBounds.width, worldBounds.height)
                let falloff = CGFloat.clamp(toCenter / max(1, maxR), 0, 1)   // 0 center .. 1 edge
                let placeP: CGFloat = 0.14 + 0.28 * falloff                  // reduced from earlier
                if !rng.chance(placeP) { continue }
                
                // Global Poisson-like spacing (cross-chunk)
                if hasNeighborObstacle(near: a, radius: minNeighborSpacing) { continue }
                
                // Clearance from existing walls/obstacles/holes/car
                let avoidMask: UInt32 = Category.wall | Category.obstacle | Category.hole | Category.car
                if !clearanceOK(at: a, radius: obstacleClearanceMajor, mask: avoidMask) { continue }
                
                // Decide & place a pattern
                var placedSomething = false
                var placedNodes: [SKNode] = []
                
                // --- BARRIER (rare), oriented away from center ---
                if rng.chance(barrierChance) {
                    let dir = CGVector(dx: a.x - worldCenter.x, dy: a.y - worldCenter.y)
                    let rot = atan2(dir.dy, dir.dx)
                    
                    if !hasNeighborObstacle(near: a, radius: minNeighborSpacing),
                       let barrier = placeObstacleTracked(.barrier, at: a, rotation: rot) {
                        placedSomething = true
                        placedNodes.append(barrier)
                        
                        // Optional cones guarding the barrier entry (also spaced-checked)
                        let back = CGPoint(x: a.x - cos(rot) * 56, y: a.y - sin(rot) * 56)
                        let left = CGPoint(x: back.x - sin(rot) * 16, y: back.y + cos(rot) * 16)
                        let right = CGPoint(x: back.x + sin(rot) * 16, y: back.y - cos(rot) * 16)
                        
                        if !hasNeighborObstacle(near: left, radius: minNeighborSpacing),
                           let l = placeObstacleTracked(.cone, at: left, rotation: rot) { placedNodes.append(l) }
                        if !hasNeighborObstacle(near: right, radius: minNeighborSpacing),
                           let r = placeObstacleTracked(.cone, at: right, rotation: rot) { placedNodes.append(r) }
                    }
                }
                
                // --- CONE ROW (lane marking) with per-cone spacing enforcement ---
                if !placedSomething, rng.chance(coneRowChanceLocal) {
                    let baseRot: CGFloat = (rng.chance(0.5) ? 0 : .pi/2)
                    let rot = baseRot + (.pi/12) * (rng.range(-1...1))
                    let count = rng.int(coneCountRange)
                    
                    var ok = true
                    var rowNodes: [SKNode] = []
                    for idx in 0..<count {
                        let t = CGFloat(idx) - CGFloat(count - 1) * 0.5
                        let p = CGPoint(
                            x: a.x + cos(rot) * coneSpacing * t,
                            y: a.y + sin(rot) * coneSpacing * t
                        )
                        
                        // Prevent bunching inside row and against neighbors
                        if hasNeighborObstacle(near: p, radius: minNeighborSpacing) { ok = false; break }
                        
                        if let n = placeObstacleTracked(.cone, at: p, rotation: rot) {
                            rowNodes.append(n)
                        } else {
                            ok = false; break
                        }
                    }
                    
                    if ok {
                        placedSomething = true
                        placedNodes.append(contentsOf: rowNodes)
                    } else {
                        // rollback partial row
                        rowNodes.forEach { $0.removeFromParent() }
                    }
                }
                
                // --- SINGLE SCATTER (rock / barrel / steel) ---
                if !placedSomething {
                    // 15% steel (indestructible), otherwise rock vs barrel
                    let u = rng.unit()
                    let kind: ObstacleKind
                    if u < steelChanceSingle { kind = .steel }
                    else if u < 0.60 { kind = .rock }
                    else { kind = .barrel }
                    
                    let rot = rng.range(-(.pi/8)...(.pi/8))
                    if !hasNeighborObstacle(near: a, radius: minNeighborSpacing),
                       let n = placeObstacleTracked(kind, at: a, rotation: rot) {
                        placedSomething = true
                        placedNodes.append(n)
                    }
                }
                
                if placedSomething {
                    nodesOut.append(contentsOf: placedNodes)
                }
            }
        }
    }
    
    // MARK: - Existing placement utilities (tweaked to support tracking)
    
    private func clearanceOK(at p: CGPoint, radius: CGFloat, mask: UInt32) -> Bool {
        var blocked = false
        let r = CGRect(x: p.x - radius, y: p.y - radius, width: radius*2, height: radius*2)
        physicsWorld.enumerateBodies(in: r) { body, stop in
            if (body.categoryBitMask & mask) != 0 {
                blocked = true; stop.pointee = true
            }
        }
        return !blocked
    }
    
    /// Tracked variant returns the created node (so we can despawn per chunk).
    @discardableResult
    private func placeObstacleTracked(_ kind: ObstacleKind, at p: CGPoint, rotation: CGFloat = 0) -> SKNode? {
        // Don’t place outside world or too close to edges
        if !worldBounds.insetBy(dx: obstacleEdgeMargin, dy: obstacleEdgeMargin).contains(p) { return nil }
        
        // Clearance from existing walls/obstacles/holes/ramps/car
        let avoidMask: UInt32 = Category.wall | Category.obstacle | Category.hole | Category.ramp | Category.car
        if !clearanceOK(at: p, radius: obstacleClearanceMajor, mask: avoidMask) { return nil }
        
        let node = ObstacleFactory.make(kind)
        node.position = p
        node.zRotation = rotation
        node.zPosition = 1
        obstacleRoot.addChild(node)   // important: parent under obstacleRoot
        return node
    }
    
    /// Backward-compatible wrapper (if you use it elsewhere)
    @discardableResult
    private func placeObstacle(_ kind: ObstacleKind, at p: CGPoint, rotation: CGFloat = 0) -> Bool {
        return placeObstacleTracked(kind, at: p, rotation: rotation) != nil
    }
    
    // Are there already obstacles too close? (uses physics bodies so it's fast enough per spawn)
    private func hasNeighborObstacle(near p: CGPoint, radius: CGFloat) -> Bool {
        var found = false
        let r = CGRect(x: p.x - radius, y: p.y - radius, width: radius*2, height: radius*2)
        let mask: UInt32 = Category.obstacle | Category.ramp | Category.hole
        physicsWorld.enumerateBodies(in: r) { body, stop in
            if (body.categoryBitMask & mask) != 0,
               let n = body.node {
                // If your ObstacleFactory parents under obstacleRoot (recommended), this avoids false positives.
                // If not, you can drop the parent check.
                if let _ = n.parent, n.position.distance(to: p) < radius {
                    found = true; stop.pointee = true
                }
            }
        }
        return found
    }
    
    // MARK: - Destruction FX
    func spawnDestructionFX(at p: CGPoint, for kind: ObstacleKind) {
        // ---- palette per obstacle type ----
        let debrisColors: [UIColor]
        switch kind {
        case .cone:    debrisColors = [UIColor.orange, UIColor(red: 1, green: 0.65, blue: 0.2, alpha: 1), .white]
        case .barrel:  debrisColors = [UIColor.brown, UIColor(red: 0.35, green: 0.18, blue: 0.08, alpha: 1), .white]
        case .rock:    debrisColors = [UIColor(white: 0.85, alpha: 1), UIColor(white: 0.55, alpha: 1), UIColor(white: 0.35, alpha: 1)]
        case .barrier: debrisColors = [UIColor(white: 0.85, alpha: 1), UIColor(white: 0.7, alpha: 1), UIColor(white: 0.4, alpha: 1)]
        case .steel:   debrisColors = [UIColor(white: 0.9, alpha: 1), UIColor(white: 0.6, alpha: 1)] // shouldn't blow up, but safe
        }
        
        // ---- 1) shockwave ring ----
        let ringR: CGFloat = 6
        let ring = SKShapeNode(circleOfRadius: ringR)
        ring.position = p
        ring.strokeColor = UIColor.white.withAlphaComponent(0.8)
        ring.lineWidth = 3
        ring.fillColor = .clear
        ring.zPosition = 50
        addChild(ring)
        let ringAnim = SKAction.group([
            .scale(to: 8.0, duration: 0.35),
            .fadeOut(withDuration: 0.35)
        ])
        ring.run(.sequence([ringAnim, .removeFromParent()]))
        
        // ---- 2) spark burst (fast, bright) ----
        let spark = SKEmitterNode()
        spark.particleTexture = makeRoundTex(px: 10)
        spark.particleBirthRate = 0
        spark.numParticlesToEmit = 120
        spark.particleLifetime = 0.45
        spark.particleLifetimeRange = 0.15
        spark.particleSpeed = 460
        spark.particleSpeedRange = 240
        spark.emissionAngleRange = .pi * 2
        spark.particleAlpha = 0.95
        spark.particleAlphaSpeed = -2.4
        spark.particleScale = 0.28
        spark.particleScaleRange = 0.18
        spark.particleBlendMode = .add
        spark.particleColorSequence = SKKeyframeSequence(
            keyframeValues: [debrisColors.first ?? .white,
                             (debrisColors.dropFirst().first ?? .white).withAlphaComponent(0.9),
                             UIColor.white.withAlphaComponent(0.0)],
            times: [0.0, 0.55, 1.0]
        )
        spark.position = p
        spark.zPosition = 49
        addChild(spark)
        // one-shot burst
        spark.particleBirthRate = 4000
        spark.run(.sequence([
            .wait(forDuration: 0.05),
            .run { spark.particleBirthRate = 0 },
            .wait(forDuration: 0.7),
            .removeFromParent()
        ]))
        
        // ---- 3) dust/smoke puff (soft, lingers) ----
        let smoke = SKEmitterNode()
        smoke.particleTexture = makeRoundTex(px: 20)
        smoke.numParticlesToEmit = 28
        smoke.particleLifetime = 0.9
        smoke.particleLifetimeRange = 0.2
        smoke.particleSpeed = 90
        smoke.particleSpeedRange = 60
        smoke.emissionAngleRange = .pi * 2
        smoke.particleAlpha = 0.35
        smoke.particleAlphaSpeed = -0.35
        smoke.particleScale = 0.55
        smoke.particleScaleSpeed = 0.45
        smoke.particleColor = UIColor(white: 0.6, alpha: 1)
        smoke.particleBlendMode = .alpha
        smoke.position = p
        smoke.zPosition = 48
        addChild(smoke)
        smoke.run(.sequence([.wait(forDuration: 1.2), .removeFromParent()]))
        
        // ---- 4) a few chunky debris sprites that arc out ----
        for _ in 0..<8 {
            let s = SKSpriteNode(texture: makeRectTex(size: CGSize(width: .random(in: 3...6),
                                                                   height: .random(in: 6...12))))
            s.colorBlendFactor = 1
            s.color = debrisColors.randomElement() ?? .white
            s.position = p
            s.zPosition = 51
            addChild(s)
            
            let angle = CGFloat.random(in: 0 ..< .pi * 2)
            let speed = CGFloat.random(in: 220...420)
            let dx = cos(angle) * speed
            let dy = sin(angle) * speed
            
            let move = SKAction.moveBy(x: dx * 0.25, y: dy * 0.25, duration: 0.25)
            move.timingMode = .easeOut
            let drift = SKAction.moveBy(x: dx * 0.15, y: dy * 0.15, duration: 0.35)
            drift.timingMode = .easeIn
            let spin = SKAction.rotate(byAngle: CGFloat.random(in: -2...2), duration: 0.6)
            let fade = SKAction.fadeOut(withDuration: 0.6)
            s.run(.sequence([.group([.sequence([move, drift]), spin, fade]), .removeFromParent()]))
        }
        
        // ---- 5) small camera shake ----
        shakeCamera(intensity: 6, duration: 0.20)
    }
    
    // Tiny radial dot texture (for sparks/smoke)
    private func makeRoundTex(px: CGFloat) -> SKTexture {
        let size = CGSize(width: px, height: px)
        let img = UIGraphicsImageRenderer(size: size).image { ctx in
            let cg = ctx.cgContext
            let colors = [UIColor.white.cgColor,
                          UIColor(white: 1, alpha: 0).cgColor] as CFArray
            let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                  colors: colors, locations: [0, 1])!
            cg.drawRadialGradient(
                grad,
                startCenter: CGPoint(x: px/2, y: px/2), startRadius: 0,
                endCenter: CGPoint(x: px/2, y: px/2), endRadius: px/2,
                options: .drawsBeforeStartLocation
            )
        }
        let t = SKTexture(image: img)
        t.filteringMode = .linear
        return t
    }
    
    // Small rectangle texture (for chunky debris)
    private func makeRectTex(size: CGSize) -> SKTexture {
        let img = UIGraphicsImageRenderer(size: size).image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
        }
        let t = SKTexture(image: img)
        t.filteringMode = .nearest
        return t
    }
    
    // Lightweight camera shake
    private func shakeCamera(intensity: CGFloat, duration: TimeInterval) {
        guard let cam = camera else { return }
        cam.removeAction(forKey: "shake")
        let frames = max(2, Int(ceil(duration / 0.02)))
        var seq: [SKAction] = []
        for _ in 0..<frames {
            let dx = CGFloat.random(in: -intensity...intensity)
            let dy = CGFloat.random(in: -intensity...intensity)
            seq.append(.moveBy(x: dx, y: dy, duration: 0.02))
        }
        seq.append(.moveTo(x: car.position.x, duration: 0.02))
        seq.append(.moveTo(y: car.position.y, duration: 0.00))
        cam.run(.sequence(seq), withKey: "shake")
    }
    
    
    // MARK: - Update
    override func update(_ currentTime: TimeInterval) {
        // --- dt clamp ---
        let raw = (lastUpdate == 0) ? 0 : (currentTime - lastUpdate)
        lastUpdate = currentTime
        let dt = CGFloat(min(max(raw, 0), 0.05))
        guard dt > 0 else {
            // keep camera glued even on first frame
            camera?.position = car.position
            return
        }
        
        // Keep camera centered on car
        camera?.position = car.position
        
        // Stream obstacles near the camera view
        maybeUpdateObstacleStreaming(currentTime)
        
        // ---------- finger → heading/throttle ----------
        if isTouching, controlArmed, let f = fingerCam, let pb = car.physicsBody {
            isCoasting = false
            
            // Finger vector (camera space)
            let vFinger = CGVector(dx: f.x, dy: f.y)
            let dRaw    = hypot(vFinger.dx, vFinger.dy)
            let (innerR, outerR) = currentRadii()
            let dClamped = CGFloat.clamp(dRaw, innerR, outerR)
            let angRaw   = atan2(vFinger.dy, vFinger.dx)
            
            // Smooth angle ONLY after finger exits the inner ring (tap shouldn’t change dir)
            let tau: CGFloat = 0.06
            let alpha = CGFloat(1.0 - exp(-Double(dt / tau)))
            if !lockAngleUntilExitDeadzone, dRaw > innerR + 4 {
                if hasAngleLP {
                    angleLP += alpha * shortestAngle(from: angleLP, to: angRaw)
                } else {
                    angleLP = angRaw
                    hasAngleLP = true
                }
            }
            
            // Steering: freeze while in deadzone; otherwise steer toward angleLP
            let heading  = car.zRotation + .pi/2
            let angleErr = shortestAngle(from: heading, to: angleLP)
            if lockAngleUntilExitDeadzone || dRaw <= innerR + 4 {
                // Tiny epsilon steer so CarNode doesn’t trigger the “parking brake”
                car.steer = 0.001
            } else {
                let steerP = angleErr / (.pi/3)         // ±1 @ ~60°
                car.steer  = tanh(2.1 * steerP)
            }
            
            // ---- THROTTLE & BOOST ----
            let fwd = CGVector(dx: cos(heading), dy: sin(heading))
            let v   = pb.velocity
            let fwdMag = v.dx * fwd.dx + v.dy * fwd.dy
            
            // Base mapping (edge of ring = maxSpeed)
            let tNormBase = (dClamped <= innerR + 1)
            ? 0
            : (dClamped - innerR) / max(outerR - innerR, 1)
            let tNorm = CGFloat.clamp(tNormBase, 0, 1)
            let baseTarget = tNorm * car.maxSpeed
            
            // Outside-ring boost → max + 280 (with a small epsilon)
            let overshootEps: CGFloat = 6
            let outside = dRaw > outerR + overshootEps
            let targetSpeed: CGFloat
            if outside {
                targetSpeed = car.maxSpeed + 280
                car.speedCapBonus = 280              // lift forward speed cap while outside
            } else {
                targetSpeed = baseTarget
                car.speedCapBonus = 0                // normal cap when inside
            }
            
            if lockAngleUntilExitDeadzone || dRaw <= innerR + 4 {
                // Inside inner ring: coast (no thrust)
                car.throttle = 0
            } else {
                // Normal speed controller toward targetSpeed
                let err = targetSpeed - max(0, fwdMag)
                let deadband: CGFloat = 25
                let accelGain: CGFloat = 280
                
                let hold = (0.06 + 0.34 * pow(tNorm, 1.15)) // baseline feed-forward
                var throttleCmd: CGFloat = 0
                if err > deadband {
                    throttleCmd = min(1, (err - deadband) / accelGain)
                } else {
                    throttleCmd = 0
                }
                if fwdMag < targetSpeed * 0.92 { throttleCmd = max(throttleCmd, hold) }
                
                // Reduce throttle when pointed far from the target heading
                let align = max(0, cos(angleErr))
                if align < 0.25 { throttleCmd = min(throttleCmd, 0.12) }
                
                car.throttle = CGFloat.clamp(throttleCmd, 0, 1)
            }
            
        } else if isCoasting {
            // Natural stop (coast) — no instant brake when finger leaves the ring
            let speed = car.physicsBody?.velocity.length ?? 0
            if speed < 8 {
                car.throttle = 0
                car.steer = 0
                isCoasting = false
                hasAngleLP = false
                lockAngleUntilExitDeadzone = false
            } else {
                car.throttle = 0
                car.steer = 0.001 // keep brake clamp off while coasting
            }
            car.speedCapBonus = 0     // ensure boost is cleared while coasting
        } else {
            car.throttle = 0
            car.steer = 0
            hasAngleLP = false
            lockAngleUntilExitDeadzone = false
            car.speedCapBonus = 0     // ensure boost is cleared when idle
        }
        
        car.update(dt)
        
        // ---- Speed HUD (km/h) ----
        let ptsPerSec = car.physicsBody?.velocity.length ?? 0
        let kmh = ptsPerSec * kmhPerPointPerSecond
        updateSpeedHUD(kmh: kmh)
        
        // ---- Heading HUD ----
        let actualHeading = car.zRotation + .pi/2
        let desiredHeading = (hasAngleLP ? angleLP : actualHeading)
        updateHeadingHUD(desired: desiredHeading, actual: actualHeading)
        
        // Cull bullets that left the world
        cullBulletsOutsideWorld()
    }
    
    // MARK: - Spawn helpers
    private func safeSpawnPoint(in rect: CGRect, radius: CGFloat, attempts: Int = 128) -> CGPoint {
        var inner = rect.insetBy(dx: radius, dy: radius)
        if inner.width <= 1 || inner.height <= 1 { inner = rect }
        
        let minX = Swift.min(inner.minX, inner.maxX)
        let maxX = Swift.max(inner.minX, inner.maxX)
        let minY = Swift.min(inner.minY, inner.maxY)
        let maxY = Swift.max(inner.minY, inner.maxY)
        
        for _ in 0..<attempts {
            let p = CGPoint(x: .random(in: minX...maxX), y: .random(in: minY...maxY))
            if !isBlocked(at: p, radius: radius) { return p }
        }
        return CGPoint(x: rect.midX, y: rect.midY)
    }
    
    private func isBlocked(at p: CGPoint, radius: CGFloat) -> Bool {
        var blocked = false
        let r = CGRect(x: p.x - radius, y: p.y - radius, width: radius*2, height: radius*2)
        physicsWorld.enumerateBodies(in: r) { [weak self] body, stop in
            guard let self else { return }
            if (body.categoryBitMask & blockedMask) != 0 {
                blocked = true; stop.pointee = true
            }
        }
        return blocked
    }
}
