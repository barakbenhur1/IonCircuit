//
//  GameScene.swift
//  IonCircuit
//
//  Created by Barak Ben Hur on 12/10/2025.
//

import SpriteKit
import UIKit

final class GameScene: SKScene, SKPhysicsContactDelegate {
    // MARK: - STREAMED Obstacles / Terrain =====================================
    
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
        mutating func range(_ r: ClosedRange<CGFloat>) -> CGFloat { r.lowerBound + (r.upperBound - r.lowerBound) * unit() }
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
    private var controlArmed = false
    private var fingerCam: CGPoint?
    
    private var angleLP: CGFloat = 0
    private var hasAngleLP = false
    private var lockAngleUntilExitDeadzone = false
    private var isCoasting = false
    
    // ==== Speed Ring HUD ====
    private let ringGroup = SKNode()
    private var ringBands: [SKShapeNode] = []
    private let ringHandle = SKShapeNode()
    private let activeHalo = SKShapeNode()
    
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
    private var kmhMaxShown: CGFloat = 0
    private let pixelsPerMeter: CGFloat = 20.0
    private var kmhPerPointPerSecond: CGFloat { (1.0 / pixelsPerMeter) * 3.6 }
    
    // ==== Heading HUD ====
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
    private let headingSize: CGFloat = 92
    
    // ==== Ramp Pointer HUD ====
    private let rampPointer = SKNode()
    private let rampArrow   = SKShapeNode()       // acts as a container for inner parts
    private let rampArrowBase = SKShapeNode()
    private let rampArrowHead = SKShapeNode()
    private let rampArrowPulse = SKShapeNode()
    private let rampPointerMaxDistance: CGFloat = 1600
    private let rampPointerMargin: CGFloat = 28
    private var rampPointerBuilt = false
    
    // ==== Fire (button / bullets) ====
    private let fireButton = SKNode()
    private let fireBase = SKShapeNode()
    private let fireIcon = SKShapeNode()
    
    private var driveTouch: UITouch?
    private var fireTouch: UITouch?
    
    // World bounds
    private var worldBounds: CGRect = .zero
    
    // ==== Obstacle placement ====
    private let obstacleCell: CGFloat = 380
    private let obstacleEdgeMargin: CGFloat = 160
    private let obstacleKeepOutFromCar: CGFloat = 300
    private let obstacleClearanceMajor: CGFloat = 80
    private let minNeighborSpacing: CGFloat = 320
    private let coneSpacing: CGFloat = 32
    private let coneCountRange = 4...6
    private let spawnClearance: CGFloat = 80
    private let blockedMask: UInt32 = Category.wall
    
    // ==== Streaming ====
    private let chunkSize: CGFloat = 2048
    private let preloadMargin: CGFloat = 600
    private var loadedChunks: [Int64: [SKNode]] = [:]
    private var lastStreamUpdateTime: TimeInterval = 0
    private let streamUpdateInterval: TimeInterval = 0.12
    private var worldSeed: UInt64 = 0
    private let obstacleRoot = SKNode()
    
    private var _preCarVel: CGVector = .zero
    private var _hadSolidContactThisStep = false
    private var _lastDTForClamp: CGFloat = 1/60
    private let _contactForwardBoostClampPerSec: CGFloat = 1400   // clamp contact-induced forward “kicks”
    
    // ==== Hills ====
    private var hills: [HillNode] = []
    
    // UI / HUD
    private let healthHUD = CarHealthHUDNode()
    
    // ==== Controls / Handedness ====
    private var isLeftHanded = true
    private var controlsLockedForOverlay = false
    private var handednessOverlay: HandChoiceOverlayNode?
    
    // ==== Death freeze / pause ====
    private var cameraFrozenPos: CGPoint?         // freeze camera here while dead
    private var pausedForDeath = false            // NEW
    
    private let strictCentering = true
    
    private func pauseWorldForDeath() {           // NEW
        guard !pausedForDeath else { return }
        pausedForDeath = true
        
        // stop inputs
        driveTouch = nil
        fireTouch = nil
        isTouching = false
        controlArmed = false
        car.stopAutoFire()
        hideRing()
        
        // freeze simulation
        physicsWorld.speed = 0
        
        // pause node trees that animate
        openWorld?.isPaused = true
        obstacleRoot.isPaused = true
        
        // IMPORTANT FIX: do NOT pause the car or its actions won't run (respawn never triggers)
        // car.isPaused = true   // ← removed
        
        // optional: quiet HUD motion
        speedHUD.isPaused = true
        headingHUD.isPaused = true
        rampPointer.isPaused = true
    }
    
    private func resumeWorldAfterRespawn() {      // NEW
        guard pausedForDeath else { return }
        pausedForDeath = false
        
        physicsWorld.speed = 1
        openWorld?.isPaused = false
        obstacleRoot.isPaused = false
        car.isPaused = false
        
        speedHUD.isPaused = false
        headingHUD.isPaused = false
        rampPointer.isPaused = false
    }
    
    // MARK: - Scene lifecycle
    override func didMove(to view: SKView) {
        backgroundColor = .black
        physicsWorld.contactDelegate = self
        view.isMultipleTouchEnabled = true
        
        // World
        let worldSize = CGSize(width: size.width * 100.0, height: size.height * 100.0)
        let world = OpenWorldNode(config: .init(size: worldSize))
        addChild(world)
        openWorld = world
        
        worldBounds = CGRect(x: -worldSize.width * 0.5,
                             y: -worldSize.height * 0.5,
                             width: worldSize.width,
                             height: worldSize.height)
        
        // Car
        let searchRect = frame.insetBy(dx: 160, dy: 160)
        car.position = safeSpawnPoint(in: searchRect, radius: spawnClearance)
        car.zRotation = 0
        addChild(car)
        car.enableAirPhysics()
        car.delegate = self
        
        // Streaming root
        worldSeed = UInt64.random(in: 1...UInt64.max)
        obstacleRoot.zPosition = 1
        addChild(obstacleRoot)
        refreshObstacleStreaming(force: true)
        
        // Camera
        let cam = SKCameraNode()
        camera = cam
        addChild(cam)
        cam.position = car.position
        
        buildRampPointerIfNeeded()
        
        // HUDs
        ringGroup.zPosition = 200
        ringGroup.alpha = ringAlphaIdle
        ringGroup.isHidden = true
        cam.addChild(ringGroup)
        buildSpeedRing()
        
        buildSpeedHUD()
        cam.addChild(speedHUD)
        
        buildHeadingHUD()
        cam.addChild(headingHUD)
        
        kmhMaxShown = car.maxSpeed * kmhPerPointPerSecond
        
        // Ramp pointer HUD (puck)
        buildRampArrowHUD()
        
        // Fire button
        buildFireButton()
        cam.addChild(fireButton)
        placeFireButton()
        
        placeHUD()
        
        // Health HUD
        camera?.addChild(healthHUD)
        placeHUD()
        
        // Car damage notifications → HUD
        car.maxHP = 100
        car.onHPChanged = { [weak self] hp, maxHP in
            self?.healthHUD.set(hp: hp, maxHP: maxHP)
        }
        car.onHPChanged?(car.hp, car.maxHP)
        car.enableCrashContacts()
        
        // Show handedness overlay EVERY time app opens (but don't block controls)
        showHandednessPicker()
    }
    
