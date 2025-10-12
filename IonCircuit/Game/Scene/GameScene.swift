//
//  GameScene.swift
//  IonCircuit
//
//  Created by Barak Ben Hur on 12/10/2025.
//

import SpriteKit
import UIKit

final class GameScene: SKScene, SKPhysicsContactDelegate {
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
    private let speedLabel = SKLabelNode(fontNamed: "Menlo")
    private let unitLabel  = SKLabelNode(fontNamed: "Menlo")
    private let speedBar   = SKShapeNode()
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
    
    // ==== Fire button (bottom-right) ====
    private let fireButton = SKNode()
    private let fireBase = SKShapeNode()
    private let fireIcon = SKShapeNode()

    private var lastShotTime: TimeInterval = 0
    private let fireCooldown: TimeInterval = 0.18
    private let bulletSpeed: CGFloat = 2200
    private let bulletLife: TimeInterval = 1.0
    
    // Multi-touch: separate pointers for drive & fire
    private var driveTouch: UITouch?
    private var fireTouch: UITouch?

    // Auto-fire state
    private var firing = false
    private let fireActionKey = "autoFire"
    
    // Spawn / walls
    private let spawnClearance: CGFloat = 80
    private let blockedMask: UInt32 = Category.wall
    
    // MARK: - Scene lifecycle
    override func didMove(to view: SKView) {
        backgroundColor = .black
        physicsWorld.contactDelegate = self
        
        view.isMultipleTouchEnabled = true
        
        // World
        let world = OpenWorldNode(config:
                .init(size: CGSize(width: size.width * 100.0,
                                   height: size.height * 100.0)))
        addChild(world)
        openWorld = world
        
        // Car
        let searchRect = frame.insetBy(dx: 160, dy: 160)
        car.position = safeSpawnPoint(in: searchRect, radius: spawnClearance)
        car.zRotation = 0
        addChild(car)
        
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
        // Triangle pointing up (+Y)
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
        // own clock (independent of scene dt)
        let now = CACurrentMediaTime()
        let dt  = lastHUDSample == 0 ? 1.0/60.0 : max(1e-3, now - lastHUDSample)
        lastHUDSample = now
        
        // EMA smoothing
        let alpha = 1 - exp(-dt / Double(max(0.001, speedTau)))   // 0..1
        speedEMA += (kmh - speedEMA) * CGFloat(alpha)
        
        // clamp & show number
        let shown = max(0, speedEMA)
        speedLabel.text = String(format: "%3.0f", shown)
        
        // progress geometry (never invalid)
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
    
    private func updateHeadingHUD(desired angDesired: CGFloat, actual angActual: CGFloat) {
        // Rotate needles so 0 rad = North (+Y on screen) to match the dial labels.
        // atan2 gives 0 at +X → subtract π/2.
        let desiredRot = normalizeAngle(angDesired - .pi/2)
        let actualRot  = normalizeAngle(angActual  - .pi/2)

        // Color + brightness
        let color: UIColor = (activeBand >= 0 && activeBand < ringPalette.count)
            ? ringPalette[activeBand]
            : UIColor.systemTeal
        headingNeedleTarget.fillColor = color.withAlphaComponent(isTouching ? 0.95 : 0.75)
        headingNeedleActual.fillColor = UIColor.white.withAlphaComponent(0.85)

        // Apply rotations
        headingNeedleTarget.zRotation = desiredRot
        headingNeedleActual.zRotation = actualRot

        // Subtle breathing when touching
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
    
    // MARK: - Touches
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let cam = camera else { return }

        for t in touches {
            let pCam = t.location(in: cam)

            // --- Fire button (start auto-fire; do not block driving) ---
            if fireTouch == nil, pointInsideFireButton(pCam) {
                fireTouch = t
                startAutoFire()
                // small press animation
                fireButton.removeAction(forKey: "press")
                let down = SKAction.scale(to: 0.94, duration: 0.05)
                let up   = SKAction.scale(to: 1.00, duration: 0.08)
                fireButton.run(.sequence([down, up]), withKey: "press")
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

                    // anchor at center; seed angle = current heading (no jump)
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
    
    // MARK: - Shooting
    private func fireOnce() {
        let now = CACurrentMediaTime()
        if now - lastShotTime < fireCooldown { return }
        lastShotTime = now

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

        // Visual bullet
        let bullet = SKShapeNode(circleOfRadius: 3.5)
        bullet.fillColor = .white
        bullet.strokeColor = UIColor.white.withAlphaComponent(0.25)
        bullet.lineWidth = 0.8
        bullet.glowWidth = 2.0
        bullet.position = origin

        // Physics (no collisions needed)
        let pb = SKPhysicsBody(circleOfRadius: 3.5)
        pb.affectedByGravity = false
        pb.allowsRotation = false
        pb.linearDamping = 0
        pb.friction = 0
        pb.collisionBitMask = 0
        pb.contactTestBitMask = 0
        pb.velocity = vel
        bullet.physicsBody = pb

        addChild(bullet)
        bullet.run(.sequence([.wait(forDuration: bulletLife), .removeFromParent()]))

        // Button tap feedback
        fireButton.removeAction(forKey: "press")
        let down = SKAction.scale(to: 0.94, duration: 0.05)
        let up   = SKAction.scale(to: 1.00, duration: 0.08)
        fireButton.run(.sequence([down, up]), withKey: "press")
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
    
    private func startAutoFire() {
        guard !firing else { return }
        firing = true
        fireOnce() // immediate shot
        let seq = SKAction.sequence([
            .wait(forDuration: fireCooldown),
            .run { [weak self] in self?.fireOnce() }
        ])
        run(.repeatForever(seq), withKey: fireActionKey)
    }

    private func stopAutoFire() {
        firing = false
        removeAction(forKey: fireActionKey)
    }
    
    // MARK: - Update
    override func update(_ currentTime: TimeInterval) {
        // --- dt clamp ---
        let raw = (lastUpdate == 0) ? 0 : (currentTime - lastUpdate)
        lastUpdate = currentTime
        let dt = CGFloat(min(max(raw, 0), 0.05))
        guard dt > 0 else { return }
        
        // Keep camera centered on car
        camera?.position = car.position
        
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
            // radius → normalized target speed (0..1)
            let tNorm = (dClamped <= innerR + 1)
            ? 0
            : (dClamped - innerR) / max(outerR - innerR, 1)
            let targetNorm  = CGFloat.clamp(tNorm, 0, 1)
            let targetSpeed = targetNorm * car.maxSpeed
            
            // Steering: freeze while in deadzone; otherwise steer toward angleLP
            let heading  = car.zRotation + .pi/2
            let angleErr = shortestAngle(from: heading, to: angleLP)
            if lockAngleUntilExitDeadzone || dRaw <= innerR + 4 {
                car.steer = 0
            } else {
                let steerP = angleErr / (.pi/3)         // ±1 @ ~60°
                car.steer  = tanh(2.1 * steerP)
            }
            
            // --- SPEED CONTROLLER (no negative throttle = no low-speed chatter) ---
            let fwd = CGVector(dx: cos(heading), dy: sin(heading))
            let v   = pb.velocity
            let fwdMag = v.dx * fwd.dx + v.dy * fwd.dy
            
            let err = targetSpeed - max(0, fwdMag)
            let deadband: CGFloat = 25
            let accelGain: CGFloat = 280
            
            let hold = (0.06 + 0.34 * pow(targetNorm, 1.15)) // baseline feed-forward
            var throttleCmd: CGFloat = 0
            if err > deadband {
                throttleCmd = min(1, (err - deadband) / accelGain)
            } else {
                throttleCmd = 0
            }
            if fwdMag < targetSpeed * 0.92 { throttleCmd = max(throttleCmd, hold) }
            
            let align = max(0, cos(angleErr))
            if align < 0.25 { throttleCmd = min(throttleCmd, 0.12) }
            
            car.throttle = CGFloat.clamp(throttleCmd, 0, 1)
            
        } else if isCoasting {
            // Natural stop (coast)
            let speed = car.physicsBody?.velocity.length ?? 0
            if speed < 8 {
                car.throttle = 0
                car.steer = 0
                isCoasting = false
                hasAngleLP = false
                lockAngleUntilExitDeadzone = false
            } else {
                car.throttle = 0
                car.steer = 0.001
            }
        } else {
            car.throttle = 0
            car.steer = 0
            hasAngleLP = false
            lockAngleUntilExitDeadzone = false
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