    private func showHandednessPicker() {
        controlsLockedForOverlay = false
        let ov = HandChoiceOverlayNode(size: size)
        handednessOverlay = ov
        camera?.addChild(ov)
        ov.onPick = { [weak self] left in
            guard let self else { return }
            self.isLeftHanded = left
            self.placeFireButton()
        }
    }
    
    override func didChangeSize(_ oldSize: CGSize) {
        super.didChangeSize(oldSize)
        placeHUD()
        placeFireButton()
        handednessOverlay?.updateSize(size)
    }
    
    // MARK: - Speed ring
    private func buildSpeedRing() {
        ringGroup.removeAllChildren()
        ringBands.removeAll()
        
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
        
        // Active halo
        let initialR: CGFloat = (baseInnerR + baseOuterR) * 0.5
        activeHalo.path = CGPath(ellipseIn: CGRect(x: -initialR, y: -initialR, width: initialR * 2, height: initialR * 2), transform: nil)
        activeHalo.strokeColor = UIColor.white.withAlphaComponent(0.0)
        activeHalo.lineWidth = 10
        activeHalo.glowWidth = 20
        activeHalo.fillColor = .clear
        activeHalo.zPosition = 0.6
        ringGroup.addChild(activeHalo)
        
        // Outer outline
        let outline = SKShapeNode(circleOfRadius: baseOuterR)
        outline.strokeColor = UIColor.white.withAlphaComponent(0.12)
        outline.lineWidth = 2
        outline.glowWidth = 4
        outline.fillColor = .clear
        outline.zPosition = 0.1
        ringGroup.addChild(outline)
        
        // Handle
        ringHandle.path = CGPath(ellipseIn: CGRect(x: -7, y: -7, width: 14, height: 14), transform: nil)
        ringHandle.fillColor = UIColor.white.withAlphaComponent(0.95)
        ringHandle.strokeColor = UIColor.black.withAlphaComponent(0.30)
        ringHandle.lineWidth = 1.5
        ringHandle.position = .zero
        ringHandle.zPosition = 1
        ringGroup.addChild(ringHandle)
    }
    
    private func buildRampPointerIfNeeded() {
        guard !rampPointerBuilt, let cam = camera else { return }
        rampPointerBuilt = true
        
        rampPointer.zPosition = 650
        rampPointer.isHidden = true
        
        // Make the arrow node a container; visuals are built in buildRampArrowHUD()
        rampPointer.addChild(rampArrow)
        cam.addChild(rampPointer)
    }
    
    // World -> camera rect (centered on (0,0) in camera space)
    private var cameraViewRect: CGRect {
        CGRect(x: -size.width/2, y: -size.height/2, width: size.width, height: size.height)
    }
    
    // Where you should aim to approach a ramp correctly (behind it along heading)
    private func rampAimPoint(for ramp: RampNode) -> CGPoint {
        let f = CGVector(dx: cos(ramp.heading), dy: sin(ramp.heading))
        let fr = ramp.calculateAccumulatedFrame()
        let along = max(fr.width, fr.height) * 0.60
        return CGPoint(x: ramp.position.x - f.dx * along,
                       y: ramp.position.y - f.dy * along)
    }
    
    // Choose nearest off-screen, path-clear ramp and place arrow on screen edge
    private func updateRampPointer() {
        buildRampPointerIfNeeded()
        guard let cam = camera else { return }
        
        let viewRect = cameraViewRect.insetBy(dx: rampPointerMargin, dy: rampPointerMargin)
        let carPos   = car.position
        
        var bestAim: CGPoint?
        var bestDist = CGFloat.greatestFiniteMagnitude
        
        // Find nearest *off-screen* ramp with a reasonably clear corridor to its approach point
        let corridorMask: UInt32 = Category.wall | Category.obstacle | Category.hole
        
        for case let ramp as RampNode in obstacleRoot.children {
            let aim = rampAimPoint(for: ramp)
            let d = carPos.distance(to: aim)
            if d > rampPointerMaxDistance { continue }
            
            let aimCam = cam.convert(aim, from: self)
            if viewRect.contains(aimCam) { continue }
            
            if !pathClearCapsule(from: carPos, to: aim, radius: 44, mask: corridorMask) { continue }
            
            if d < bestDist { bestDist = d; bestAim = aim }
        }
        
        // No candidate → hide
        guard let targetWorld = bestAim else {
            if !rampPointer.isHidden {
                rampPointer.run(.sequence([.fadeOut(withDuration: 0.12), .hide()]))
            }
            return
        }
        
        // Project to camera and clamp to screen edge
        let tCam = cam.convert(targetWorld, from: self)
        let halfW = size.width  * 0.5 - rampPointerMargin
        let halfH = size.height * 0.5 - rampPointerMargin
        
        let k = max(abs(tCam.x) / max(halfW, 1), abs(tCam.y) / max(halfH, 1))  // >= 1 for off-screen points
        let edge = CGPoint(x: tCam.x / max(k, 1), y: tCam.y / max(k, 1))       // clamp to edge rectangle
        
        rampPointer.position   = edge
        rampPointer.zRotation  = atan2(tCam.y, tCam.x) - .pi/2   // arrow points along +Y in local space
        
        if rampPointer.isHidden {
            rampPointer.alpha = 0
            rampPointer.isHidden = false
            rampPointer.run(.fadeAlpha(to: 1.0, duration: 0.12))
        }
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
    
    // MARK: - Speed HUD
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
        
        speedLabel.fontSize = 34
        speedLabel.horizontalAlignmentMode = .center
        speedLabel.verticalAlignmentMode = .center
        speedLabel.position = CGPoint(x: 0, y: 10)
        speedLabel.fontColor = UIColor.white.withAlphaComponent(0.95)
        speedLabel.text = "0"
        speedHUD.addChild(speedLabel)
        
        unitLabel.fontSize = 12
        unitLabel.horizontalAlignmentMode = .center
        unitLabel.verticalAlignmentMode = .center
        unitLabel.position = CGPoint(x: 0, y: -14)
        unitLabel.fontColor = UIColor.white.withAlphaComponent(0.75)
        unitLabel.text = "km/h"
        speedHUD.addChild(unitLabel)
        
        let barBase = SKShapeNode(rectOf: CGSize(width: cardW - 24, height: 6), cornerRadius: 3)
        barBase.fillColor = UIColor.white.withAlphaComponent(0.10)
        barBase.strokeColor = .clear
        barBase.position = CGPoint(x: 0, y: -24)
        speedHUD.addChild(barBase)
        
        speedBar.removeFromParent()
        speedBar.fillColor = UIColor.systemTeal.withAlphaComponent(0.85)
        speedBar.strokeColor = .clear
        speedBar.position = CGPoint(x: 0, y: -24)
        let eps: CGFloat = 0.001
        let p0 = CGMutablePath()
        p0.addRect(CGRect(x: -(cardW-24)/2, y: -3, width: eps, height: 6))
        speedBar.path = p0
        speedHUD.addChild(speedBar)
    }
    
    // MARK: - Heading HUD
    private func buildHeadingHUD() {
        headingHUD.zPosition = 400
        headingHUD.alpha = 0.82
        
        let r = headingSize * 0.5
        headingDial.path = CGPath(ellipseIn: CGRect(x: -r, y: -r, width: headingSize, height: headingSize), transform: nil)
        headingDial.fillColor = UIColor(white: 0, alpha: 0.28)
        headingDial.strokeColor = UIColor(white: 1, alpha: 0.10)
        headingDial.lineWidth = 1.0
        headingDial.glowWidth = 2
        headingHUD.addChild(headingDial)
        
        let g = SKShapeNode(circleOfRadius: r - 6)
        g.strokeColor = UIColor.white.withAlphaComponent(0.08)
        g.lineWidth = 2
        g.fillColor = .clear
        headingGlass.path = g.path
        headingHUD.addChild(headingGlass)
        
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
        let margin: CGFloat = 16
        let drop: CGFloat   = 30
        let halfW = speedCard.frame.width  * 0.5
        let halfH = speedCard.frame.height * 0.5
        
        // Speed (top-left)
        speedHUD.position = CGPoint(
            x: -size.width  * 0.5 + margin + halfW,
            y:  size.height * 0.5 - (margin + drop) - halfH
        )
        
        // Heading (top-right)
        let r = headingSize * 0.5
        headingHUD.position = CGPoint(
            x:  size.width  * 0.5 - margin - r,
            y:  size.height * 0.5 - (margin + drop) - r
        )
        
        // Health (under speed)
        healthHUD.position = CGPoint(
            x: -size.width * 0.5 + margin + 80,
            y:  size.height * 0.5 - (margin + drop) - speedCard.frame.height - 18
        )
    }
    
    private func recenterCameraOnCar() {
        guard let cam = camera else { return }
        cam.removeAllActions()              // cancel any residual shake
        cam.position = car.position         // hard-lock car at screen center
    }

    // Keep the camera lock AFTER physics each frame so it never lags
    override func didSimulatePhysics() {
        // If we're freezing on death, don't re-center until respawn
        guard cameraFrozenPos == nil else { return }
        defer { _hadSolidContactThisStep = false }
        guard !_hadSolidContactThisStep else {
            guard !car.isAirborne, let pb = car.physicsBody else { return }
            let heading = car.zRotation + .pi/2
            let fwd  = CGVector(dx: cos(heading),  dy: sin(heading))
            let right = CGVector(dx: -sin(heading), dy: cos(heading))
            
            // pre/post forward components
            let preF  = _preCarVel.dx * fwd.dx + _preCarVel.dy * fwd.dy
            let post  = pb.velocity
            let postF = post.dx * fwd.dx + post.dy * fwd.dy
            let postLat = post.dx * right.dx + post.dy * right.dy
            
            // allow only a small forward gain per step from contacts
            let maxDelta = _contactForwardBoostClampPerSec * _lastDTForClamp
            if postF > preF + maxDelta {
                let clampedF = preF + maxDelta
                let newV = CGVector(
                    dx: fwd.dx * clampedF + right.dx * postLat,
                    dy: fwd.dy * clampedF + right.dy * postLat
                )
                pb.velocity = newV
            }
            return
        }
        recenterCameraOnCar()
    }
    
    private func updateSpeedHUD(kmh: CGFloat) {
        let now = CACurrentMediaTime()
        let dt  = lastHUDSample == 0 ? 1.0/60.0 : max(1e-3, now - lastHUDSample)
        lastHUDSample = now
        
        let alpha = 1 - exp(-dt / Double(max(0.001, speedTau)))
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
        let bodyA = contact.bodyA
        let bodyB = contact.bodyB
        
        @inline(__always) func isBullet(_ b: SKPhysicsBody) -> Bool { (b.categoryBitMask & Category.bullet) != 0 }
        @inline(__always) func isObstacle(_ b: SKPhysicsBody) -> Bool { (b.categoryBitMask & Category.obstacle) != 0 }
        @inline(__always) func isWall(_ b: SKPhysicsBody) -> Bool { (b.categoryBitMask & Category.wall) != 0 }
        @inline(__always) func isCar(_ b: SKPhysicsBody) -> Bool { (b.categoryBitMask & Category.car) != 0 }
        @inline(__always) func isRamp(_ b: SKPhysicsBody) -> Bool { (b.categoryBitMask & Category.ramp) != 0 }
        @inline(__always) func isHill(_ b: SKPhysicsBody) -> Bool { b.node is HillNode }
        @inline(__always) func killBullet(_ b: SKPhysicsBody) {
            b.node?.removeAllActions()
            b.node?.removeFromParent()
        }
        
        // Bullet ↔ Obstacle
        if (isBullet(bodyA) && isObstacle(bodyB)) || (isBullet(bodyB) && isObstacle(bodyA)) {
            let bullet   = isBullet(bodyA) ? bodyA : bodyB
            let obstacle = isObstacle(bodyA) ? bodyA : bodyB
            if let ob = obstacle.node as? ObstacleNode {
                let hitScene = contact.contactPoint
                let hitLocal = ob.convert(hitScene, from: self)
                _ = ob.applyDamage(1, impact: hitLocal)
            }
            killBullet(bullet); return
        }
        
        // Bullet ↔ Wall
        if (isBullet(bodyA) && isWall(bodyB)) || (isBullet(bodyB) && isWall(bodyA)) {
            let bullet = isBullet(bodyA) ? bodyA : bodyB
            killBullet(bullet); return
        }
        
        // Car ↔ Ramp (launch only; no damage here)
        if (isCar(bodyA) && isRamp(bodyB)) || (isCar(bodyB) && isRamp(bodyA)) {
            guard !car.isAirborne else { return }
            let rampBody = isRamp(bodyA) ? bodyA : bodyB
            guard let ramp = rampBody.node as? RampNode else { return }
            
            let carHeading  = car.zRotation + .pi/2
            var align = cos(self.shortestAngle(from: carHeading, to: ramp.heading))
            align = max(0, align)
            
            let spd = car.physicsBody?.velocity.length ?? 0
            let spdFrac = min(1, spd / max(1, car.maxSpeed))
            
            let vz0 = ramp.strengthZ * max(0.72, (0.55 + 0.45*spdFrac)) * align
            let fwdPush = (0.35 * spd + 0.18 * vz0) * align
            let fwdBoost = min(600, max(0, fwdPush))
            
            car.applyRampImpulse(vzAdd: vz0, forwardBoost: fwdBoost, heading: ramp.heading)
            return
        }
        
        // Car ↔ Obstacle/Wall (damage), BUT NEVER from ramps or hills
        let harmMask: UInt32 = (Category.obstacle | Category.wall)
        let carA  = (bodyA.categoryBitMask & Category.car) != 0
        let carB  = (bodyB.categoryBitMask & Category.car) != 0
        let harmA = (bodyA.categoryBitMask & harmMask) != 0
        let harmB = (bodyB.categoryBitMask & harmMask) != 0
        
        if (carA && harmB) || (carB && harmA) {
            let carBody = carA ? bodyA : bodyB
            let other   = carA ? bodyB : bodyA
            
            // ⛔ Never damage from ramps or hills
            if isRamp(other) { return }
            if isHill(other) { return }
            
            _hadSolidContactThisStep = true   // ← NEW: remember this step had a solid contact
            (carBody.node as? CarNode)?.handleCrash(contact: contact, other: other)
            return
        }
    }
    
    // MARK: - Touches
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        if controlsLockedForOverlay || pausedForDeath { return }   // NEW guard
        guard let cam = camera else { return }
        
        for t in touches {
            let pCam = t.location(in: cam)
            
            if fireTouch == nil, pointInsideFireButton(pCam) {
                fireTouch = t
                car.startAutoFire(on: self)
                animateFireTap()
                continue
            }
            
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
        if controlsLockedForOverlay || pausedForDeath { return }   // NEW guard
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
        if controlsLockedForOverlay || pausedForDeath { return }   // NEW guard
        for t in touches {
            if let ft = fireTouch, t === ft {
                fireTouch = nil
                car.stopAutoFire()
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
    
    // MARK: - Ring show/hide
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
    
    // MARK: - Fire button
    private func buildFireButton() {
        fireButton.zPosition = 500
        
        let R: CGFloat = 40
        fireBase.path = CGPath(ellipseIn: CGRect(x: -R, y: -R, width: R*2, height: R*2), transform: nil)
        fireBase.fillColor = UIColor(red: 0.95, green: 0.18, blue: 0.25, alpha: 0.90)
        fireBase.strokeColor = UIColor.white.withAlphaComponent(0.18)
        fireBase.lineWidth = 1.5
        fireBase.glowWidth = 2
        fireButton.addChild(fireBase)
        
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
        spawnHillsAndRamps(in: rect, nodesOut: &nodes, cx: cx, cy: cy)
        loadedChunks[key] = nodes
    }
    
    // Lower density, better spacing, deterministic per chunk
    private func spawnObstacles(in rect: CGRect, nodesOut: inout [SKNode], cx: Int, cy: Int) {
        let barrierChance: CGFloat = 0.10
        let coneRowChanceLocal: CGFloat = 0.16
        let steelChanceSingle: CGFloat = 0.15
        
        let pad: CGFloat = max(28, obstacleCell * 0.08)
        let cols = Int(ceil(rect.width / obstacleCell))
        let rows = Int(ceil(rect.height / obstacleCell))
        
        let worldCenter = CGPoint(x: worldBounds.midX, y: worldBounds.midY)
        
        for j in 0..<rows {
            for i in 0..<cols {
                var rng = SplitMix64(seed: hash2(cx*10_000 + i, cy*10_000 + j, seed: worldSeed))
                
                let cellRect = CGRect(
                    x: rect.minX + CGFloat(i) * obstacleCell,
                    y: rect.minY + CGFloat(j) * obstacleCell,
                    width: obstacleCell, height: obstacleCell
                )
                let jitterX = rng.range(pad...(obstacleCell - pad))
                let jitterY = rng.range(pad...(obstacleCell - pad))
                let a = CGPoint(x: cellRect.minX + jitterX, y: cellRect.minY + jitterY)
                
                if !worldBounds.insetBy(dx: obstacleEdgeMargin, dy: obstacleEdgeMargin).contains(a) { continue }
                if a.distance(to: car.position) < obstacleKeepOutFromCar { continue }
                
                let toCenter = hypot(a.x - worldCenter.x, a.y - worldCenter.y)
                let maxR = 0.5 * hypot(worldBounds.width, worldBounds.height)
                let falloff = CGFloat.clamp(toCenter / max(1, maxR), 0, 1)
                let placeP: CGFloat = 0.14 + 0.28 * falloff
                if !rng.chance(placeP) { continue }
                
                if hasNeighborObstacle(near: a, radius: minNeighborSpacing) { continue }
                
                let avoidMask: UInt32 = Category.wall | Category.obstacle | Category.hole | Category.car
                if !clearanceOK(at: a, radius: obstacleClearanceMajor, mask: avoidMask) { continue }
                
                var placedSomething = false
                var placedNodes: [SKNode] = []
                
                // barrier
                if rng.chance(barrierChance) {
                    let dir = CGVector(dx: a.x - worldCenter.x, dy: a.y - worldCenter.y)
                    let rot = atan2(dir.dy, dir.dx)
                    
                    if !hasNeighborObstacle(near: a, radius: minNeighborSpacing),
                       let barrier = placeObstacleTracked(.barrier, at: a, rotation: rot) {
                        placedSomething = true
                        placedNodes.append(barrier)
                        
                        let back = CGPoint(x: a.x - cos(rot) * 56, y: a.y - sin(rot) * 56)
                        let left = CGPoint(x: back.x - sin(rot) * 16, y: back.y + cos(rot) * 16)
                        let right = CGPoint(x: back.x + sin(rot) * 16, y: back.y - cos(rot) * 16)
                        
                        if !hasNeighborObstacle(near: left, radius: minNeighborSpacing),
                           let l = placeObstacleTracked(.cone, at: left, rotation: rot) { placedNodes.append(l) }
                        if !hasNeighborObstacle(near: right, radius: minNeighborSpacing),
                           let r = placeObstacleTracked(.cone, at: right, rotation: rot) { placedNodes.append(r) }
                    }
                }
                
                // cone row
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
                        rowNodes.forEach { $0.removeFromParent() }
                    }
                }
                
                // single scatter
                if !placedSomething {
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
    
    // MARK: - Placement utilities
    
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
    
    // ─────────────────────────────────────────────────────────────────────────────
    // Make static/dynamic obstacles non-bouncy
    // ─────────────────────────────────────────────────────────────────────────────
    
    @discardableResult
    private func placeObstacleTracked(_ kind: ObstacleKind, at p: CGPoint, rotation: CGFloat = 0) -> SKNode? {
        if !worldBounds.insetBy(dx: obstacleEdgeMargin, dy: obstacleEdgeMargin).contains(p) { return nil }
        
        let avoidMask: UInt32 = Category.wall | Category.obstacle | Category.hole | Category.ramp | Category.car
        if !clearanceOK(at: p, radius: obstacleClearanceMajor, mask: avoidMask) { return nil }
        
        let node = ObstacleFactory.make(kind)
        node.position = p
        node.zRotation = rotation
        node.zPosition = 1
        
        if let pb = node.physicsBody {
            pb.restitution = 0         // ← NEW
            pb.friction = 0            // ← NEW (already common, just enforce)
            pb.usesPreciseCollisionDetection = true
        }
        obstacleRoot.addChild(node)
        return node
    }
    
    private func hasNeighborObstacle(near p: CGPoint, radius: CGFloat) -> Bool {
        var found = false
        let r = CGRect(x: p.x - radius, y: p.y - radius, width: radius*2, height: radius*2)
        let mask: UInt32 = Category.obstacle | Category.ramp | Category.hole
        physicsWorld.enumerateBodies(in: r) { body, stop in
            if (body.categoryBitMask & mask) != 0,
               let n = body.node {
                if let _ = n.parent, n.position.distance(to: p) < radius {
                    found = true; stop.pointee = true
                }
            }
        }
        return found
    }
    
    // MARK: - Hills & ramps -----------------------------------------------------
    
    func spawnHill(at center: CGPoint, size: CGSize, height: CGFloat) {
        let rect = CGRect(x: center.x - size.width/2, y: center.y - size.height/2,
                          width: size.width, height: size.height)
        let hill = HillNode(rect: rect, height: height)
        hill.zPosition = 0.5
        addChild(hill)
        hills.append(hill)
    }
    
    /// Smooth ground height so you can drive on/off a hill without getting stuck.
    /// Height = top at inner plateau, then smooth falloff to 0 near ellipse edge.
    private func groundHeight(at p: CGPoint) -> CGFloat {
        var h: CGFloat = 0
        for hill in hills where hill.parent != nil {
            let f = hill.calculateAccumulatedFrame()
            let cx = f.midX, cy = f.midY
            let rx = max(1, f.width * 0.5)
            let ry = max(1, f.height * 0.5)
            
            let dx = (p.x - cx) / rx
            let dy = (p.y - cy) / ry
            let r = sqrt(dx*dx + dy*dy)
            
            if r <= 1.05 {
                let inner: CGFloat = 0.35
                let t: CGFloat
                if r <= inner {
                    t = 0
                } else {
                    let u = min(1, (r - inner) / max(0.0001, (1 - inner)))
                    t = u*u*(3 - 2*u)
                }
                let hh = hill.topHeight * (1 - t)
                h = max(h, hh)
            }
        }
        return h
    }
    
    func spawnRamp(at center: CGPoint, size: CGSize, angleRadians: CGFloat, strengthZ: CGFloat = 850) {
        let ramp = RampNode(center: center, size: size, heading: angleRadians, strengthZ: strengthZ)
        ramp.zPosition = 0.4
        obstacleRoot.addChild(ramp)
    }
    
    @inline(__always)
    private func ellipseRadiusAlong(rx: CGFloat, ry: CGFloat, vx: CGFloat, vy: CGFloat) -> CGFloat {
        let denom = sqrt((vx*vx)/(rx*rx) + (vy*vy)/(ry*ry))
        return denom < 1e-6 ? 0 : 1/denom
    }
    
    @inline(__always)
    private func pathClearCapsule(from a: CGPoint, to b: CGPoint, radius r: CGFloat, mask: UInt32) -> Bool {
        let dx = b.x - a.x, dy = b.y - a.y
        let dist = hypot(dx, dy)
        let steps = max(1, Int(ceil(dist / max(24, r * 0.75))))
        for i in 0...steps {
            let t = CGFloat(i) / CGFloat(steps)
            let p = CGPoint(x: a.x + dx * t, y: a.y + dy * t)
            var blocked = false
            let box = CGRect(x: p.x - r, y: p.y - r, width: r*2, height: r*2)
            physicsWorld.enumerateBodies(in: box) { body, stop in
                if (body.categoryBitMask & mask) != 0 { blocked = true; stop.pointee = true }
            }
            if blocked { return false }
        }
        return true
    }
    
    /// Place a single, useful and **narrow** ramp pointed toward the hill.
    @discardableResult
    private func placeUsefulRamp(for hill: HillNode,
                                 runupRange: ClosedRange<CGFloat> = 520...900,
                                 corridorHalfWidth: CGFloat = 56,
                                 rng: inout SplitMix64) -> RampNode? {
        
        let f = hill.calculateAccumulatedFrame()
        let center = CGPoint(x: f.midX, y: f.midY)
        let rx = f.width  * 0.5
        let ry = f.height * 0.5
        let worldCtr = CGPoint(x: worldBounds.midX, y: worldBounds.midY)
        
        func dir(_ a: CGFloat) -> CGVector { .init(dx: cos(a), dy: sin(a)) }
        let baseHeading = atan2(center.y - worldCtr.y, center.x - worldCtr.x)
        
        let candidates: [CGFloat] = [
            baseHeading,
            baseHeading + (.pi/10),
            baseHeading - (.pi/10),
            rng.range(-.pi ... .pi)
        ]
        
        let rampWidthRange: ClosedRange<CGFloat>  = 64...88
        let rampLengthRange: ClosedRange<CGFloat> = 110...160
        
        for heading in candidates {
            let d = dir(heading)
            let edge = ellipseRadiusAlong(rx: rx, ry: ry, vx: d.dx, vy: d.dy)
            let gap: CGFloat = 70
            let rampCenter = CGPoint(x: center.x - d.dx * (edge + gap),
                                     y: center.y - d.dy * (edge + gap))
            
            let runLen = rng.range(runupRange)
            let start  = CGPoint(x: rampCenter.x - d.dx * runLen,
                                 y: rampCenter.y - d.dy * runLen)
            
            let corridorMask: UInt32 = Category.wall | Category.obstacle | Category.hole | Category.ramp
            guard pathClearCapsule(from: start, to: rampCenter, radius: corridorHalfWidth, mask: corridorMask) else { continue }
            
            let rampSize  = CGSize(width: rng.range(rampWidthRange), height: rng.range(rampLengthRange))
            let g = abs(car.gravity)
            let heightToReach = max(0, hill.topHeight - groundHeight(at: rampCenter))
            let vzNeeded = sqrt(max(1, 2 * g * max(20, heightToReach * 1.05)))
            
            let ramp = RampNode(center: rampCenter, size: rampSize, heading: heading, strengthZ: vzNeeded)
            ramp.zPosition = 0.4
            obstacleRoot.addChild(ramp)
            return ramp
        }
        return nil
    }
    
    private func spawnHillsAndRamps(in rect: CGRect, nodesOut: inout [SKNode], cx: Int, cy: Int) {
        var rng = SplitMix64(seed: hash2(cx &* 7919, cy &* 104729, seed: worldSeed ^ 0xC0FFEE))
        
        // Density
        let hillsPerChunkChance: CGFloat = 0.58
        let hillsPerChunkMax = 2
        let rampsPerHillTarget = 3
        let rampRunupRange: ClosedRange<CGFloat> = 520...1000
        let rampCorridorHalfWidth: CGFloat = 56
        
        let wantHills = (rng.chance(hillsPerChunkChance) ? 1 : 0)
        + (rng.chance(hillsPerChunkChance * 0.50) ? 1 : 0)
        let count = min(wantHills, hillsPerChunkMax)
        
        let pad: CGFloat = max(140, obstacleCell * 0.22)
        let allowed = rect.insetBy(dx: pad, dy: pad)
        
        for _ in 0..<count {
            let sz = CGSize(width:  rng.range(320...540),
                            height: rng.range(220...420))
            let c  = CGPoint(x: rng.range(allowed.minX...allowed.maxX),
                             y: rng.range(allowed.minY...allowed.maxY))
            
            let minHillSpacing = max(minNeighborSpacing, max(sz.width, sz.height))
            if c.distance(to: car.position) < max(minHillSpacing, obstacleKeepOutFromCar) { continue }
            if hills.contains(where: { $0.parent != nil && $0.calculateAccumulatedFrame().contains(CGPoint(x: c.x, y: c.y)) }) { continue }
            
            let avoidMask: UInt32 = Category.wall | Category.obstacle | Category.hole | Category.ramp | Category.car
            if !clearanceOK(at: c, radius: minHillSpacing * 0.6, mask: avoidMask) { continue }
            
            let rectHill = CGRect(x: c.x - sz.width/2, y: c.y - sz.height/2, width: sz.width, height: sz.height)
            let h = rng.range(90...180)
            let hill = HillNode(rect: rectHill, height: h)
            hill.zPosition = 0.5
            addChild(hill)
            hills.append(hill)
            nodesOut.append(hill)
            
            var made = 0
            for _ in 0..<rampsPerHillTarget {
                if let r = placeUsefulRamp(for: hill,
                                           runupRange: rampRunupRange,
                                           corridorHalfWidth: rampCorridorHalfWidth,
                                           rng: &rng) {
                    nodesOut.append(r); made += 1
                }
            }
            if made == 0 {
                var relaxed = rng
                if let r = placeUsefulRamp(for: hill,
                                           runupRange: (rampRunupRange.lowerBound - 120)...(rampRunupRange.upperBound + 200),
                                           corridorHalfWidth: rampCorridorHalfWidth * 0.8,
                                           rng: &relaxed) {
                    nodesOut.append(r)
                }
            }
        }
    }
    
    // MARK: - Ramp pointer HUD (puck)
    private func buildRampArrowHUD() {
        rampArrow.zPosition = 600
        
        // Base puck (ring)
        let R: CGFloat = 18
        let ringRect = CGRect(x: -R, y: -R, width: 2*R, height: 2*R)
        rampArrowBase.path = CGPath(ellipseIn: ringRect, transform: nil)
        rampArrowBase.fillColor = UIColor(white: 0, alpha: 0.28)
        rampArrowBase.strokeColor = UIColor.white.withAlphaComponent(0.22)
        rampArrowBase.lineWidth = 1.5
        rampArrowBase.glowWidth = 2
        rampArrow.addChild(rampArrowBase)
        
        // Pulse halo
        let haloR: CGFloat = R + 6
        rampArrowPulse.path = CGPath(ellipseIn: CGRect(x: -haloR, y: -haloR, width: 2*haloR, height: 2*haloR), transform: nil)
        rampArrowPulse.strokeColor = UIColor.systemTeal.withAlphaComponent(0.55)
        rampArrowPulse.fillColor = .clear
        rampArrowPulse.lineWidth = 3
        rampArrowPulse.glowWidth = 4
        rampArrow.addChild(rampArrowPulse)
        let pulseUp = SKAction.group([.scale(to: 1.08, duration: 0.6), .fadeAlpha(to: 0.25, duration: 0.6)])
        let pulseDn = SKAction.group([.scale(to: 1.00, duration: 0.6), .fadeAlpha(to: 0.55, duration: 0.6)])
        rampArrowPulse.run(.repeatForever(.sequence([pulseUp, pulseDn])))
        
        // Arrow head (points along +Y in local space) inside the puck
        let padding: CGFloat = 3.0
        let innerR = R - padding
        let tipY: CGFloat = innerR - 0.5
        let baseY: CGFloat = innerR - 8.0
        let w: CGFloat = 10.0
        
        let tri = CGMutablePath()
        tri.move(to: CGPoint(x: 0, y: tipY))
        tri.addLine(to: CGPoint(x:  w * 0.5, y: baseY))
        tri.addLine(to: CGPoint(x: -w * 0.5, y: baseY))
        tri.closeSubpath()
        rampArrowHead.path = tri
        rampArrowHead.fillColor = .black
        rampArrowHead.strokeColor = UIColor.white.withAlphaComponent(0.25)
        rampArrowHead.lineWidth = 1
        rampArrow.addChild(rampArrowHead)
    }
    
    // Flip placement by chosen hand
    private func placeFireButton() {
        let margin: CGFloat = 20
        let R: CGFloat = 40
        let x = isLeftHanded
        ? (-size.width * 0.5 + margin + R)
        : ( size.width * 0.5 - margin - R)
        fireButton.position = CGPoint(x: x, y: -size.height * 0.5 + margin + R)
    }
    
    // MARK: - Update
    override func update(_ currentTime: TimeInterval) {
        let raw = (lastUpdate == 0) ? 0 : (currentTime - lastUpdate)
        lastUpdate = currentTime
        let dt = CGFloat(min(max(raw, 0), 0.05))
        
        // Freeze camera hard while dead; unfreeze on respawn
        if let freeze = cameraFrozenPos {
            camera?.removeAllActions()
            camera?.position = freeze
            if car.isDead {
                return
            } else {
                cameraFrozenPos = nil
                resumeWorldAfterRespawn() // NEW
                // fall through to normal update this frame
            }
        }
        
        guard dt > 0 else {
            camera?.position = car.position
            return
        }
        
        camera?.position = car.position
        
        maybeUpdateObstacleStreaming(currentTime)
        
        if !car.isDead, isTouching, controlArmed, let f = fingerCam, let pb = car.physicsBody {
            isCoasting = false
            
            let vFinger = CGVector(dx: f.x, dy: f.y)
            let dRaw    = hypot(vFinger.dx, vFinger.dy)
            let (innerR, outerR) = currentRadii()
            let dClamped = CGFloat.clamp(dRaw, innerR, outerR)
            let angRaw   = atan2(vFinger.dy, vFinger.dx)
            
            ringHandle.position = CGPoint(x: cos(angRaw) * dClamped, y: sin(angRaw) * dClamped)
            
            let tNormBase = (dClamped <= innerR + 1) ? 0 : (dClamped - innerR) / max(outerR - innerR, 1)
            let tNorm = CGFloat.clamp(tNormBase, 0, 1)
            let idx = max(0, min(4, Int(floor(tNorm * 5))))
            setActiveBand(index: idx)
            
            if lockAngleUntilExitDeadzone, dRaw > innerR + 4 {
                lockAngleUntilExitDeadzone = false
            }
            
            // === DRIVING LOGIC ===
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
            
            let heading  = car.zRotation + .pi/2
            let angleErr = shortestAngle(from: heading, to: angleLP)
            if lockAngleUntilExitDeadzone || dRaw <= innerR + 4 {
                car.steer = 0.001
            } else {
                let steerP = angleErr / (.pi/3)
                car.steer  = tanh(2.1 * steerP)
            }
            
            let fwd = CGVector(dx: cos(heading), dy: sin(heading))
            let v   = pb.velocity
            let fwdMag = v.dx * fwd.dx + v.dy * fwd.dy
            
            let baseTarget = tNorm * car.maxSpeed
            
            let overshootEps: CGFloat = 6
            let outside = dRaw > outerR + overshootEps
            let targetSpeed: CGFloat
            if outside {
                targetSpeed = car.maxSpeed + 280
                car.speedCapBonus = 280
            } else {
                targetSpeed = baseTarget
                car.speedCapBonus = 0
            }
            
            if lockAngleUntilExitDeadzone || dRaw <= innerR + 4 {
                car.throttle = 0
            } else {
                let err = targetSpeed - max(0, fwdMag)
                let deadband: CGFloat = 25
                let accelGain: CGFloat = 280
                
                let hold = (0.06 + 0.34 * pow(tNorm, 1.15))
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
            }
            // === END DRIVING LOGIC ===
            
        } else if isCoasting && !car.isDead {
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
            car.speedCapBonus = 0
        } else {
            car.throttle = 0
            car.steer = 0
            hasAngleLP = false
            lockAngleUntilExitDeadzone = false
            car.speedCapBonus = 0
        }
        
        // Keep the vertical axis in sync with terrain (smooth hill profile)
        let gh = groundHeight(at: car.position)
        applyHillModifiers(gh: gh)
        car.stepVertical(dt: dt, groundHeight: gh)
        
        car.update(dt)
        
        car.update(dt)
        
        _preCarVel = car.physicsBody?.velocity ?? .zero   // ← NEW
        _lastDTForClamp = dt
        
        let ptsPerSec = car.physicsBody?.velocity.length ?? 0
        let kmh = ptsPerSec * kmhPerPointPerSecond
        updateSpeedHUD(kmh: kmh)
        
        let actualHeading = car.zRotation + .pi/2
        let desiredHeading = (hasAngleLP ? angleLP : actualHeading)
        updateHeadingHUD(desired: desiredHeading, actual: actualHeading)
        
        updateRampPointer()
        cullBulletsOutsideWorld()
    }
    
    // GameScene.swift — helpers (add anywhere in GameScene)
    @inline(__always)
    private func groundGradientMagnitude(at p: CGPoint) -> CGFloat {
        // Finite differences on your groundHeight() field
        let h: CGFloat = 8
        let hx = groundHeight(at: CGPoint(x: p.x + h, y: p.y)) - groundHeight(at: CGPoint(x: p.x - h, y: p.y))
        let hy = groundHeight(at: CGPoint(x: p.x, y: p.y + h)) - groundHeight(at: CGPoint(x: p.x, y: p.y - h))
        // height per point; scale to a convenient range
        return 0.5 * sqrt(hx*hx + hy*hy)
    }
    
    private func applyHillModifiers(gh: CGFloat) {
        // Treat tiny residual heights at the base as flat → no penalties
        if gh < 16 {
            car.hillSpeedMul = 1
            car.hillAccelMul = 1
            car.hillDragK    = 0
            return
        }
        
        let gvec = groundGradient(at: car.position)           // ∇h (uphill)
        let gmag = hypot(gvec.dx, gvec.dy) * 0.5              // same scale as groundGradientMagnitude
        let slope = min(1, gmag / 28.0)                       // 0 on flat → 1 on steep rim
        
        // Forward / downhill alignment
        let heading = car.zRotation + .pi/2
        let fwd = CGVector(dx: cos(heading), dy: sin(heading))
        var down = CGVector(dx: -gvec.dx, dy: -gvec.dy)       // downhill
        let dLen = max(1e-6, hypot(down.dx, down.dy))
        down.dx /= dLen; down.dy /= dLen
        let alignDown = max(0, fwd.dx * down.dx + fwd.dy * down.dy)   // 0…1
        
        // Base hill penalties are now gentler
        var speedMul = 0.85 - 0.20 * slope                     // 0.65…0.85 (was 0.35…0.58)
        var accelMul = 0.95 - 0.45 * slope                     // 0.50…0.95 (was 0.50…0.75)
        var dragK    = 0.6  + 1.4  * slope                     // lighter extra drag
        
        // Downhill assist: reduce penalties and add "free" acceleration down the slope
        // (implemented by raising accelMul toward/above 1 when aligned downhill)
        let assist = alignDown * slope                         // 0…1 only if pointing downhill
        speedMul = min(1.00, speedMul + 0.22 * assist)         // loosen cap when rolling down
        accelMul = min(1.20, accelMul + 0.55 * assist)         // push down the hill
        dragK    = max(0.0, dragK * (1.0 - 0.55 * assist))     // less drag when going with gravity
        
        car.hillSpeedMul = speedMul
        car.hillAccelMul = accelMul
        car.hillDragK    = dragK
    }
    
    // ─────────────────────────────────────────────────────────────────────────────
    // Vector version: uphill gradient (∇h). Downhill is the negative of this.
    // ─────────────────────────────────────────────────────────────────────────────
    @inline(__always)
    func groundGradient(at p: CGPoint) -> CGVector {
        let h: CGFloat = 8
        let hx = groundHeight(at: CGPoint(x: p.x + h, y: p.y)) - groundHeight(at: CGPoint(x: p.x - h, y: p.y))
        let hy = groundHeight(at: CGPoint(x: p.x, y: p.y + h)) - groundHeight(at: CGPoint(x: p.x, y: p.y - h))
        return CGVector(dx: 0.5 * hx, dy: 0.5 * hy)   // height per point (matches magnitude helper)
    }
}

// MARK: - Destruction FX (scene-level) ----------------------------------------
extension GameScene {
    func spawnDestructionFX(at p: CGPoint, for kind: ObstacleKind) {
        // Choose debris palette by obstacle kind
        let debrisColors: [UIColor]
        switch kind {
        case .cone:    debrisColors = [UIColor.orange, UIColor(red: 1, green: 0.65, blue: 0.2, alpha: 1), .white]
        case .barrel:  debrisColors = [UIColor.brown, UIColor(red: 0.35, green: 0.18, blue: 0.08, alpha: 1), .white]
        case .rock:    debrisColors = [UIColor(white: 0.85, alpha: 1), UIColor(white: 0.55, alpha: 1), UIColor(white: 0.35, alpha: 1)]
        case .barrier: debrisColors = [UIColor(white: 0.85, alpha: 1), UIColor(white: 0.7, alpha: 1), UIColor(white: 0.4, alpha: 1)]
        case .steel:   debrisColors = [UIColor(white: 0.9, alpha: 1), UIColor(white: 0.6, alpha: 1)]
        }
        
        // Shock ring
        let ring = SKShapeNode(circleOfRadius: 6)
        ring.position = p
        ring.strokeColor = UIColor.white.withAlphaComponent(0.8)
        ring.lineWidth = 3
        ring.fillColor = .clear
        ring.zPosition = 50
        addChild(ring)
        ring.run(.sequence([.group([.scale(to: 8.0, duration: 0.35),
                                    .fadeOut(withDuration: 0.35)]),
                            .removeFromParent()]))
        
        // Sparks
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
        spark.particleBirthRate = 4000
        spark.run(.sequence([
            .wait(forDuration: 0.05),
            .run { spark.particleBirthRate = 0 },
            .wait(forDuration: 0.7),
            .removeFromParent()
        ]))
        
        // Smoke puff
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
        
        // Chunky debris sprites
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
        
        shakeCamera(intensity: 6, duration: 0.20)
    }
    
    // MARK: helpers used by FX
    
    func makeRoundTex(px: CGFloat) -> SKTexture {
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
    
    func makeRectTex(size: CGSize) -> SKTexture {
        let img = UIGraphicsImageRenderer(size: size).image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
        }
        let t = SKTexture(image: img)
        t.filteringMode = .nearest
        return t
    }
    
    func shakeCamera(intensity: CGFloat, duration: TimeInterval) {
        guard let cam = camera else { return }
        if strictCentering { return }   // never offset the view from the car
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
    
    // GameScene.swift — spawn safety helpers + safeSpawnPoint(in:radius:)
    @inline(__always)
    private func circleIntersectsRect(center: CGPoint, radius: CGFloat, rect: CGRect) -> Bool {
        let nx = max(rect.minX, min(center.x, rect.maxX))
        let ny = max(rect.minY, min(center.y, rect.maxY))
        let dx = center.x - nx
        let dy = center.y - ny
        return (dx*dx + dy*dy) <= radius*radius
    }
    
    // Any node that should block spawning now or in the future.
    @inline(__always)
    private func nodeBlocksSpawn(_ n: SKNode) -> Bool {
        if n is HillNode { return true }
        if n is RampNode { return true }
        if let ud = n.userData, ud["spawnBlocks"] as? Bool == true { return true }
        if let name = n.name?.lowercased(), name.contains("enhancement") || name.contains("powerup") { return true }
        return false
    }
    
    private func isBlocked(at p: CGPoint, radius: CGFloat) -> Bool {
        // Physics bodies that must not overlap spawns
        let area = CGRect(x: p.x - radius, y: p.y - radius, width: radius*2, height: radius*2)
        let physicsMask: UInt32 = (Category.wall | Category.obstacle | Category.hole | Category.ramp | Category.car)
        
        var blockedByPhysics = false
        physicsWorld.enumerateBodies(in: area) { body, stop in
            if (body.categoryBitMask & physicsMask) != 0 {
                blockedByPhysics = true; stop.pointee = true
            }
        }
        if blockedByPhysics { return true }
        
        // Hills (often non-physics)
        for hill in hills where hill.parent != nil {
            let fr = hill.calculateAccumulatedFrame()
            if circleIntersectsRect(center: p, radius: radius, rect: fr) { return true }
        }
        
        // Ramps + future enhancements/powerups hosted under obstacleRoot
        for n in obstacleRoot.children where nodeBlocksSpawn(n) {
            let fr = n.calculateAccumulatedFrame()
            if circleIntersectsRect(center: p, radius: radius, rect: fr) { return true }
        }
        
        // Keep away from world edges
        if !worldBounds.insetBy(dx: radius, dy: radius).contains(p) { return true }
        
        return false
    }
    
    private func safeSpawnPoint(in rect: CGRect, radius: CGFloat, attempts: Int = 128) -> CGPoint {
        var inner = rect.intersection(worldBounds).insetBy(dx: radius, dy: radius)
        if inner.isNull || inner.width < 2 || inner.height < 2 {
            inner = rect.insetBy(dx: radius, dy: radius)
        }
        
        let minX = min(inner.minX, inner.maxX)
        let maxX = max(inner.minX, inner.maxX)
        let minY = min(inner.minY, inner.maxY)
        let maxY = max(inner.minY, inner.maxY)
        
        // Random sampling
        for _ in 0..<attempts {
            let p = CGPoint(x: .random(in: minX...maxX), y: .random(in: minY...maxY))
            if !isBlocked(at: p, radius: radius) { return p }
        }
        
        // Grid fallback
        let step = max(16, radius * 0.8)
        let cols = max(1, Int(ceil(inner.width  / step)))
        let rows = max(1, Int(ceil(inner.height / step)))
        let cx = inner.midX, cy = inner.midY
        var candidates: [CGPoint] = []
        for j in 0...rows {
            for i in 0...cols {
                let x = inner.minX + CGFloat(i) * step
                let y = inner.minY + CGFloat(j) * step
                candidates.append(CGPoint(x: x, y: y))
            }
        }
        candidates.sort {
            let da = hypot($0.x - cx, $0.y - cy)
            let db = hypot($1.x - cx, $1.y - cy)
            return da < db
        }
        for p in candidates {
            if !isBlocked(at: p, radius: radius) { return p }
        }
        
        // Expand rings
        var expand: CGFloat = radius * 1.5
        for _ in 0..<6 {
            let expanded = inner.insetBy(dx: -expand, dy: -expand).intersection(worldBounds)
            if expanded.isNull || expanded.width < 2 || expanded.height < 2 {
                expand += radius; continue
            }
            let cols2 = max(1, Int(ceil(expanded.width  / step)))
            let rows2 = max(1, Int(ceil(expanded.height / step)))
            for j in 0...rows2 {
                for i in 0...cols2 {
                    let x = expanded.minX + CGFloat(i) * step
                    let y = expanded.minY + CGFloat(j) * step
                    let p = CGPoint(x: x, y: y)
                    if !isBlocked(at: p, radius: radius) { return p }
                }
            }
            expand += radius
        }
        
        return CGPoint(x: rect.midX, y: rect.midY)
    }
}

// MARK: - CarNodeDelegate
extension GameScene: CarNodeDelegate {
    func carNodeDidExplode(_ car: CarNode, at position: CGPoint) {
        spawnDestructionFX(at: position, for: .steel)
        shakeCamera(intensity: 6, duration: 0.20)
        
        // HARD FREEZE the camera until respawn + pause world
        cameraFrozenPos = position
        camera?.removeAllActions()
        camera?.position = position
        pauseWorldForDeath()     // NEW
    }
    func carNodeRequestRespawnPoint(_ car: CarNode) -> CGPoint {
        let search = cameraWorldRect(margin: 400).insetBy(dx: 120, dy: 120)
        return safeSpawnPoint(in: search, radius: spawnClearance)
    }
}

