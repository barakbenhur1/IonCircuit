//
//  GameScene.swift
//  IonCircuit
//
//  Created by Barak Ben Hur on 12/10/2025.
//

import SpriteKit
import UIKit

final class GameScene: SKScene, SKPhysicsContactDelegate, UIGestureRecognizerDelegate {
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
    let car = CarNode()
    private var openWorld: OpenWorldNode?
    
    private var worms: [WormNode] = []
    private let wormSpawnInterval: ClosedRange<TimeInterval> = 6.5...10.5
    private let maxLiveWorms = 20
    private let holeAvoidMask: UInt32 = Category.wall | Category.obstacle | Category.ramp | Category.car | Category.hill
    
    // ==== Input ====
    private var isTouching = false
    private var controlArmed = false
    private var fingerCam: CGPoint?
    
    private var pendingChunkLoads: [(Int, Int)] = []
    private var pendingChunkUnloads: [[SKNode]] = []
    private let streamChunkLoadBudgetPerFrame = 1        // load <= N chunks per frame
    private let streamNodeUnloadBudgetPerFrame = 80
    
    // ==== Speed Ring HUD ====
    private let ringGroup = SKNode()
    private var ringBands: [SKShapeNode] = []
    private let ringHandle = SKShapeNode()
    private let activeHalo = SKShapeNode()
    
    private let baseInnerR: CGFloat = 14
    private let baseOuterR: CGFloat = 88
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
    
    // Enemy blip on the compass
    private let enemyBlip = SKShapeNode()
    private let enemyBlipMaxDistance: CGFloat = 1800
    private let enemyBlipScreenMargin: CGFloat = 28
    
    // ==== Fire (button / bullets) ====
    private let fireButton = SKNode()
    private let fireBase = SKShapeNode()
    private let fireIcon = SKShapeNode()
    // Fire button colors (idle/active)
    private let fireIdleColor  = UIColor(red: 0.95, green: 0.18, blue: 0.25, alpha: 0.90)
    private let fireActiveColor = UIColor(red: 1.00, green: 0.42, blue: 0.15, alpha: 0.98)
    
    // ==== DRIVE BUTTON (movement) — NEW =======================================
    private let driveButton = SKNode()
    private let driveBase = SKShapeNode()
    private let driveIcon = SKShapeNode()   // container for arrows
    
    // Per-direction arrow nodes (so we can color individually)
    private let driveArrowUp = SKShapeNode()
    private let driveArrowDown = SKShapeNode()
    private let driveArrowLeft = SKShapeNode()
    private let driveArrowRight = SKShapeNode()
    private let driveArrowInactive = UIColor.white.withAlphaComponent(0.55)
    
    private let controlButtonRadius: CGFloat = 40   // SAME as fire button (unpressed)
    // ==========================================================================
    
    private var driveTouch: UITouch?
    private var fireTouch: UITouch?
    
    // --- RL firing & ramp shaping state ---
    private weak var rlAgentCar: CarNode?
    private weak var rlTargetCar: CarNode?
    
    // === RL: run BOTH cars with real training ==========================
    var aiControlsPlayer = true // false
    private var rlControlsPlayer = true // false      // the .player car is driven by RL
    private var rlControlsEnemy  = true      // enemies driven by RL (first enemy)
    private var playerRLServer: RLServer?
    private var enemyRLServer:  RLServer?
    private var toggle: RLCardToggle?
    
    private var nextRampPointerUpdate: TimeInterval = 0
    private let rampPointerUpdateInterval: TimeInterval = 0.25
    
    private var nextWormAt: TimeInterval = 0
    
    // World bounds
    var worldBounds: CGRect = .zero
    // ==== Spawn only in the map BORDER band ====
    private let borderBandWidth: CGFloat = 420   // thickness of the allowed border ring
    private let borderOuterPadding: CGFloat = 28 // keep a tiny gap from the absolute outer wall
    
    // ==== Air phasing for hill rim (so we can clear the wall while jumping)
    private var playerPhasingWallsUntilLand = false
    
    @inline(__always)
    private func setPassThroughWallsWhileAirborne(_ car: CarNode, enabled: Bool) {
        guard let pb = car.physicsBody else { return }
        if enabled {
            // remember original mask exactly once
            if car.userData == nil { car.userData = NSMutableDictionary() }
            if car.userData?["origCollisionMask"] == nil {
                car.userData?["origCollisionMask"] = pb.collisionBitMask
            }
            // allow passing the hill rim (Category.wall) while airborne
            pb.collisionBitMask &= ~(Category.wall | Category.hill)
        } else {
            if let orig = car.userData?["origCollisionMask"] as? UInt32 {
                pb.collisionBitMask = orig
            }
            car.userData?["origCollisionMask"] = nil
        }
    }
    
    
    @inline(__always)
    private func pointInBorderBand(_ p: CGPoint) -> Bool {
        guard worldBounds.width > 0 else { return false }
        let outer = worldBounds.insetBy(dx: borderOuterPadding, dy: borderOuterPadding)
        let inner = worldBounds.insetBy(dx: borderBandWidth + borderOuterPadding,
                                        dy: borderBandWidth + borderOuterPadding)
        return outer.contains(p) && !inner.contains(p)
    }
    
    @inline(__always)
    private func rectFullyInBorderBand(_ r: CGRect) -> Bool {
        guard worldBounds.width > 0 else { return false }
        let outer = worldBounds.insetBy(dx: borderOuterPadding, dy: borderOuterPadding)
        let inner = worldBounds.insetBy(dx: borderBandWidth + borderOuterPadding,
                                        dy: borderBandWidth + borderOuterPadding)
        // Entire rect must sit inside the border (no overlap with interior)
        return outer.contains(r) && !r.intersects(inner)
    }
    
    // ==== Obstacle placement ====
    private let obstacleCell: CGFloat = 380
    private let obstacleEdgeMargin: CGFloat = 160
    private let obstacleKeepOutFromCar: CGFloat = 300
    private let obstacleClearanceMajor: CGFloat = 80
    private let minNeighborSpacing: CGFloat = 320
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
    private let gameOverOverlay = GameOverOverlayNode()
    private let winOverlay = WinOverlayNode()
    
    private var minZoom: CGFloat = 1.34
    private var maxZoom: CGFloat = 2.4
    private var pinchGR: UIPinchGestureRecognizer?
    private var pinchStartScale: CGFloat = 1.34
    
    // ==== Controls / Handedness ====
    private var isLeftHanded = true
    private var controlsLockedForOverlay = false
    private var handednessOverlay: HandChoiceOverlayNode?
    private var didPickHand = false
    
    // ==== Death freeze / pause ====
    private var cameraFrozenPos: CGPoint?         // freeze camera here while dead
    private var pausedForDeath = false            // NEW
    
    private let strictCentering = true
    
    // MARK: - Enemy-seeded obstacles
    private var enemyObstacleCooldown: TimeInterval = 2.4           // seconds between seed attempts per enemy
    private var enemyObstacleTravelReq: CGFloat = 420               // min travel since last seed
    private var enemyObstacleMaxPerEnemy: Int = 20                  // hard cap per enemy (per life)
    private var enemyObstacleState: [ObjectIdentifier:(lastT: TimeInterval, lastPos: CGPoint, count: Int)] = [:]
    
    // Camera follow target (defaults to player)
    private weak var cameraTarget: CarNode?
    private var cameraFollowLerp: CGFloat = 0.20
    private var followedEnemyIndex: Int?   // if following an enemy, keep its index
    private var lastUpdateTime: TimeInterval = 0
    private var prevSpeed: CGFloat = 0
    
    // Loosen spawn region for terrain (ON by default so you see them again)
    private let hillsBorderOnly: Bool = false
    private let rampsBorderOnly: Bool = false
    
    // === Ion Void FX (outside world) =============================================
    private let voidFXRoot = SKNode()
    private var voidSprite: SKSpriteNode?
    private var voidTime: Float = 0
    
    private var rlServerEnemy: RLServer?   // replaces old rlServer
    private var rlServerPlayer: RLServer?
    
    // Keep a handle to the time uniform so we can update it every frame
    private var voidTimeUniform = SKUniform(name: "u_time", float: 0)
    
    private var playerIsAIControlled: Bool { aiControlsPlayer || rlControlsPlayer }
    
    private let aiAutoRestartDelay: TimeInterval = 0.5
    
    // Cones are small: give them lighter rules
    private let coneNeighborSpacing: CGFloat = 140      // used for per-cone spacing
    private let coneLocalClearance: CGFloat = 22        // physics clearance radius per cone
    private let coneRowChainGuard: CGFloat = 360        // don’t chain rows too tightly in one chunk
    private let coneSpacing: CGFloat = 32
    private let coneCountRange = 4...6
    private let coneRowChance: CGFloat = 0.30           // was 0.16
    private let coneSingleChance: CGFloat = 0.22        // NEW: chance to scatter a single cone
    
    private var fightLevel: CGFloat = 0              // smoothed combat level
    private var fightHoldUntil: TimeInterval = 0     // keep “combat” for a short hold
    private var fightWasCombat = false
    private let fightEnterThreshold: CGFloat = 0.22  // start combat when > this
    private let fightExitThreshold: CGFloat  = 0.08  // end combat when < this (hysteresis)
    
    private let groundRoot = SKNode()   // ground decals (holes, skidmarks, etc.)
    
    private let wormRoot = SKNode()
    
    private var wormCategoryMask: UInt32 {
        var m: UInt32 = 0
        if Category.wormHead != 0 { m |= Category.wormHead }
        if Category.wormBody != 0 { m |= Category.wormBody }
        return m
    }

    @inline(__always)
    private func isWormNode(_ n: SKNode) -> Bool {
        // Prefer category check; fall back to name in case categories are 0
        if let pb = n.physicsBody, (pb.categoryBitMask & wormCategoryMask) != 0 { return true }
        return (n.name?.contains("worm.segment") == true)
    }
    
    private var training: Bool = true // false
    
    // --- Training state ---
    var rlPrevHP: Int = 0
    var rlEpisodeStep: Int = 0
    let rlMaxSteps: Int = 1200   // ~20s at 60Hz
    
    func logWiFiIP() {
        var addr: String?
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        if getifaddrs(&ifaddr) == 0 {
            var p = ifaddr
            while p != nil {
                let i = p!.pointee
                if i.ifa_addr.pointee.sa_family == UInt8(AF_INET),
                   let name = String(validatingUTF8: i.ifa_name), name == "en0" {
                    var a = i.ifa_addr.pointee
                    var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    getnameinfo(&a, socklen_t(i.ifa_addr.pointee.sa_len),
                                &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST)
                    addr = String(cString: host)
                }
                p = i.ifa_next
            }
            freeifaddrs(ifaddr)
        }
        print("📡 Device IP:", addr ?? "unknown")
    }
    
    
    var cars: [CarNode] = []   // includes the player car
    private var voidWaves: SKNode?
    
    private func pauseWorldForDeath() {           // NEW
        guard !pausedForDeath else { return }
        
        Audio.shared.updateFight(intensity: 0, at: car.position, now: CACurrentMediaTime())
        fightLevel = 0
        fightHoldUntil = 0
        fightWasCombat = false
        
        pausedForDeath = true
        
        // stop inputs
        driveTouch = nil
        fireTouch = nil
        refreshControlActiveFlags()
        isTouching = false
        controlArmed = false
        car.stopAutoFire()
        hideRing()
        
        // freeze simulation
        physicsWorld.speed = 0
        
        // pause node trees that animate
        openWorld?.isPaused = true
        obstacleRoot.isPaused = true
        
        // optional: quiet HUD motion
        speedHUD.isPaused = true
        headingHUD.isPaused = true
        rampPointer.isPaused = true
    }
    
    private func buildIonVoidFX() {
        guard worldBounds.width > 0 && worldBounds.height > 0 else { return }
        
        voidFXRoot.removeAllChildren()
        if voidFXRoot.parent == nil {
            voidFXRoot.zPosition = -50
            addChild(voidFXRoot)
        }
        
        // Massive cover so it always reaches the screen edges
        let coverSide: CGFloat = 100_000
        let sprite = SKSpriteNode(
            color: UIColor(red: 0.0000, green: 0.1020, blue: 0.2000, alpha: 0.8),
            size: .init(width: coverSide, height: coverSide)
        )
        sprite.position = CGPoint(x: worldBounds.midX, y: worldBounds.midY)
        sprite.anchorPoint = .init(x: 0.5, y: 0.5)
        sprite.blendMode = .alpha
        sprite.alpha = 1.0
        sprite.zPosition = -50
        voidFXRoot.addChild(sprite)
        voidSprite = sprite
        
        // 🔹 Waves shader (centered on the sprite, i.e., camera)
        let src = """
        uniform float u_time
        uniform float u_speed
        uniform float u_freq
        uniform float u_alpha
        void main() {
            vec2 uv = v_tex_coord;          // 0..1 across the quad
            vec2 p  = uv - 0.5;             // center
            float r = length(p)
            float phase = r * u_freq - u_time * u_speed
            // Thin ring highlights (no derivatives needed)
            float c = cos(phase)
            float rings = smoothstep(0.96, 1.0, abs(c));   // bright near crests
        
            // Diagonal layer to break symmetry
            float d = (uv.x + uv.y - 1.0) * (u_freq * 0.6) - u_time * (u_speed * 1.2)
            float diag = smoothstep(0.96, 1.0, abs(cos(d)))
            // Combine and clamp
            float glow = clamp(rings * 0.85 + diag * 0.45, 0.0, 1.0)
            // Base teal + bright teal accents
            vec3 base   = vec3(0.0, 0.1020, 0.2000)
            vec3 accent = vec3(0.0, 0.65, 0.75)
            vec3 col = mix(base, accent, glow * 0.70);     // up to +70% tint
        
            // Gentle center-focused vignette to emphasize waves
            float vign = smoothstep(0.9, 0.2, r);          // center ~1, edges darker
            col *= mix(0.60, 1.0, vign)
            // Slight alpha pulse so you *see* motion even on dark screens
            float a = u_alpha * (0.88 + 0.12 * sin(phase))
            gl_FragColor = vec4(col, a)
        }
        """
        
        let shader = SKShader(source: src)
        shader.uniforms = [
            voidTimeUniform,                        // you already advance this each frame
            SKUniform(name: "u_speed", float: 1.5), // ↑ faster = 1.2–1.6, slower = 0.5–0.8
            SKUniform(name: "u_freq",  float: 40.0),// ↑ more rings = 34–48, fewer = 18–26
            SKUniform(name: "u_alpha", float: 0.95) // overall opacity
        ]
        sprite.shader = shader
        
        // Optional neon outline at the edge of the world (unchanged)
        let outline = SKShapeNode(rect: worldBounds)
        outline.strokeColor = UIColor.systemTeal.withAlphaComponent(0.40)
        outline.glowWidth = 18
        outline.lineWidth = 2
        outline.fillColor = .clear
        outline.zPosition = -49
        voidFXRoot.addChild(outline)
    }
    
    private func scheduleAutoRestartIfAIControlled(delay: TimeInterval = 1.2) {
        // Only auto-restart when the player is AI-driven
        guard aiControlsPlayer || rlControlsPlayer else { return }
        // Avoid multiple queued restarts
        removeAction(forKey: "autoRestart")
        let restart = SKAction.run { [weak self] in
            guard let self = self else { return }
            self.gameOverOverlay.hide()
            self.winOverlay.hide()
            self.restartRound()
        }
        run(.sequence([.wait(forDuration: delay), restart]), withKey: "autoRestart")
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
    
    private func detectCarColor(of car: SKNode) -> UIColor {
        // Prefer the body chassis (zPosition == 2)
        var result: UIColor?
        func visit(_ n: SKNode) {
            if let sh = n as? SKShapeNode, sh.zPosition == 2, result == nil {
                result = sh.fillColor
            }
            for c in n.children where result == nil { visit(c) }
        }
        visit(car)
        return result ?? .systemRed
    }
    
    private func setZoom(_ z: CGFloat, forceStreamRefresh: Bool = false) {
        let s = clamp(z, minZoom, maxZoom)
        camera?.setScale(s)
        if forceStreamRefresh { refreshObstacleStreaming(force: true) }
    }
    
    func spawnEnemy(at p: CGPoint) -> CarNode {
        let enemy = spawnCar(kind: .enemy, at: p, target: car)
        
        let playerColor = detectCarColor(of: car)
        let color = randomDistinctColor(avoid: playerColor)
        tintCar(enemy, to: color)
        
        return enemy
    }
    
    @discardableResult
    func spawnCar(kind: CarNode.Kind,
                  at position: CGPoint? = nil,
                  target: CarNode? = nil) -> CarNode {
        let c = CarNode()
        c.position = position ?? safeSpawnPoint(in: cameraWorldRect(margin: 400).insetBy(dx: 120, dy: 120),
                                                radius: spawnClearance)
        c.delegate = self
        c.configure(kind: kind, target: target)
        c.enableCrashContacts()
        addChild(c)
        cars.append(c)
        return c
    }
    
    // MARK: - Scene lifecycle
    override func didMove(to view: SKView) {
        backgroundColor = .black
        physicsWorld.contactDelegate = self
        view.isMultipleTouchEnabled = true
        
        car.aiControl = aiControlsPlayer
        
        startOnboardingFlowTutorialFirst()
        
        Audio.shared.playMusic(names: ["ambient_loop"], crossfade: 2.5)
        
        logWiFiIP()
        
        // World
        let scalar: CGFloat = 100.0 // map size //
        let worldSize = CGSize(width: size.width * scalar, height: size.height * scalar)
        let world = OpenWorldNode(config: .init(size: worldSize))
        addChild(world)
        openWorld = world
        
        worldBounds = CGRect(x: -worldSize.width * 0.5,
                             y: -worldSize.height * 0.5,
                             width: worldSize.width,
                             height: worldSize.height)
        
        buildIonVoidFX()
        
        groundRoot.zPosition = 0.35     // below the car & obstacles
        addChild(groundRoot)
        
        // Car
        let searchRect = frame.insetBy(dx: 160, dy: 160)
        car.position = safeSpawnPoint(in: searchRect, radius: spawnClearance)
        car.zRotation = 0
        addChild(car)
        car.enableAirPhysics()
        car.delegate = self
        
        cars = [car]
        
        // Streaming root
        worldSeed = UInt64.random(in: 1...UInt64.max)
        obstacleRoot.zPosition = 1
        addChild(obstacleRoot)
        refreshObstacleStreaming(force: true)
        
        wormRoot.zPosition = 3.0   // above car (≈2) & obstacles (≈2)
        addChild(wormRoot)
        
        // Camera
        let cam = SKCameraNode()
        camera = cam
        addChild(cam)
        cam.position = car.position
        
        setZoom(minZoom, forceStreamRefresh: true)
        
        // ⬇️ Start at MAX ZOOM OUT and enable pinch zoom
        pinchGR = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
        pinchGR?.delegate = self          // ← add this
        view.addGestureRecognizer(pinchGR!)
        
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
        updateEnemyBlipOnHeadingHUD()
        cam.addChild(headingHUD)
        // Ensure the CarNode-owned enhancement UI is shown
        
        kmhMaxShown = car.maxSpeed * kmhPerPointPerSecond
        
        // Ramp pointer HUD (puck)
        buildRampArrowHUD()
        
        // Fire button
        buildFireButton()
        cam.addChild(fireButton)
        placeFireButton()
        
        // DRIVE button — NEW
        buildDriveButton()
        cam.addChild(driveButton)
        placeDriveButton()
        
        // Health HUD
        camera?.addChild(healthHUD)
        placeHUD()
        
        // When HP changes (including after shield-only hits, because we call onHPChanged above)
        // HP changes → update both HUDs
        car.onHPChanged = { [weak self] hp, max in
            guard let self else { return }
            self.updateHealthHUD() // your existing top-left HUD
        }
        
        // Lives changes → update both HUDs
        car.onLivesChanged = { [weak self] lives, max in
            guard let self else { return }
            self.healthHUD.setLives(left: lives, max: max)    // existing
        }
        
        // Initial draw (keep these after you set closures)
        car.onHPChanged?(car.hp, car.maxHP)
        healthHUD.setLives(left: car.livesLeft, max: car.maxLives)
        
        // Show handedness overlay EVERY time app opens (but don't block controls)
        if !didPickHand && !aiControlsPlayer && UserDefaults.standard.bool(forKey: OnboardKeys.finishedTutorial) {
            showHandednessPicker()
        } else {
            processStreamQueues()
        }
        // After: let cam = SKCameraNode(); camera = cam; addChild(cam)
        cam.addChild(gameOverOverlay)
        cam.addChild(winOverlay)
        
        // Restart handler (player lost)
        gameOverOverlay.onRestart = { [weak self] in
            guard let self = self else { return }
            self.gameOverOverlay.hide()
            self.restartRound()      // see helper below
        }
        
        // Restart handler (player won)
        winOverlay.onRestart = { [weak self] in
            guard let self = self else { return }
            self.winOverlay.hide()
            self.restartRound()
        }
        
        for _ in 0..<1 {
            let p = safeSpawnPoint(in: cameraWorldRect(margin: 500).insetBy(dx: 150, dy: 150),
                                   radius: spawnClearance)
            _ = spawnEnemy(at: p)
        }
        
        let agent  = cars.first { $0.kind == .enemy }!
        let target = cars.first { $0.kind == .player }!
        
        car.configure(kind: .player, target: target)
        
        self.rlAgentCar = agent
        self.rlTargetCar = target
        
        cameraTarget = agent
        
        startAIControl(aiControlsPlayer, training: training)
        
        followPlayer()
        updateCameraFollow(dt: 0)
    }
    
    // MARK: - Camera follow API
    
    private func updateCameraFollow(dt: CGFloat) {
        guard let cam = camera else { return }
        let targetNode = cameraTarget ?? car
        let dest = targetNode.position
        let pos = cam.position
        let t = cameraFollowLerp
        cam.position = CGPoint(x: pos.x + (dest.x - pos.x) * t,
                               y: pos.y + (dest.y - pos.y) * t)
    }
    
    // MARK: Worm + hole
    private var holeForWorm: [ObjectIdentifier: SKNode] = [:]
    // How far a hole must stay away from other things
    // Keep holes away from stuff, but never fail to place one.
    private let holeClearance: CGFloat = 84
    
    private func findSafeHolePositionSpiral(
        from origin: CGPoint,
        step: CGFloat,
        maxRadius: CGFloat,
        samplesPerRing: Int,
        avoidMask: UInt32,
        withinAnnulus: ClosedRange<CGFloat>? = nil
    ) -> CGPoint? {
        var r = step
        while r <= maxRadius {
            for i in 0..<samplesPerRing {
                let a = (CGFloat(i) / CGFloat(samplesPerRing)) * (.pi * 2)
                let cand = CGPoint(x: origin.x + cos(a) * r, y: origin.y + sin(a) * r)
                guard worldBounds.contains(cand) else { continue }
                
                if let ann = withinAnnulus {
                    let d = origin.distance(to: cand)
                    if d < ann.lowerBound || d > ann.upperBound { continue }
                }
                
                let box = CGRect(x: cand.x - holeClearance - 12,
                                 y: cand.y - holeClearance - 12,
                                 width: (holeClearance + 12) * 2,
                                 height: (holeClearance + 12) * 2)
                
                if clearanceOK(at: cand, radius: holeClearance, mask: avoidMask) &&
                    !circleIntersectsAny(center: cand, radius: holeClearance, rects: gatherSpawnBlockers(in: box)) {
                    return cand
                }
            }
            r += step
        }
        return nil
    }
    
    private func spawnWormFromHole(at pScene: CGPoint) {
        // 🔁 find an existing hole at this scene point (±3 pts)
        var hole: SKNode?
        groundRoot.enumerateChildNodes(withName: "worm.hole") { n, stop in
            let p = self.convert(n.position, from: self.groundRoot)
            if hypot(p.x - pScene.x, p.y - pScene.y) < 3 {
                hole = n; stop.pointee = true
            }
        }
        if hole == nil {
            hole = spawnHole(at: pScene, ttl: 10.0) // fallback if none
        }
        
        // mark occupied so we don't double-spawn
        if hole?.userData == nil { hole?.userData = NSMutableDictionary() }
        hole?.userData?["occupied"] = true
        
        // place the worm exactly at the hole (scene space)
        let startInScene = self.convert(hole!.position, from: groundRoot)
        
        let w = WormNode.spawn(in: self, at: startInScene, toward: car)  // ← builds segments
        w.zPosition = 2.0
        w.moveSpeed = 110
        w.turnRate  = .pi * 0.75
        worms.append(w)
        
        holeForWorm[ObjectIdentifier(w)] = hole!
        
        w.alpha = 0
        w.run(.sequence([
            .group([.fadeIn(withDuration: 0.18), .scale(to: 1.06, duration: 0.18)]),
            .scale(to: 1.0, duration: 0.10)
        ]))
        
        w.onRemoved = { [weak self, weak w] in
            guard let self, let w = w else { return }
            if let hole = self.holeForWorm.removeValue(forKey: ObjectIdentifier(w)) {
                hole.run(.sequence([.fadeOut(withDuration: 0.18), .removeFromParent()]))
            }
        }
    }
    
    func followPlayer() {
        cameraTarget = car
        followedEnemyIndex = nil
    }
    
    func followEnemy(at index: Int) {
        let enemies = cars.filter({ $0.kind == .enemy })
        guard enemies.indices.contains(index) else { return }
        cameraTarget = enemies[index]
        followedEnemyIndex = index
    }
    
    // Convenience: cycle Player -> Enemy0 -> Enemy1 -> ... -> Player
    func cycleCameraTarget() {
        let enemies = cars.filter({ $0.kind == .enemy })
        if let i = followedEnemyIndex {
            let next = i + 1
            if enemies.indices.contains(next) {
                followEnemy(at: next)
            } else {
                followPlayer()
            }
        } else {
            if enemies.indices.contains(0) {
                followEnemy(at: 0)
            }
        }
    }
    
    
    // GameScene.swift
    private func hasLineOfSight(from a: CarNode, to b: CarNode) -> Bool {
        let start = a.position, end = b.position
        var result = false
        physicsWorld.enumerateBodies(alongRayStart: start, end: end) { body, _, _, stop in
            guard let n = body.node else { return }
            if n === b || n.inParentHierarchy(b) { result = true; stop.pointee = true; return }
            let cat = body.categoryBitMask
            let blockerMask: UInt32 = Category.wall | Category.obstacle | Category.hole | Category.ramp | Category.hill | self.wormCategoryMask
            if (cat & blockerMask) != 0 {
                result = false; stop.pointee = true; return
            }
        }
        return result
    }

    // MARK: Worm head separation (soft repulsion)
    private func applyWormHeadSeparation(dt: CGFloat) {
        // Collect all live worm heads
        let activeWorms = worms.filter { $0.parent != nil }
        var heads: [WormSegmentNode] = []
        for w in activeWorms {
            if let h = w.segments.first { heads.append(h) }
        }

        let minGap: CGFloat =  (heads.first?.frame.width ?? 60) * 0.9 + 16  // ≈ radius*2 + pad
        let kPush: CGFloat = 220.0                                          // force scale

        for i in 0..<heads.count {
            guard let aPB = heads[i].physicsBody else { continue }
            let pa = heads[i].convert(CGPoint.zero, to: self)
            for j in (i+1)..<heads.count {
                guard let bPB = heads[j].physicsBody else { continue }
                let pb = heads[j].convert(CGPoint.zero, to: self)

                let dx = pb.x - pa.x, dy = pb.y - pa.y
                let d  = max(0.001, hypot(dx, dy))
                if d < minGap {
                    let nx = dx / d, ny = dy / d
                    let push = (minGap - d) * kPush
                    aPB.applyForce(CGVector(dx: -nx * push, dy: -ny * push))
                    bPB.applyForce(CGVector(dx:  nx * push, dy:  ny * push))
                }
            }
        }
    }
    
    private func lineOfSightOrBlocker(from a: CarNode, to b: CarNode) -> (los: Bool, blocker: SKNode?) {
        let start = a.position, end = b.position
        var los = false
        var blocker: SKNode?
        physicsWorld.enumerateBodies(alongRayStart: start, end: end) { body, _, _, stop in
            guard let n = body.node else { return }
            if n === b || n.inParentHierarchy(b) { los = true; stop.pointee = true; return }
            let cat = body.categoryBitMask
            let blockerMask: UInt32 = Category.wall | Category.obstacle | Category.hole | Category.ramp | Category.hill | self.wormCategoryMask
            if (cat & blockerMask) != 0 {
                blocker = n; stop.pointee = true; return
            }
        }
        return (los, blocker)
    }
    
    /// Heuristic guard the AI can ask before firing.
    func aiShouldFire(shooter: CarNode, at target: CarNode) -> Bool {
        let los   = hasLineOfSight(from: shooter, to: target)
        let aim   = aimAlignment(from: shooter, to: target) > 0.85
        let dist  = shooter.position.distance(to: target.position)
        let distOK = (dist >= 160 && dist <= 1100)
        return los && aim && distOK
    }
    
    // 1.0 = perfectly aimed at target, 0 = 90° off, -1 = opposite direction
    private func aimAlignment(from a: CarNode, to b: CarNode) -> CGFloat {
        let heading = a.zRotation + .pi/2
        let dir = atan2(b.position.y - a.position.y, b.position.x - a.position.x)
        let err = shortestAngle(from: heading, to: dir)
        return cos(err)
    }
    
    // MARK: - AI obstacle awareness & tactical fire
    
    private var aiBurstLockout: [ObjectIdentifier: TimeInterval] = [:]
    
    @inline(__always)
    private func isDestructibleObstacleNode(_ n: SKNode) -> Bool {
        // Treat any obstacle that isn't explicitly marked non-destructible or "steel" as fair game
        if isWormNode(n) { return true }
        // Existing rules for map obstacles
        if let d = n.userData?["destructible"] as? Bool, d == false { return false }
        if let name = n.name?.lowercased(), name.contains("steel") { return false }
        return true
    }
    
    private func firstObstacleAheadInCone(for shooter: CarNode,
                                          maxDist: CGFloat = 520,
                                          halfAngle: CGFloat = .pi/8) -> SKNode? {
        let origin = shooter.position
        let heading = shooter.zRotation + .pi/2
        let dir = CGVector(dx: cos(heading), dy: sin(heading))
        
        var closest: (n: SKNode, d: CGFloat)? = nil
        
        // Use a coarse sweep: a few rays in the cone + a small AABB probe
        let rays = [-halfAngle * 0.6, 0, halfAngle * 0.6]
        for off in rays {
            let a = heading + off
            let end = CGPoint(x: origin.x + cos(a) * maxDist, y: origin.y + sin(a) * maxDist)
            physicsWorld.enumerateBodies(alongRayStart: origin, end: end) { [weak self] body, p, _, stop in
                guard let self, let n = body.node else { return }
                if (body.categoryBitMask & (Category.obstacle | self.wormCategoryMask)) != 0,
                   self.isDestructibleObstacleNode(n) == true {
                    let d = hypot(p.x - origin.x, p.y - origin.y)
                    if closest == nil || d < closest!.d { closest = (n, d) }
                    stop.pointee = true
                    return
                }
                if (body.categoryBitMask & (Category.wall | Category.ramp | Category.hole)) != 0 {
                    stop.pointee = true
                    return
                }
            }
        }
        
        // Extra: local box in front (helps for very near obstacles)
        let probeW: CGFloat = 90
        let probeL: CGFloat = min(maxDist, 180)
        let center = CGPoint(x: origin.x + dir.dx * (probeL * 0.5),
                             y: origin.y + dir.dy * (probeL * 0.5))
        let box = CGRect(x: center.x - probeW/2, y: center.y - probeW/2, width: probeW, height: probeL)
        physicsWorld.enumerateBodies(in: box) { [weak self] body, _ in
            guard let self, let n = body.node else { return }
            if (body.categoryBitMask & (Category.obstacle | wormCategoryMask)) != 0,
               self.isDestructibleObstacleNode(n) == true {
                let d = shooter.position.distance(to: n.position)
                if closest == nil || d < closest!.d { closest = (n, d) }
            }
        }
        
        return closest?.n
    }
    
    private func fireBurst(_ car: CarNode, duration: TimeInterval = 0.18) {
        // Start auto-fire briefly to clear geometry
        car.startAutoFire(on: self)
        car.run(.sequence([
            .wait(forDuration: duration),
            .run { [weak car] in car?.stopAutoFire() }
        ]))
    }
    
    private func aiTacticalFireIfNeeded(shooter: CarNode, target: CarNode) {
        let now = CACurrentMediaTime()
        let key = ObjectIdentifier(shooter)
        if let lock = aiBurstLockout[key], now < lock { return }
        
        // (1) If LoS to target → standard aim/LoS rule (keeps your PvP behavior)
        let (los, blocker) = lineOfSightOrBlocker(from: shooter, to: target)
        if los {
            if aimAlignment(from: shooter, to: target) > 0.85 {
                // short controlled puff to avoid perma-firing
                fireBurst(shooter, duration: 0.16)
                aiBurstLockout[key] = now + 0.20
            }
            return
        }
        
        // (2) If LoS is blocked by a destructible obstacle → clear it
        if let n = blocker, isDestructibleObstacleNode(n) {
            fireBurst(shooter, duration: 0.22)
            aiBurstLockout[key] = now + 0.28
            return
        }
        
        // (3) No target LoS: proactively clear obstacle straight ahead (path opening)
        if let _ = firstObstacleAheadInCone(for: shooter, maxDist: 520, halfAngle: .pi/10) {
            fireBurst(shooter, duration: 0.18)
            aiBurstLockout[key] = now + 0.24
            return
        }
    }
    
    private func restartRound() {
        removeAction(forKey: "autoRestart")
        // Hide overlays if still up
        gameOverOverlay.hide()
        winOverlay.hide()
        
        // Choose a safe spawn in the current camera area
        let spawn = safeSpawnPoint(in: cameraWorldRect(margin: 400).insetBy(dx: 120, dy: 120),
                                   radius: spawnClearance)
        
        // Reset player
        car.restartAfterGameOver(at: spawn)
        
        // Despawn existing enemies
        for e in cars where e !== car {
            let p = safeSpawnPoint(in: cameraWorldRect(margin: 500).insetBy(dx: 150, dy: 150),
                                   radius: spawnClearance)
            e.restartAfterGameOver(at: p)
        }
        
        Audio.shared.updateFight(intensity: 0, at: car.position, now: CACurrentMediaTime())
        fightLevel = 0
        fightHoldUntil = 0
        fightWasCombat = false
        
        cameraFrozenPos = nil
        resumeWorldAfterRespawn()
    }
    
    func showHandednessPicker() {
        controlsLockedForOverlay = false
        let ov = HandChoiceOverlayNode(size: size)
        handednessOverlay = ov
        camera?.addChild(ov)
        ov.onPick = { [weak self] left in
            guard let self = self else { return }
            self.isLeftHanded = left
            self.placeDriveButton()
            self.placeFireButton()
            self.didPickHand = true
            self.onboardingState = .done
            processStreamQueues()
        }
    }
    
    override func didChangeSize(_ oldSize: CGSize) {
        super.didChangeSize(oldSize)
        buildIonVoidFX()
        placeHUD()
        placeFireButton()
        placeDriveButton()
        handednessOverlay?.updateSize(size)
    }
    
    @objc private func handlePinch(_ gr: UIPinchGestureRecognizer) {
        if isAnyControlActive {
            if gr.state == .changed { gr.scale = 1 }
            return
        }
        guard let cam = camera, view != nil else { return }
        switch gr.state {
        case .began:
            pinchStartScale = cam.xScale
        case .changed, .ended:
            setZoom(pinchStartScale / max(gr.scale, 0.001),
                    forceStreamRefresh: gr.state == .ended)
            // minimal: re-place UI so safe-area offsets match new zoom
            placeHUD(); placeFireButton(); placeDriveButton()
        default: break
        }
    }
    
    func gestureRecognizerShouldBegin(_ g: UIGestureRecognizer) -> Bool {
        if g === pinchGR { return !isAnyControlActive }
        return true
    }
    
    func gestureRecognizer(_ g: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        return false
    }
    
    private var moveControlActive = false
    private var fireControlActive = false
    private var isAnyControlActive: Bool { moveControlActive || fireControlActive }
    
    private func refreshControlActiveFlags() {
        // Drive is active while the move touch is down (ring shown) or we’re in the legacy “car touch” mode.
        moveControlActive = (driveTouch != nil) || (isTouching && controlArmed)
        fireControlActive = (fireTouch != nil)
    }
    
    override func willMove(from view: SKView) {
        super.willMove(from: view)
        Audio.shared.updateEngine(run: false, normalized: 0)
        enemyRLServer?.stop(); enemyRLServer = nil
        playerRLServer?.stop(); playerRLServer = nil
        if let g = pinchGR { view.removeGestureRecognizer(g) }
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
    
    // Convert UIKit safeAreaInsets → camera-space points
    private func safeInsetsInCamera() -> UIEdgeInsets {
        guard let v = view, let cam = camera else { return .zero }
        let s = max(cam.xScale, 0.001)         // camera children scale with xScale
        let i = v.safeAreaInsets
        return UIEdgeInsets(top: i.top / s, left: i.left / s,
                            bottom: i.bottom / s, right: i.right / s)
    }
    
    // Centered between speedHUD and headingHUD (X only); Y stays aligned to speedHUD row.
    func addRLEnemyToggleBetween(speedNode: SKNode, headingNode: SKNode) {
        toggle?.removeFromParent()
        let parent = (speedNode.parent ?? camera ?? self)
        toggle = RLCardToggle()
        toggle?.isOn = training
        toggle?.name = "hud.rlToggle"
        parent.addChild(toggle!)
        
        // wherever you set the toggle callback
        toggle?.onChanged = { [weak self] isOn in
            guard let self else { return }
            Task {
                do {
                    if isOn {
                        let host = NetworkUtils.currentWiFiIP() ?? "0.0.0.0" // LAN dev; for WAN see note below
                        try await TrainingService.start(host: host, port: 5556, name: "enemy")
                    } else {
                        try await TrainingService.stop(name: "enemy")
                    }
                } catch {
                    print("train toggle backend error:", error)
                }
            }
            training = isOn
            self.bindRLServers(train: isOn)
        }
        
        // X midpoint between speed & heading; Y aligned to speed row
        let xMid = (speedNode.position.x + headingNode.position.x) * 0.5
        toggle?.position = CGPoint(x: xMid, y: speedNode.position.y)
        
        // Keep visual in sync if state changed elsewhere
    }
    
    private func placeHUD() {
        let inset = safeInsetsInCamera()
        let margin: CGFloat = 16
        let drop: CGFloat   = 4
        let halfW = speedCard.frame.width  * 0.5
        let halfH = speedCard.frame.height * 0.5
        
        // Top-left (Speed)
        speedHUD.position = CGPoint(
            x: -size.width * 0.5 + inset.left + margin + halfW + 10,
            y:  size.height * 0.5  - (margin + drop) - halfH
        )
        
        // Top-right (Heading)
        let r = headingSize * 0.5
        headingHUD.position = CGPoint(
            x:  size.width * 0.5 - inset.right - margin - r - 5,
            y:  size.height * 0.5 - (margin + drop) - r
        )
        
        // Health
        healthHUD.position = CGPoint(
            x: -size.width * 0.5 + inset.left + margin + 90,
            y:  size.height * 0.5 - (margin + drop) - speedCard.frame.height - 38
        )
        
#if DEBUG
        addRLEnemyToggleBetween(speedNode: speedHUD, headingNode: headingHUD)
#endif
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
        
        let br: CGFloat = 5
        enemyBlip.path = CGPath(ellipseIn: CGRect(x: -br, y: -br, width: br, height: br), transform: nil)
        enemyBlip.fillColor = UIColor.systemRed.withAlphaComponent(0.95)
        enemyBlip.strokeColor = UIColor.white.withAlphaComponent(0.35)
        enemyBlip.lineWidth = 1.5
        enemyBlip.zPosition = 2
        enemyBlip.isHidden = true
        headingHUD.addChild(enemyBlip)
    }
    
    private func updateEnemyBlipOnHeadingHUD() {
        guard let cam = camera else { return }
        
        // pick nearest enemy that is off-screen but within range
        let viewRect = cameraViewRect.insetBy(dx: enemyBlipScreenMargin, dy: enemyBlipScreenMargin)
        let myPos = car.position
        var best: (node: CarNode, dist: CGFloat)?
        
        for e in cars where e.kind == .enemy && !e.isDead {
            let d = myPos.distance(to: e.position)
            if d >= enemyBlipMaxDistance { continue }
            let eCam = cam.convert(e.position, from: self)
            if viewRect.contains(eCam) { continue } // on-screen → no blip
            if best == nil || d < best!.dist { best = (e, d) }
        }
        
        guard let enemy = best?.node else {
            if !enemyBlip.isHidden {
                enemyBlip.removeAction(forKey: "blink")
                enemyBlip.run(.sequence([.fadeOut(withDuration: 0.12), .hide()]))
            }
            return
        }
        
        // place the dot on the compass rim at the absolute bearing to the enemy
        let a = atan2(enemy.position.y - myPos.y, enemy.position.x - myPos.x) // world bearing to enemy
        let r = (headingSize * 0.5) - 12                                      // just inside the dial
        enemyBlip.position = CGPoint(x: cos(a) * r, y: sin(a) * r)
        
        // color intensity by proximity (optional)
        let t = max(0, 1 - (best!.dist / enemyBlipMaxDistance))
        enemyBlip.fillColor = UIColor.systemRed.withAlphaComponent(0.65 + 0.35 * t)
        
        // show & blink
        if enemyBlip.isHidden {
            enemyBlip.alpha = 0
            enemyBlip.isHidden = false
            enemyBlip.run(.fadeAlpha(to: 1.0, duration: 0.12))
        }
        if enemyBlip.action(forKey: "blink") == nil {
            let up = SKAction.fadeAlpha(to: 1.0, duration: 0.30)
            let dn = SKAction.fadeAlpha(to: 0.35, duration: 0.30)
            enemyBlip.run(.repeatForever(.sequence([up, dn])), withKey: "blink")
        }
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
    
    private func recenterCameraOnTargetIfNeeded() {
        guard let cam = camera else { return }
        let t = cameraTarget ?? car
        cam.removeAllActions()
        cam.position = t.position
    }
    
    // GameScene.swift
    override func didSimulatePhysics() {
        super.didSimulatePhysics()
        
        // Keep Ion Void FX centered on camera
        if let cam = camera {
            if let s = voidSprite {
                s.position = cam.position
                if let u = s.shader?.uniformNamed("u_center") {
                    u.vectorFloat2Value = .init(Float(cam.position.x), Float(cam.position.y))
                }
            }
            // If you added the non-shader rings:
            voidWaves?.position = cam.position
        }
        
        // Always clear this flag, even on early returns
        defer { _hadSolidContactThisStep = false }
        
        // Freeze camera hard while dead; unfreeze on respawn path elsewhere
        if cameraFrozenPos != nil { return }
        
        // Skip recentring on a solid-contact correction step
        if _hadSolidContactThisStep { return }
        
        // Optional (your no-op helper)
        applyHillEdgeAssist(dt: CGFloat(_lastDTForClamp))
        
        // Normal recentering
        recenterCameraOnTargetIfNeeded()
        syncOnboardingUIWithCamera()
    }
    
    // Keep as an empty hook (or remove call above entirely)
    private func applyHillEdgeAssist(dt: CGFloat) { }
    
    @inline(__always)
    private func applyHillBottomOneWayGuard(dt: CGFloat) {
        // Only on ground, only if we have physics
        guard !car.isAirborne, let pb = car.physicsBody else { return }
        
        // ---- Tunables (adjust to taste) ----
        let outerBand: CGFloat   = 1.035   // r just outside the ellipse edge
        let blockOuter: CGFloat  = 1.08    // how far outside we still block inward entry
        let maxAccelPS: CGFloat  = 2200.0  // max outward speed change per second
        let tinyBias: CGFloat    = 60.0    // small outward bias when blocking entry
        let ghTol: CGFloat       = 10.0    // only treat as “bottom” when ground is ~flat (near 0)
        
        let p = car.position
        
        // Find the closest hill edge (r ≈ 1) around us where ground is low
        var best: (r: CGFloat, cx: CGFloat, cy: CGFloat, rx: CGFloat, ry: CGFloat)?
        for hill in hills where hill.parent != nil {
            let f = hill.calculateAccumulatedFrame()
            let cx = f.midX, cy = f.midY
            let rx = max(1, f.width * 0.5), ry = max(1, f.height * 0.5)
            // ellipse radius parameter r (1 = exact edge)
            let dx = p.x - cx, dy = p.y - cy
            let r  = sqrt((dx*dx)/(rx*rx) + (dy*dy)/(ry*ry))
            
            // Only consider if we’re at the *bottom* (height ~ 0)
            if groundHeight(at: p) <= ghTol {
                if best == nil || abs(r - 1) < abs(best!.r - 1) {
                    best = (r, cx, cy, rx, ry)
                }
            }
        }
        guard let b = best else { return }
        
        // Outward unit normal for an ellipse: ∇(x^2/rx^2 + y^2/ry^2) = (2x/rx^2, 2y/ry^2)
        let dx = p.x - b.cx, dy = p.y - b.cy
        if abs(dx) < 1e-6 && abs(dy) < 1e-6 { return } // at center; ignore
        var nx = dx / (b.rx * b.rx), ny = dy / (b.ry * b.ry)
        let nlen = max(1e-6, sqrt(nx*nx + ny*ny))
        nx /= nlen; ny /= nlen
        
        // Radial (outward) velocity component
        let v = pb.velocity
        let vRad = v.dx * nx + v.dy * ny
        
        // Per-step clamp
        let dtClamp = max(1.0/240.0, min(0.05, dt))
        let maxDelta = maxAccelPS * dtClamp
        
        // Inside the thin bottom ring → push outward
        // GameScene.swift — inside applyHillBottomOneWayGuard(dt:)
        if b.r > outerBand && b.r < blockOuter, vRad < 0 {
            // reflect radial component with a little restitution
            let e: CGFloat = 0.30              // bounce "springiness"
            let vtX = v.dx - nx * vRad         // tangential part
            let vtY = v.dy - ny * vRad
            let newRad = e * (-vRad) + tinyBias
            
            var out = CGVector(
                dx: nx * newRad + vtX * 0.95,  // slight tangential damping
                dy: ny * newRad + vtY * 0.95
            )
            // cap per-step change
            let dvx = CGFloat.clamp(out.dx - v.dx, -maxDelta, maxDelta)
            let dvy = CGFloat.clamp(out.dy - v.dy, -maxDelta, maxDelta)
            out = CGVector(dx: v.dx + dvx, dy: v.dy + dvy)
            pb.velocity = out
            
            // tiny nudge + feedback
            car.position = CGPoint(x: car.position.x + nx * 0.5, y: car.position.y + ny * 0.5)
            car.playHitFX(at: car.position)
            return
        }
    }
    
    private func updateSpeedHUD(kmh: CGFloat) {
        let now = CACurrentMediaTime()
        let dt  = lastHUDSample == 0 ? 1.0/60.0 : max(1e-3, now - lastHUDSample)
        lastHUDSample = now
        
        let alpha = 1 - exp(-dt / Double(max(0.001, speedTau)))
        speedEMA += (kmh - speedEMA) * CGFloat(alpha)
        
        let shown = max(0, speedEMA)
        speedLabel.text = String(format: "%3.0f", shown)
        
        UIView.animate(withDuration: 0.5) {
            self.speedLabel.fontColor
            = self.speedEMA < 40
            ? UIColor.white.withAlphaComponent(0.95)
            : self.speedEMA < 100
            ? UIColor.yellow.withAlphaComponent(0.95)
            : self.speedEMA < 200
            ? UIColor.orange.withAlphaComponent(0.95)
            : UIColor.red.withAlphaComponent(0.95)
        }
        
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
    
    func carNodeDidRunOutOfLives(_ car: CarNode) {
        guard let cam = camera else { return }
        
        if car.kind == .player {
            cameraFrozenPos = self.car.position
            pauseWorldForDeath()
            gameOverOverlay.show(in: cam, size: size)
            
            // NEW: auto restart if AI drives the player
            scheduleAutoRestartIfAIControlled(delay: aiAutoRestartDelay)
            return
        }
        
        let anyEnemyStillAlive = cars.contains { $0.kind == .enemy && $0.livesLeft > 0 }
        if !anyEnemyStillAlive {
            cameraFrozenPos = self.car.position
            pauseWorldForDeath()
            winOverlay.show(in: cam, size: size)
            
            // NEW: auto restart if AI drives the player
            scheduleAutoRestartIfAIControlled(delay: aiAutoRestartDelay)
        }
    }
    
    // Stop any RL servers we spun up
    private func stopRLServers() {
        playerRLServer?.stop()
        enemyRLServer?.stop()
        playerRLServer = nil
        enemyRLServer  = nil
    }
    
    private func bindRLServers(train: Bool = true, policyName: String = "IonCircuitPolicy") {
        stopRLServers()
        guard let enemy = cars.first(where: { $0.kind == .enemy && !$0.isDead }) else { return }
        
        // Enemy vs player
        if aiControlsPlayer {
            if train {
                do {
                    let srv = try RLServer(scene: self, agent: car, target: enemy, port: 5555)
                    playerRLServer = srv
                    srv.start()
                    print("✅ RLServer (Player) listening on 5555")
                } catch { print("Player RLServer failed:", error) }
            } else {
                do { try car.useLearnedPolicyInstalled(named: policyName) }
                catch { print("Player policy load failed:", error) }
            }
        }
        
        // Player mirrors same path
        if rlControlsEnemy {
            if train {
                do {
                    let srv = try RLServer(scene: self, agent: enemy, target: car, port: 5556) { [weak self] in
                        self?.toggle?.isUserInteractionEnabled = CarNode.hasPolicyAvailable(named: policyName)
                        
                    }
                    enemyRLServer = srv
                    srv.start()
                    print("✅ RLServer (Enemy) listening on 5556")
                } catch { print("Enemy RLServer failed:", error) }
            } else {
                do { try enemy.useLearnedPolicyInstalled(named: policyName) }
                catch { print("Enemy policy load failed:", error) }
            }
        }
    }
    
    // Toggle AI control of the PLAYER (keeps Kind.player for HUD/UX)
    func startAIControl(_ enabled: Bool, training: Bool = true, policyName: String = "IonCircuitPolicy") {
        refreshControlActiveFlags()
        
        UIApplication.shared.isIdleTimerDisabled = training
        
        if enabled {
            fireButton.isHidden = true
            driveButton.isHidden = true
        }
        
        bindRLServers(train: training, policyName: policyName)
    }
    
    
    @inline(__always)
    private func bulletTooCloseToOwner(_ bullet: SKNode, minDistance: CGFloat = 72) -> Bool {
        if let owner = bullet.userData?["owner"] as? CarNode {
            return owner.position.distance(to: bullet.position) < minDistance
        }
        return false
    }
    
    // MARK: - Touch helpers
    private func isTouchOnCarScene(_ pScene: CGPoint) -> Bool {
        for n in nodes(at: pScene) where (n === car || n.inParentHierarchy(car)) { return true }
        return car.position.distance(to: pScene) <= 26
    }
    
    // MARK: - Touches
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let t = touches.first else { return }

        // 1) Let overlays consume the tap even when the game is paused/locked.
        if !gameOverOverlay.isHidden,
           gameOverOverlay.handleTouch(scenePoint: t.location(in: self)) { return }

        if !winOverlay.isHidden,
           winOverlay.handleTouch(scenePoint: t.location(in: self)) { return }

        // 2) Now block gameplay controls if paused/locked/AI.
        if controlsLockedForOverlay || pausedForDeath || aiControlsPlayer { return }

        guard let cam = camera else { return }

        for t in touches {
            let pCam = t.location(in: cam)

            if fireTouch == nil, pointInsideFireButton(pCam) {
                fireTouch = t
                car.startAutoFire(on: self)
                animateFireTap()
                setFiring(true)
                continue
            } else {
                setFiring(false)
            }

            if driveTouch == nil, pointInsideDriveButton(pCam) {
                driveTouch = t
                isTouching = true
                controlArmed = true
                car.isCoasting = false
                fingerCam = pCam
                car.hasAngleLP = true
                car.angleLP = car.zRotation + .pi/2
                car.lockAngleUntilExitDeadzone = true

                ringGroup.position = driveButton.position
                showRing()
                ringHandle.position = .zero
                animateDriveTap()
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                continue
            }

            if driveTouch == nil {
                let pScene = t.location(in: self)
                if isTouchOnCarScene(pScene) {
                    driveTouch = t
                    isTouching = true
                    controlArmed = true
                    car.isCoasting = false

                    fingerCam = .zero
                    car.hasAngleLP = true
                    car.angleLP = car.zRotation + .pi/2
                    car.lockAngleUntilExitDeadzone = true

                    ringGroup.position = .zero
                    showRing()
                    ringHandle.position = .zero
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    refreshControlActiveFlags()
                }
            }
        }

        refreshControlActiveFlags()
    }
    
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        if controlsLockedForOverlay || pausedForDeath || aiControlsPlayer { return }
        guard let cam = camera else { return }
        
        if let dt = driveTouch, touches.contains(dt) {
            isTouching = true
            fingerCam = dt.location(in: cam)
            guard controlArmed, let f = fingerCam else { return }
            
            // Measure from where the ring actually lives (can be drive button pos)
            let origin = ringGroup.position
            let v = CGVector(dx: f.x - origin.x, dy: f.y - origin.y)
            let dRaw = hypot(v.dx, v.dy)
            let (innerR, outerR) = currentRadii()
            let dClamp = CGFloat.clamp(dRaw, innerR, outerR)
            let angRaw = atan2(v.dy, v.dx)
            
            ringHandle.position = CGPoint(x: cos(angRaw) * dClamp, y: sin(angRaw) * dClamp)
            
            let tNorm = (dClamp - innerR) / max(outerR - innerR, 1)
            let idx = max(0, min(4, Int(floor(tNorm * 5))))
            setActiveBand(index: idx)
            
            if car.lockAngleUntilExitDeadzone, dRaw > innerR + 4 {
                car.lockAngleUntilExitDeadzone = false
            }
        }
    }
    
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        if controlsLockedForOverlay || pausedForDeath || aiControlsPlayer { return }
        if controlsLockedForOverlay || pausedForDeath { return }   // NEW guard
        for t in touches {
            if let ft = fireTouch, t === ft {
                fireTouch = nil
                refreshControlActiveFlags()
                car.stopAutoFire()
                setFiring(false)         // ← color OFF
            }
            if let dt = driveTouch, t === dt {
                driveTouch = nil
                refreshControlActiveFlags()
                isTouching = false
                controlArmed = false
                fingerCam = nil
                hideRing()
                car.isCoasting = true
                // Reset drive arrows when ring hidden / no input
                setDriveArrowColors(up: false, down: false, left: false, right: false,
                                    highlight: .systemTeal)
            }
        }
        
        refreshControlActiveFlags()
    }
    
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        if controlsLockedForOverlay || pausedForDeath || aiControlsPlayer { return }
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
        fireBase.fillColor = fireIdleColor
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
    
    private func setFiring(_ active: Bool) {
        fireBase.removeAction(forKey: "firePulse")
        if active {
            fireBase.fillColor = fireActiveColor
            fireBase.strokeColor = UIColor.white.withAlphaComponent(0.28)
            // subtle pulse while firing
            let up = SKAction.scale(to: 1.05, duration: 0.12); up.timingMode = .easeOut
            let dn = SKAction.scale(to: 1.00, duration: 0.12); dn.timingMode = .easeIn
            fireButton.run(.repeatForever(.sequence([up, dn])), withKey: "firePulse")
        } else {
            fireBase.fillColor = fireIdleColor
            fireBase.strokeColor = UIColor.white.withAlphaComponent(0.18)
            fireButton.removeAction(forKey: "firePulse")
            fireButton.setScale(1.0)
        }
    }
    
    // MARK: - DRIVE BUTTON (movement)
    private func buildDriveButton() {
        driveButton.zPosition = 500
        
        let R = controlButtonRadius // SAME size as fire button (unpressed)
        driveBase.path = CGPath(ellipseIn: CGRect(x: -R, y: -R, width: R*2, height: R*2), transform: nil)
        driveBase.fillColor = UIColor(white: 0.12, alpha: 0.90)
        driveBase.strokeColor = UIColor.white.withAlphaComponent(0.18)
        driveBase.lineWidth = 1.5
        driveBase.glowWidth = 2
        if driveBase.parent == nil { driveButton.addChild(driveBase) }
        
        // Use driveIcon as a container (no own path)
        driveIcon.path = nil
        driveIcon.strokeColor = .clear
        driveIcon.fillColor = .clear
        if driveIcon.parent == nil { driveButton.addChild(driveIcon) }
        
        // Shared geometry for arrows
        func arrowPath(dir: String) -> CGPath {
            let p = CGMutablePath()
            let shaft: CGFloat = 10   // straight segment from center
            let len: CGFloat   = 16   // total length to arrow tip
            let head: CGFloat  = 5    // arrowhead size
            let wing: CGFloat  = head * 0.6
            
            switch dir {
            case "up":
                p.move(to: CGPoint(x: 0, y: shaft))
                p.addLine(to: CGPoint(x: 0, y: len))
                p.move(to: CGPoint(x: 0, y: len))
                p.addLine(to: CGPoint(x: -wing, y: len - head))
                p.move(to: CGPoint(x: 0, y: len))
                p.addLine(to: CGPoint(x:  wing, y: len - head))
            case "down":
                p.move(to: CGPoint(x: 0, y: -shaft))
                p.addLine(to: CGPoint(x: 0, y: -len))
                p.move(to: CGPoint(x: 0, y: -len))
                p.addLine(to: CGPoint(x: -wing, y: -len + head))
                p.move(to: CGPoint(x: 0, y: -len))
                p.addLine(to: CGPoint(x:  wing, y: -len + head))
            case "left":
                p.move(to: CGPoint(x: -shaft, y: 0))
                p.addLine(to: CGPoint(x: -len, y: 0))
                p.move(to: CGPoint(x: -len, y: 0))
                p.addLine(to: CGPoint(x: -len + head, y:  wing))
                p.move(to: CGPoint(x: -len, y: 0))
                p.addLine(to: CGPoint(x: -len + head, y: -wing))
            default: // "right"
                p.move(to: CGPoint(x: shaft, y: 0))
                p.addLine(to: CGPoint(x: len, y: 0))
                p.move(to: CGPoint(x: len, y: 0))
                p.addLine(to: CGPoint(x: len - head, y:  wing))
                p.move(to: CGPoint(x: len, y: 0))
                p.addLine(to: CGPoint(x: len - head, y: -wing))
            }
            return p
        }
        
        // Prepare each arrow node once
        func style(_ n: SKShapeNode, path: CGPath) {
            n.path = path
            n.strokeColor = driveArrowInactive
            n.lineWidth = 2
            n.lineCap = .round
            n.lineJoin = .round
            n.fillColor = .clear
            if n.parent == nil { driveIcon.addChild(n) }
        }
        
        style(driveArrowUp,    path: arrowPath(dir: "up"))
        style(driveArrowDown,  path: arrowPath(dir: "down"))
        style(driveArrowLeft,  path: arrowPath(dir: "left"))
        style(driveArrowRight, path: arrowPath(dir: "right"))
        
        // start dim
        setDriveArrowColors(up: false, down: false, left: false, right: false, highlight: .systemTeal)
    }
    
    private func pointInsideDriveButton(_ pCam: CGPoint) -> Bool {
        let local = CGPoint(x: pCam.x - driveButton.position.x, y: pCam.y - driveButton.position.y)
        return hypot(local.x, local.y) <= (controlButtonRadius + 4)
    }
    
    private func animateDriveTap() {
        driveButton.removeAction(forKey: "press")
        let down = SKAction.scale(to: 0.94, duration: 0.05)
        let up   = SKAction.scale(to: 1.00, duration: 0.08)
        driveButton.run(.sequence([down, up]), withKey: "press")
    }
    // --------------------------------------------------------------------------
    
    private func hash2(_ x: Int, _ y: Int, seed: UInt64) -> UInt64 {
        var h = seed &+ UInt64(bitPattern: Int64(x)) &* 0x9E3779B97F4A7C15
        h ^= UInt64(bitPattern: Int64(y)) &* 0xBF58476D1CE4E5B9
        h ^= (h >> 27)
        return h
    }
    
    private func cameraWorldRect(margin: CGFloat) -> CGRect {
        let camPos   = camera?.position ?? .zero
        let camScale = camera?.xScale ?? 1.0
        let w = size.width  * camScale
        let h = size.height * camScale
        return CGRect(x: camPos.x - w/2 - margin,
                      y: camPos.y - h/2 - margin,
                      width:  w + margin * 2,
                      height: h + margin * 2)
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
        let target = carsStreamingRect(margin: preloadMargin)
        let r = chunkRange(for: target)
        
        var want: Set<Int64> = []
        for cy in r.cy0...r.cy1 {
            for cx in r.cx0...r.cx1 {
                let key = chunkKey(cx: cx, cy: cy)
                want.insert(key)
                if loadedChunks[key] == nil || force {
                    // Queue instead of building immediately
                    pendingChunkLoads.append((cx, cy))
                }
            }
        }
        
        if !force {
            for (key, nodes) in loadedChunks where !want.contains(key) {
                // Queue graceful unload
                pendingChunkUnloads.append(nodes)
                loadedChunks.removeValue(forKey: key)
            }
        }
    }
    
    private func processStreamQueues() {
        // Load a few chunks
        var loaded = 0
        while loaded < streamChunkLoadBudgetPerFrame, !pendingChunkLoads.isEmpty {
            let (cx, cy) = pendingChunkLoads.removeFirst()
            let key = chunkKey(cx: cx, cy: cy)
            if loadedChunks[key] == nil { spawnChunk(cx: cx, cy: cy) }
            loaded += 1
        }
        
        // Unload nodes in small batches
        var removed = 0
        while removed < streamNodeUnloadBudgetPerFrame, !pendingChunkUnloads.isEmpty {
            var arr = pendingChunkUnloads[0]
            while removed < streamNodeUnloadBudgetPerFrame, !arr.isEmpty {
                let n = arr.removeLast()
                n.removeAllActions()
                n.removeFromParent()
                removed += 1
            }
            if arr.isEmpty { pendingChunkUnloads.removeFirst() }
            else { pendingChunkUnloads[0] = arr }
        }
    }
    
    private func spawnChunk(cx: Int, cy: Int) {
        let key = chunkKey(cx: cx, cy: cy)
        guard loadedChunks[key] == nil else { return }
        let rect = chunkRect(cx: cx, cy: cy)
        
        var nodes: [SKNode] = []
        spawnObstacles(in: rect, nodesOut: &nodes, cx: cx, cy: cy)
        spawnHillsAndRamps(in: rect, nodesOut: &nodes, cx: cx, cy: cy)
        
        // === Unrelated ground enhancements (independent rolls) ===
        spawnGroundEnhancements(in: rect, nodesOut: &nodes, cx: cx, cy: cy)
        
        loadedChunks[key] = nodes
    }
    
    private func spawnObstacles(in rect: CGRect, nodesOut: inout [SKNode], cx: Int, cy: Int) {
        var rowAnchors: [CGPoint] = []
        let barrierChance: CGFloat = 0.08
        let coneRowChanceLocal: CGFloat = coneRowChance
        let steelChanceSingle: CGFloat = 0.15
        
        let pad: CGFloat = max(28, obstacleCell * 0.08)
        let cols = Int(ceil(rect.width / obstacleCell))
        let rows = Int(ceil(rect.height / obstacleCell))
        
        // One-time blocker cache for this chunk (inflate a bit for clearances)
        let query = rect.insetBy(dx: -(obstacleClearanceMajor + 24), dy: -(obstacleClearanceMajor + 24))
        var blockers = gatherSpawnBlockers(in: query)
        
        // As we place inside this chunk, also track the frames we just added
        var placedThisChunk: [CGRect] = []
        
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
                
                if !worldBounds.contains(a) { continue }
                if a.distance(to: car.position) < obstacleKeepOutFromCar { continue }
                
                let toCenter = hypot(a.x - worldCenter.x, a.y - worldCenter.y)
                let maxR = 0.5 * hypot(worldBounds.width, worldBounds.height)
                let falloff = CGFloat.clamp(toCenter / max(1, maxR), 0, 1)
                let placeP: CGFloat = 0.14 + 0.28 * falloff
                if !rng.chance(placeP) { continue }
                
                // Fast clearance: check vs cached blockers and what we placed this chunk
                if circleIntersectsAny(center: a, radius: obstacleClearanceMajor, rects: blockers) { continue }
                if circleIntersectsAny(center: a, radius: minNeighborSpacing, rects: placedThisChunk) { continue }
                
                var placedNodes: [SKNode] = []
                var placedSomething = false
                
                // --- barrier + two cones behind it ---
                if rng.chance(barrierChance) {
                    let dir = CGVector(dx: a.x - worldCenter.x, dy: a.y - worldCenter.y)
                    let rot = atan2(dir.dy, dir.dx)
                    
                    if let barrier = placeObstacleTracked(.barrier, at: a, rotation: rot, skipPhysicsClearance: false) {
                        placedNodes.append(barrier)
                        placedSomething = true
                        
                        let back = CGPoint(x: a.x - cos(rot) * 56, y: a.y - sin(rot) * 56)
                        let left = CGPoint(x: back.x - sin(rot) * 16, y: back.y + cos(rot) * 16)
                        let right = CGPoint(x: back.x + sin(rot) * 16, y: back.y - cos(rot) * 16)
                        
                        // cones behind the barrier should also respect physics
                        if !circleIntersectsAny(center: left,  radius: minNeighborSpacing, rects: blockers + placedThisChunk),
                           let l = placeObstacleTracked(.cone, at: left, rotation: rot, skipPhysicsClearance: false) {
                            placedNodes.append(l)
                        }
                        if !circleIntersectsAny(center: right, radius: minNeighborSpacing, rects: blockers + placedThisChunk),
                           let r = placeObstacleTracked(.cone, at: right, rotation: rot, skipPhysicsClearance: false) {
                            placedNodes.append(r)
                        }
                    }
                }
                
                // --- cone row (with corridor & anti-chaining) ---
                if !placedSomething, rng.chance(coneRowChanceLocal) {
                    
                    // 1) Don’t chain rows too close to each other (per-chunk guard)
                    let nearAnotherRow = rowAnchors.contains { $0.distance(to: a) < coneRowChainGuard }
                    if !nearAnotherRow {
                        let baseRot: CGFloat = (rng.chance(0.5) ? 0 : .pi/2)
                        let rot = baseRot + (.pi/12) * (rng.range(-1...1))
                        let count = rng.int(coneCountRange)
                        
                        // Row endpoints (used for a corridor probe)
                        let totalSpan = CGFloat(count - 1) * coneSpacing
                        let start = CGPoint(x: a.x - cos(rot) * totalSpan * 0.5,
                                            y: a.y - sin(rot) * totalSpan * 0.5)
                        let end   = CGPoint(x: a.x + cos(rot) * totalSpan * 0.5,
                                            y: a.y + sin(rot) * totalSpan * 0.5)
                        
                        // 2) Make sure the whole corridor is free (capsule sweep)
                        let corridorMask: UInt32 = (Category.wall | Category.obstacle | Category.hole | Category.ramp)
                        let corridorClear = pathClearCapsule(from: start, to: end, radius: max(18, coneLocalClearance), mask: corridorMask)
                        if corridorClear {
                            var ok = true
                            var rowNodes: [SKNode] = []
                            
                            for idx in 0..<count {
                                let t = CGFloat(idx) - CGFloat(count - 1) * 0.5
                                let p = CGPoint(x: a.x + cos(rot) * coneSpacing * t,
                                                y: a.y + sin(rot) * coneSpacing * t)
                                
                                // 3) Physics-aware local clearance (don’t stack on anything)
                                let avoidMask: UInt32 = (Category.wall | Category.obstacle | Category.hole | Category.ramp | Category.car)
                                if circleIntersectsAny(center: p, radius: coneNeighborSpacing, rects: blockers + placedThisChunk)
                                    || !clearanceOK(at: p, radius: coneLocalClearance, mask: avoidMask) {
                                    ok = false; break
                                }
                                
                                if let n = placeObstacleTracked(.cone, at: p, rotation: rot, skipPhysicsClearance: false) {
                                    rowNodes.append(n)
                                } else {
                                    ok = false; break
                                }
                            }
                            
                            if ok {
                                placedNodes.append(contentsOf: rowNodes)
                                placedSomething = true
                                rowAnchors.append(a)
                            } else {
                                rowNodes.forEach { $0.removeFromParent() }
                            }
                        }
                    }
                }
                
                // --- single scatter ---
                // --- single scatter ---
                if !placedSomething {
                    let u = rng.unit()
                    if u < coneSingleChance {
                        // A lone cone with proper clearance (uses cone rules)
                        let rot = rng.range(-(.pi/8)...(.pi/8))
                        let avoidMask: UInt32 = Category.wall | Category.obstacle | Category.hole | Category.ramp | Category.car
                        if !circleIntersectsAny(center: a, radius: coneNeighborSpacing, rects: blockers + placedThisChunk),
                           clearanceOK(at: a, radius: coneLocalClearance, mask: avoidMask),
                           let n = placeObstacleTracked(.cone, at: a, rotation: rot, skipPhysicsClearance: false) {
                            placedNodes.append(n); placedSomething = true
                        }
                    } else {
                        // Existing rock / barrel / steel scatter
                        let kind: ObstacleKind = (u < (coneSingleChance + steelChanceSingle)) ? .steel : (u < 0.60 ? .rock : .barrel)
                        let rot = rng.range(-(.pi/8)...(.pi/8))
                        if let n = placeObstacleTracked(kind, at: a, rotation: rot, skipPhysicsClearance: true) {
                            placedNodes.append(n); placedSomething = true
                        }
                    }
                }
                
                if placedSomething {
                    nodesOut.append(contentsOf: placedNodes)
                    // Add their frames to caches so next placements respect spacing
                    for n in placedNodes {
                        blockers.append(n.calculateAccumulatedFrame())
                        placedThisChunk.append(n.calculateAccumulatedFrame())
                    }
                }
            }
        }
    }
    
    // MARK: - Placement utilities
    @discardableResult
    private func clearanceOK(
        at p: CGPoint,
        radius: CGFloat,
        mask: UInt32,
        ignoring ignoreSet: Set<SKNode> = []
    ) -> Bool {
        var blocked = false
        let box = CGRect(x: p.x - radius, y: p.y - radius, width: radius * 2, height: radius * 2)
        
        physicsWorld.enumerateBodies(in: box) { body, stop in
            // only consider masked bodies
            guard (body.categoryBitMask & mask) != 0 else { return }
            
            // skip the explicitly ignored nodes (and anything inside them)
            if let n = body.node {
                if ignoreSet.contains(where: { n === $0 || n.inParentHierarchy($0) || $0.inParentHierarchy(n) }) {
                    return
                }
            }
            
            // filter out AABB-only overlaps that don't actually touch our circle
            if let n = body.node {
                let fr = n.calculateAccumulatedFrame()
                if !self.circleIntersectsRect(center: p, radius: radius, rect: fr) {
                    return
                }
            }
            
            blocked = true
            stop.pointee = true
        }
        
        return !blocked
    }
    
    // ─────────────────────────────────────────────────────────────────────────────
    // Make static/dynamic obstacles non-bouncy
    // ─────────────────────────────────────────────────────────────────────────────
    
    @discardableResult
    private func placeObstacleTracked(_ kind: ObstacleKind,
                                      at p: CGPoint,
                                      rotation: CGFloat = 0,
                                      skipPhysicsClearance: Bool = false) -> SKNode? {
        if !worldBounds.contains(p) { return nil }
        
        if !skipPhysicsClearance {
            let avoidMask: UInt32 = Category.wall | Category.obstacle | Category.hole | Category.ramp | Category.car
            if !clearanceOK(at: p, radius: obstacleClearanceMajor, mask: avoidMask) { return nil }
        }
        
        let node = ObstacleFactory.make(kind)
        node.position = p
        node.zRotation = rotation
        
        if kind == .hole {
            node.name = "worm.hole"
            node.zPosition = -0.2
            applyMultiplyBlendRecursively(node)

            if let pb = node.physicsBody {
                pb.isDynamic = false
                pb.categoryBitMask = Category.hole
                pb.collisionBitMask = 0
                pb.contactTestBitMask = 0
            }

            if node.userData == nil { node.userData = NSMutableDictionary() }
            node.userData?["occupied"] = false

            // ⬇️ auto-spawn a worm from THIS hole shortly after it appears
            node.run(.sequence([
                .wait(forDuration: 0.12),
                .run { [weak self, weak node] in
                    guard let self, let hole = node,
                          (hole.userData?["occupied"] as? Bool) == false else { return }
                    let pScene = self.convert(hole.position, from: self.groundRoot)
                    self.spawnWormFromHole(at: pScene)
                }
            ]), withKey: "wormAutospawn")

            node.alpha = 0
            node.run(.sequence([
                .fadeIn(withDuration: 0.08),
                .wait(forDuration: 6.0),
                .group([ .fadeOut(withDuration: 0.22),
                         .scale(to: 0.92, duration: 0.22) ]),
                .removeFromParent()
            ]), withKey: "ttl")

            groundRoot.addChild(node)
            return node
        }
        
        // normal obstacles
        node.zPosition = 1
        if let pb = node.physicsBody { pb.restitution = 0; pb.friction = 0 }
        obstacleRoot.addChild(node)
        return node
    }
    
    private func applyMultiplyBlendRecursively(_ n: SKNode) {
        if let s = n as? SKSpriteNode { s.blendMode = SKBlendMode.multiply }
        if let s = n as? SKShapeNode  { s.blendMode = SKBlendMode.multiply }
        // If your hole uses an emitter, you can also do:
        if let e = n as? SKEmitterNode { e.particleBlendMode = SKBlendMode.multiply }
        for c in n.children { applyMultiplyBlendRecursively(c) }
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
    func groundHeight(at p: CGPoint) -> CGFloat {
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
    
    @inline(__always)
    private func ellipseRadiusAlong(rx: CGFloat, ry: CGFloat, vx: CGFloat, vy: CGFloat) -> CGFloat {
        let denom = sqrt((vx*vx)/(rx*rx) + (vy*vy)/(ry*ry))
        return denom < 1e-6 ? 0 : 1/denom
    }
    
    @inline(__always)
    func pathClearCapsule(from a: CGPoint, to b: CGPoint, radius r: CGFloat, mask: UInt32) -> Bool {
        let dx = b.x - a.x, dy = b.y - a.y
        let dist = hypot(dx, dy)
        let steps = max(1, Int(ceil(dist / max(72, r * 1.25))))
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
        
        @inline(__always) func dir(_ a: CGFloat) -> CGVector { .init(dx: cos(a), dy: sin(a)) }
        
        let baseHeading = atan2(center.y - worldCtr.y, center.x - worldCtr.x)
        let candidates: [CGFloat] = [
            baseHeading,
            baseHeading + (.pi/10),
            baseHeading - (.pi/10),
            rng.range(-.pi ... .pi)     // a wild-card direction for variety
        ]
        
        let rampWidthRange: ClosedRange<CGFloat>  = 74...98
        let rampLengthRange: ClosedRange<CGFloat> = 120...160
        let corridorMask: UInt32 = Category.wall | Category.obstacle | Category.ramp
        
        for heading in candidates {
            let d = dir(heading)
            
            // Where the ellipse edge lies along this direction
            let edge = ellipseRadiusAlong(rx: rx, ry: ry, vx: d.dx, vy: d.dy)
            
            // Place ramp just outside the hill edge, pointing toward the hill
            let gap: CGFloat = 78
            let rampCenter = CGPoint(x: center.x - d.dx * (edge + gap),
                                     y: center.y - d.dy * (edge + gap))
            
            // ✅ Loosen region gating:
            if rampsBorderOnly {
                guard pointInBorderBand(rampCenter) else { continue }
            } else {
                guard worldBounds.contains(rampCenter) else { continue }
            }
            
            // Sample a run-up start point behind the ramp
            let runLen = rng.range(runupRange)
            let start  = CGPoint(x: rampCenter.x - d.dx * runLen,
                                 y: rampCenter.y - d.dy * runLen)
            
            if rampsBorderOnly {
                guard pointInBorderBand(start) else { continue }
                // (no need to keep the entire segment inside the band anymore)
            } else {
                guard worldBounds.contains(start) else { continue }
            }
            
            // Corridor must be clear of walls/obstacles/holes/ramps
            guard pathClearCapsule(from: start, to: rampCenter,
                                   radius: corridorHalfWidth,
                                   mask: corridorMask) else { continue }
            
            // Build ramp footprint; ensure its tip & tail lie inside the world
            let rampSize = CGSize(width: rng.range(rampWidthRange),
                                  height: rng.range(rampLengthRange))
            let halfL = 0.5 * rampSize.height
            let tip  = CGPoint(x: rampCenter.x + d.dx * halfL, y: rampCenter.y + d.dy * halfL)
            let tail = CGPoint(x: rampCenter.x - d.dx * halfL, y: rampCenter.y - d.dy * halfL)
            guard worldBounds.contains(tip), worldBounds.contains(tail) else { continue }
            
            // Vertical impulse needed to reach hill top from this point
            let g = abs(car.gravity)
            let heightToReach = max(0, hill.topHeight - groundHeight(at: rampCenter))
            let vzNeeded = sqrt(max(1, 2 * g * max(20, heightToReach * 1.05))) * 1.25
            
            let ramp = RampNode(center: rampCenter, size: rampSize, heading: heading, strengthZ: vzNeeded)
            ramp.zPosition = 0.4
            obstacleRoot.addChild(ramp)
            return ramp
        }
        return nil
    }
    
    // Find the nearest hill to a point (used to figure which hill a ramp is “for”)
    private func nearestHill(to p: CGPoint, within maxDistance: CGFloat = 1200) -> HillNode? {
        var best: (node: HillNode, d: CGFloat)?
        for h in hills where h.parent != nil {
            let fr = h.calculateAccumulatedFrame()
            let c  = CGPoint(x: fr.midX, y: fr.midY)
            let d  = hypot(p.x - c.x, p.y - c.y)
            if d <= maxDistance, (best == nil || d < best!.d) { best = (h, d) }
        }
        return best?.node
    }
    
    // Minimum vertical speed needed to reach a hill’s top from world position p
    private func requiredVzToReachTop(from p: CGPoint, to hill: HillNode) -> CGFloat {
        // how much vertical “height” we still need to gain at the ramp location
        let g = abs(car.gravity)
        let dz = max(0, hill.topHeight - groundHeight(at: p))
        // classic v^2 = 2 g h, plus a small safety margin
        let base = sqrt(max(1, 2 * g * dz))
        return base * 1.08  // +8% cushion
    }
    
    private func spawnHillsAndRamps(in rect: CGRect, nodesOut: inout [SKNode], cx: Int, cy: Int) {
        var rng = SplitMix64(seed: hash2(cx &* 7919, cy &* 104729, seed: worldSeed ^ 0xC0FFEE))
        
        // Density / tuning
        let hillsPerChunkChance: CGFloat = 0.58
        let hillsPerChunkMax = 2
        let rampsPerHillTarget = 3
        let rampRunupRange: ClosedRange<CGFloat> = 520...1000
        let rampCorridorHalfWidth: CGFloat = 56
        
        // How many hills this chunk wants
        let wantHills = (rng.chance(hillsPerChunkChance) ? 1 : 0)
        + (rng.chance(hillsPerChunkChance * 0.50) ? 1 : 0)
        let count = min(wantHills, hillsPerChunkMax)
        
        // Stay away from chunk edges a bit when sampling candidate centers
        let pad: CGFloat = max(140, obstacleCell * 0.22)
        let allowed = rect.insetBy(dx: pad, dy: pad)
        
        for _ in 0..<count {
            // Random size and candidate center
            let sz = CGSize(width:  rng.range(320...540),
                            height: rng.range(220...420))
            let c  = CGPoint(x: rng.range(allowed.minX...allowed.maxX),
                             y: rng.range(allowed.minY...allowed.maxY))
            
            // Hill rect we intend to place
            let rectHill = CGRect(x: c.x - sz.width/2, y: c.y - sz.height/2,
                                  width: sz.width, height: sz.height)
            
            // ✅ Loosen region gating:
            if hillsBorderOnly {
                guard rectFullyInBorderBand(rectHill) else { continue }
            } else {
                guard worldBounds.contains(rectHill) else { continue }
            }
            
            // Spacing & safety
            let minHillSpacing = max(minNeighborSpacing, max(sz.width, sz.height))
            if c.distance(to: car.position) < max(minHillSpacing, obstacleKeepOutFromCar) { continue }
            if hills.contains(where: { $0.parent != nil && $0.calculateAccumulatedFrame().intersects(rectHill.insetBy(dx: -24, dy: -24)) }) { continue }
            
            let avoidMask: UInt32 = Category.wall | Category.obstacle | Category.hole | Category.ramp | Category.car
            if !clearanceOK(at: c, radius: minHillSpacing * 0.6, mask: avoidMask) { continue }
            
            // Create hill
            let h = rng.range(90...180)
            let hill = HillNode(rect: rectHill, height: h)
            hill.zPosition = 0.5
            addChild(hill)
            hills.append(hill)
            nodesOut.append(hill)
            
            // Try placing ramps for this hill
            var made = 0
            for _ in 0..<rampsPerHillTarget {
                if var localRNG = Optional(rng), let r = placeUsefulRamp(for: hill,
                                                                         runupRange: rampRunupRange,
                                                                         corridorHalfWidth: rampCorridorHalfWidth,
                                                                         rng: &localRNG) {
                    nodesOut.append(r); made += 1
                }
            }
            
            // Fallback ramp if none succeeded (slightly relaxed)
            if made == 0 {
                var relaxed = rng
                if let r = placeUsefulRamp(for: hill,
                                           runupRange: (rampRunupRange.lowerBound - 120)...(rampRunupRange.upperBound + 200),
                                           corridorHalfWidth: rampCorridorHalfWidth * 0.8,
                                           rng: &relaxed) {
                    nodesOut.append(r)
                }
            }
            
            // Hill enhancement
            maybeSpawnEnhancement(on: hill, rng: &rng)
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
    
    // Fire on the opposite side of Drive
    private func placeFireButton() {
        let inset = safeInsetsInCamera()
        let margin: CGFloat = 20
        let R: CGFloat = 40
        let y = -size.height * 0.5 + margin + R + 50
        let x = isLeftHanded
        ? ( size.width * 0.5 - inset.right - margin - R - 40)   // Fire RIGHT
        : (-size.width * 0.5 + inset.left  + margin + R + 40)   // Fire LEFT
        fireButton.position = CGPoint(x: x, y: y)
    }
    
    private func placeDriveButton() {
        let inset = safeInsetsInCamera()
        let margin: CGFloat = 20
        let R: CGFloat = 40
        let y = -size.height * 0.5 + margin + R + 50
        let x = isLeftHanded
        ? (-size.width * 0.5 + inset.left  + margin + R + 40)   // Drive LEFT
        : ( size.width * 0.5 - inset.right - margin - R - 40)   // Drive RIGHT
        driveButton.position = CGPoint(x: x, y: y)
    }
    
    // MARK: - Update
    override func update(_ currentTime: TimeInterval) {
        let dt = lastUpdateTime > 0 ? CGFloat(currentTime - lastUpdateTime) : 0
        lastUpdateTime = currentTime
        voidTime += max(0, Float(dt))
        voidTimeUniform.floatValue = voidTime
        
        if let camera {
            Audio.shared.updateListener(camera: camera.position, viewportSize: size)
        }
        
        let overlaysUp = pausedForDeath || !gameOverOverlay.isHidden || !winOverlay.isHidden
        let rawFight = overlaysUp ? 0 : fightIntensityEstimate()
        
        // Hysteresis + short hold so combat actually “finishes”
        if rawFight > fightEnterThreshold {
            fightHoldUntil = currentTime + 2.5
        }
        let shouldBeCombat = (rawFight > fightEnterThreshold) || (currentTime < fightHoldUntil && rawFight > fightExitThreshold)
        let target = shouldBeCombat ? rawFight : 0
        
        let fight = smoothFight(target, dt: dt)
        Audio.shared.updateFight(intensity: fight, at: car.position, now: currentTime)
        
        // If your Audio manager needs a nudge to bring ambient back, re-cue on exit:
        if fightWasCombat && !shouldBeCombat {
            Audio.shared.playMusic(names: ["ambient_loop"], crossfade: 2.5)
        }
        fightWasCombat = shouldBeCombat
        
        // --- Engine audio gating + spatialization ---
        let v = car.physicsBody?.velocity ?? .zero
        let speed = hypot(v.dx, v.dy)
        let rev = min(1, speed / max(1, car.maxSpeed + car.speedCapBonus))
        
        // Start the engine only when we’re moving or the player is actively driving
        let shouldRun = (speed > 30) || isAnyControlActive || (car.throttle > 0.01)
        
        Audio.shared.updateEngine(run: shouldRun, normalized: rev)
        
        if currentTime >= nextRampPointerUpdate {
            updateRampPointer()
            nextRampPointerUpdate = currentTime + rampPointerUpdateInterval
        }
        
        updateCameraFollow(dt: dt)
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
            voidTime += Float(dt)
            voidTimeUniform.floatValue = voidTime
            recenterCameraOnTargetIfNeeded()
            return
        }
        
        maybeUpdateObstacleStreaming(currentTime)
        
        if !car.isDead, isTouching, controlArmed, let f = fingerCam, let pb = car.physicsBody  {
            car.isCoasting = false
            
            // Measure from the ring’s current center (drive button or camera)
            let origin = ringGroup.position
            let vFinger = CGVector(dx: f.x - origin.x, dy: f.y - origin.y)
            let dRaw    = hypot(vFinger.dx, vFinger.dy)
            let (innerR, outerR) = currentRadii()
            let dClamped = CGFloat.clamp(dRaw, innerR, outerR)
            let angRaw   = atan2(vFinger.dy, vFinger.dx)
            
            ringHandle.position = CGPoint(x: cos(angRaw) * dClamped, y: sin(angRaw) * dClamped)
            
            let tNormBase = (dClamped <= innerR + 1) ? 0 : (dClamped - innerR) / max(outerR - innerR, 1)
            let tNorm = CGFloat.clamp(tNormBase, 0, 1)
            let idx = max(0, min(4, Int(floor(tNorm * 5))))
            setActiveBand(index: idx)
            
            if car.lockAngleUntilExitDeadzone, dRaw > innerR + 4 {
                car.lockAngleUntilExitDeadzone = false
            }
            
            // === DRIVING LOGIC ===
            let tau: CGFloat = 0.06
            let alpha = CGFloat(1.0 - exp(-Double(dt / tau)))
            if !car.lockAngleUntilExitDeadzone, dRaw > innerR + 4 {
                if car.hasAngleLP {
                    car.angleLP += alpha * shortestAngle(from: car.angleLP, to: angRaw)
                } else {
                    car.angleLP = angRaw
                    car.hasAngleLP = true
                }
            }
            
            let heading  = car.zRotation + .pi/2
            let angleErr = shortestAngle(from: heading, to: car.angleLP)
            if car.lockAngleUntilExitDeadzone || dRaw <= innerR + 4 {
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
            
            if car.lockAngleUntilExitDeadzone || dRaw <= innerR + 4 {
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
            
            // Drive arrows highlight based on finger direction
            updateDriveArrows(fromInput: vFinger, tNorm: tNorm, activeBand: idx)
            
        } else if car.isCoasting && !car.isDead && !playerIsAIControlled {
            let speed = car.physicsBody?.velocity.length ?? 0
            if speed < 8 {
                car.throttle = 0
                car.steer = 0
                car.isCoasting = false
                car.hasAngleLP = false
                car.lockAngleUntilExitDeadzone = false
            } else {
                car.throttle = 0
                car.steer = 0.001
            }
            car.speedCapBonus = 0
            // Dim arrows during coasting (no input)
            setDriveArrowColors(up: false, down: false, left: false, right: false, highlight: .systemTeal)
        } else if !playerIsAIControlled {
            car.throttle = 0
            car.steer = 0
            car.hasAngleLP = false
            car.lockAngleUntilExitDeadzone = false
            car.speedCapBonus = 0
            setDriveArrowColors(up: false, down: false, left: false, right: false, highlight: .systemTeal)
        }
        
        // Keep the vertical axis in sync with terrain (smooth hill profile)
        for car in cars {
            let (gh, gvec) = groundHeightAndGradient(at: car.position)
            applyHillModifiers(for: car, gh: gh, gradient: gvec)
            car.stepVertical(dt: dt, groundHeight: gh)
            if playerPhasingWallsUntilLand, !car.isAirborne {
                setPassThroughWallsWhileAirborne(car, enabled: false)
                playerPhasingWallsUntilLand = false
            }
            car.update(dt)
        }
        
        // --- AI tactical fire control (obstacle-aware) ---
        if let enemy = cars.first(where: { $0.kind == .enemy && !$0.isDead }) {
            // If enemy is not driven by RL, use the heuristic fully.
            if !rlControlsEnemy {
                aiTacticalFireIfNeeded(shooter: enemy, target: car)
            } else {
                // Even during RL, auto-clear an immediate blocker straight ahead.
                if let _ = firstObstacleAheadInCone(for: enemy, maxDist: 420, halfAngle: .pi/12) {
                    fireBurst(enemy, duration: 0.14)
                }
            }
        }
        
        if aiControlsPlayer {
            // If player is heuristic AI (not RL), clear path and shoot as needed.
            if !rlControlsPlayer, let enemyForPlayer = cars.first(where: { $0.kind == .enemy && !$0.isDead }) {
                aiTacticalFireIfNeeded(shooter: car, target: enemyForPlayer)
            } else {
                // RL player: still clear a near blocker to keep movement fluid
                if let _ = firstObstacleAheadInCone(for: car, maxDist: 420, halfAngle: .pi/12) {
                    fireBurst(car, duration: 0.14)
                }
            }
        }
        
        _preCarVel = car.physicsBody?.velocity ?? .zero   // ← NEW
        _lastDTForClamp = dt
        
        let ptsPerSec = car.physicsBody?.velocity.length ?? 0
        let kmh = ptsPerSec * kmhPerPointPerSecond
        updateSpeedHUD(kmh: kmh)
        
        let actualHeading = car.zRotation + .pi/2
        let desiredHeading = (car.hasAngleLP ? car.angleLP : actualHeading)
        updateHeadingHUD(desired: desiredHeading, actual: actualHeading)
        
        updateEnemyBlipOnHeadingHUD()
        
        updateRampPointer()
        cullBulletsOutsideWorld()
        seedObstaclesFromEnemies()
        
        if didPickHand || aiControlsPlayer {
            processStreamQueues()
            
            let go = training ? (!aiControlsPlayer || playerRLServer!.isRunning) && enemyRLServer!.isRunning : false
            guard go else { return }
            maybeSpawnWorm(car: car ,currentTime)
            
            let enemies = cars.filter({ $0.kind == .enemy })
        
            for enemy in enemies {
                guard car.position.distance(to: enemy.position) >= 1200 else { continue }
                maybeSpawnWorm(car: enemy, currentTime)
            }
            
            for w in worms where w.parent != nil {
                w.update(dt: dt, target: car)
            }
        }
    }
    
    @discardableResult
    private func spawnHole(at pScene: CGPoint, ttl: TimeInterval = 8.0) -> SKNode {
        let r: CGFloat = 60
        let h = SKShapeNode(ellipseOf: CGSize(width: r*2, height: r*2))
        h.fillColor = UIColor.black.withAlphaComponent(0.85)
        h.strokeColor = UIColor.black.withAlphaComponent(0.15)
        h.lineWidth = 1
        h.name = "worm.hole"
        
        groundRoot.addChild(h)
        h.position = groundRoot.convert(pScene, from: self)
        h.zPosition = 0
        
        // ✅ mark not occupied yet
        if h.userData == nil { h.userData = NSMutableDictionary() }
        h.userData?["occupied"] = false
        
        // ✅ auto-spawn a worm from THIS hole after a tiny delay
        h.run(.sequence([
            .wait(forDuration: 0.12),
            .run { [weak self, weak h] in
                guard let self, let hole = h,
                      (hole.userData?["occupied"] as? Bool) != true else { return }
                // convert back to scene space and spawn the worm
                let p = self.convert(hole.position, from: self.groundRoot)
                self.spawnWormFromHole(at: p)   // reuse hole via the change below
            },
            .wait(forDuration: ttl),
            .group([.fadeOut(withDuration: 0.25), .scale(to: 0.85, duration: 0.25)]),
            .removeFromParent()
        ]))
        return h
    }
    
    private func findSafeHolePositionSpiral(from origin: CGPoint,
                                            step: CGFloat,
                                            maxRadius: CGFloat,
                                            samplesPerRing: Int,
                                            avoidMask: UInt32) -> CGPoint? {
        var r = step
        while r <= maxRadius {
            for i in 0..<samplesPerRing {
                let a = (CGFloat(i) / CGFloat(samplesPerRing)) * (.pi * 2)
                let cand = CGPoint(x: origin.x + cos(a) * r,
                                   y: origin.y + sin(a) * r)
                guard worldBounds.contains(cand) else { continue }
                
                let box = CGRect(x: cand.x - holeClearance - 12,
                                 y: cand.y - holeClearance - 12,
                                 width: (holeClearance + 12) * 2,
                                 height: (holeClearance + 12) * 2)
                if clearanceOK(at: cand, radius: holeClearance, mask: avoidMask) &&
                    !circleIntersectsAny(center: cand, radius: holeClearance, rects: gatherSpawnBlockers(in: box)) {
                    return cand
                }
            }
            r += step
        }
        return nil
    }
    
    
    // Find an unoccupied hole near the player
    private func freeHole(near p: CGPoint, maxDist: CGFloat = 10000) -> SKNode? {
        var best: (n: SKNode, d: CGFloat)?
        enumerateChildNodes(withName: "//worm.hole") { n, _ in
            let used = (n.userData?["occupied"] as? Bool) == true
            if used { return }
            let d = n.position.distance(to: p)
            if d >= maxDist * 0.2, d <= maxDist, best == nil || d < best!.d { best = (n, d) }
        }
        return best?.n
    }
    
    private func fightIntensityEstimate() -> CGFloat {
        guard let enemy = cars.first(where: { $0.kind == .enemy && !$0.isDead }) else { return 0 }
        var score: CGFloat = 0
        let d = car.position.distance(to: enemy.position)
        let los = hasLineOfSight(from: enemy, to: car)
        
        // Enemy bullets near the player
        var nearEnemyBullets = 0
        enumerateChildNodes(withName: "bullet") { n, _ in
            if let owner = n.userData?["owner"] as? CarNode, owner.kind == .enemy,
               n.position.distance(to: self.car.position) < 320 { nearEnemyBullets += 1 }
        }
        score += min(1, CGFloat(nearEnemyBullets) / 3) * 0.65
        
        // Distance only contributes if there’s LoS
        if los {
            let near = CGFloat.clamp((750 - d) / 750, 0, 1)
            score += near * 0.35
        } else if d < 450 {
            score += 0.08 // mild tension when very close but no LoS
        }
        
        return CGFloat.clamp(score, 0, 1)
    }
    
    @inline(__always)
    private func smoothFight(_ target: CGFloat, dt: CGFloat) -> CGFloat {
        let tauUp: CGFloat = 0.15   // rise fast
        let tauDn: CGFloat = 0.80   // fall a bit slower (still reaches 0)
        let tau = (target > fightLevel) ? tauUp : tauDn
        let alpha = 1 - exp(-dt / max(0.001, tau))
        fightLevel += (target - fightLevel) * alpha
        return fightLevel
    }
    
    @inline(__always)
    private func gatherSpawnBlockers(in region: CGRect) -> [CGRect] {
        var rects: [CGRect] = []
        let avoidMask: UInt32 = Category.wall | Category.obstacle | Category.hole | Category.ramp | Category.car
        
        // One physics query for the whole region
        physicsWorld.enumerateBodies(in: region) { body, _ in
            if (body.categoryBitMask & avoidMask) != 0, let n = body.node {
                rects.append(n.calculateAccumulatedFrame())
            }
        }
        // Hills are often non-physics → include their frames too
        for h in hills where h.parent != nil {
            let fr = h.calculateAccumulatedFrame()
            if fr.intersects(region) { rects.append(fr) }
        }
        // Also include already-streamed ramps/enhancements hosted under obstacleRoot that block spawns
        for n in obstacleRoot.children where nodeBlocksSpawn(n) {
            let fr = n.calculateAccumulatedFrame()
            if fr.intersects(region) { rects.append(fr) }
        }
        return rects
    }
    
    @inline(__always)
    private func circleIntersectsAny(center: CGPoint, radius: CGFloat, rects: [CGRect]) -> Bool {
        for r in rects {
            if circleIntersectsRect(center: center, radius: radius, rect: r) { return true }
        }
        return false
    }
    
    // Which chunk does a point belong to?
    @inline(__always)
    private func chunkIndex(for p: CGPoint) -> (Int, Int) {
        let cx = Int(floor((p.x - worldBounds.minX) / chunkSize))
        let cy = Int(floor((p.y - worldBounds.minY) / chunkSize))
        return (cx, cy)
    }
    
    // Track dynamic obstacles under loadedChunks so streaming can unload them later
    @inline(__always)
    private func registerDynamicObstacle(_ n: SKNode, at p: CGPoint) {
        let (cx, cy) = chunkIndex(for: p)
        let key = chunkKey(cx: cx, cy: cy)
        if var arr = loadedChunks[key] {
            arr.append(n)
            loadedChunks[key] = arr
        } else {
            loadedChunks[key] = [n]
        }
    }
    
    // Drive the per-enemy spawning logic
    private func seedObstaclesFromEnemies() {
        let now = CACurrentMediaTime()
        for e in cars where e.kind == .enemy && !e.isDead {
            let id = ObjectIdentifier(e)
            let s  = enemyObstacleState[id] ?? (lastT: 0, lastPos: e.position, count: 0)
            
            // Basic gates: cooldown, travel distance, cap, stay in border band, don’t spawn on the player
            guard s.count < enemyObstacleMaxPerEnemy else { continue }
            guard now - s.lastT >= enemyObstacleCooldown else { continue }
            guard e.position.distance(to: s.lastPos) >= enemyObstacleTravelReq else { continue }
            guard worldBounds.contains(e.position) else { continue }
            guard car.position.distance(to: e.position) >= 220 else { continue }
            
            if maybeDropObstaclePack(from: e) {
                enemyObstacleState[id] = (lastT: now, lastPos: e.position, count: s.count + 1)
            }
        }
    }
    
    // Covers a circular-ish window around each active car (player + enemies),
    // then unions it with the camera rect so streaming stays robust even when
    // cars are off-screen.
    private var allCarPositions: [CGPoint] {
        var pts: [CGPoint] = [car.position]                // player
        let enemies = cars.filter { $0.kind == .enemy }
        for d in enemies { pts.append(d.position) }    // enemies
        return pts
    }
    
    private func carsStreamingRect(margin: CGFloat) -> CGRect {
        // preload radius around each car; using view size keeps it stable across zooms
        let base = max(size.width, size.height)
        let preloadRadius: CGFloat = base * 0.9 + margin
        
        // start from camera rect to keep the near-screen area always loaded
        var rect = cameraWorldRect(margin: margin)
        
        // union a square box around each car
        for p in allCarPositions {
            let box = CGRect(x: p.x - preloadRadius,
                             y: p.y - preloadRadius,
                             width: preloadRadius * 2,
                             height: preloadRadius * 2)
            rect = rect.union(box)
        }
        
        // keep it bounded and allow a tiny bleed so borders stream in cleanly
        return rect.intersection(worldBounds.insetBy(dx: -chunkSize, dy: -chunkSize))
    }
    
    
    // Try to place a small “pack” of obstacles near/just ahead of the enemy.
    // Returns true if anything was placed.
    @discardableResult
    private func maybeDropObstaclePack(from enemy: CarNode) -> Bool {
        var placedAny = false
        
        // Forward point ahead of the enemy
        let heading = enemy.zRotation + .pi/2
        let fwd = CGVector(dx: cos(heading), dy: sin(heading))
        let baseDist = CGFloat.random(in: 160...260)
        let base = CGPoint(x: enemy.position.x + fwd.dx * baseDist,
                           y: enemy.position.y + fwd.dy * baseDist)
        
        // 55% chance: a short cone "barrier" row perpendicular to heading.
        // 45%: scatter 1–2 singles ahead with small lateral offset.
        if CGFloat.random(in: 0...1) < 0.55 {
            // CONE ROW
            let rot = heading + .pi/2 + CGFloat.random(in: (-.pi/14)...(.pi/14))
            let count = Int.random(in: 4...6)
            
            let totalSpan = CGFloat(count - 1) * coneSpacing
            let start = CGPoint(x: base.x - cos(rot) * totalSpan * 0.5,
                                y: base.y - sin(rot) * totalSpan * 0.5)
            let end   = CGPoint(x: base.x + cos(rot) * totalSpan * 0.5,
                                y: base.y + sin(rot) * totalSpan * 0.5)
            
            let corridorMask: UInt32 = (Category.wall | Category.obstacle | Category.hole | Category.ramp)
            guard pathClearCapsule(from: start, to: end, radius: 24, mask: corridorMask) else { return placedAny }
            
            var localPlaced: [SKNode] = []
            for i in 0..<count {
                let t = CGFloat(i) - CGFloat(count-1)*0.5
                let p = CGPoint(x: base.x + cos(rot) * coneSpacing * t,
                                y: base.y + sin(rot) * coneSpacing * t)
                if let node = placeObstacleTracked(.cone, at: p, rotation: rot, skipPhysicsClearance: false) {
                    localPlaced.append(node)
                    registerDynamicObstacle(node, at: p)
                }
            }
            placedAny = !localPlaced.isEmpty
        } else {
            // SINGLE SCATTER (rock/barrel) — 1 or 2 pieces
            let singles = Int.random(in: 1...2)
            for _ in 0..<singles {
                let lat = CGFloat.random(in: -48...48)
                let lon = CGFloat.random(in: -20...40)
                let right = CGVector(dx: -sin(heading), dy: cos(heading))
                let p = CGPoint(x: base.x + fwd.dx * lon + right.dx * lat,
                                y: base.y + fwd.dy * lon + right.dy * lat)
                
                let kind: ObstacleKind = (CGFloat.random(in: 0...1) < 0.5) ? .rock : .barrel
                let rot = CGFloat.random(in: (-(.pi/8))...(.pi/8))
                if let node = placeObstacleTracked(kind, at: p, rotation: rot) {
                    registerDynamicObstacle(node, at: p)
                    placedAny = true
                }
            }
        }
        
        return placedAny
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
    
    // One pass over active hills: returns ground height and analytical gradient.
    @inline(__always)
    private func groundHeightAndGradient(at p: CGPoint) -> (height: CGFloat, grad: CGVector) {
        var bestH: CGFloat = 0
        var bestGrad = CGVector.zero
        
        for hill in hills where hill.parent != nil {
            let f = hill.calculateAccumulatedFrame()
            let cx = f.midX, cy = f.midY
            let rx = max(1, f.width * 0.5), ry = max(1, f.height * 0.5)
            
            // Normalized ellipse coords
            let dx = p.x - cx, dy = p.y - cy
            let nx = dx / rx,  ny = dy / ry
            let r  = sqrt(nx*nx + ny*ny)   // 1.0 ≈ edge
            
            if r > 1.05 { continue }       // tiny grace like your groundHeight()
            
            let inner: CGFloat = 0.35
            var h: CGFloat = 0
            var gx: CGFloat = 0, gy: CGFloat = 0
            
            if r <= inner {
                h = hill.topHeight
                // gradient 0 on the flat top
            } else {
                // smoothstep falloff: t = u^2 (3 - 2u), u in [0,1]
                let u = min(1, (r - inner) / max(0.0001, (1 - inner)))
                let t = u*u*(3 - 2*u)
                h = hill.topHeight * (1 - t)
                
                // analytical gradient on the slope band
                if r > 1e-5 && u > 0 && u < 1 {
                    let dt_du = 6*u*(1 - u)                     // d(u^2(3-2u))/du
                    let du_dr = 1 / max(1e-6, (1 - inner))
                    let dh_dr = -hill.topHeight * dt_du * du_dr
                    let dr_dx = dx / (r * rx * rx)
                    let dr_dy = dy / (r * ry * ry)
                    gx = dh_dr * dr_dx
                    gy = dh_dr * dr_dy
                }
            }
            
            if h > bestH { bestH = h; bestGrad = CGVector(dx: gx, dy: gy) }
        }
        
        return (bestH, bestGrad)
    }
    
    @inline(__always)
    private func applyHillModifiers(for car: CarNode, gh: CGFloat, gradient gvec: CGVector) {
        if gh < 16 {
            car.hillSpeedMul = 1
            car.hillAccelMul = 1
            car.hillDragK    = 0
            return
        }
        
        let gmag = hypot(gvec.dx, gvec.dy) * 0.5
        let slope = min(1, gmag / 28.0)
        
        let heading = car.zRotation + .pi/2
        let fwd = CGVector(dx: cos(heading), dy: sin(heading))
        let down = CGVector(dx: -gvec.dx, dy: -gvec.dy)
        
        let downLen = max(0.001, hypot(down.dx, down.dy))
        let downhillAlign = max(0, (fwd.dx * down.dx + fwd.dy * down.dy) / downLen)
        let uphillAlign   = max(0, -downhillAlign)
        
        car.hillSpeedMul = 1 - 0.30 * slope * uphillAlign
        car.hillAccelMul = 1 - 0.45 * slope * uphillAlign
        car.hillDragK    =  1.20 * slope * (1 - downhillAlign)
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
        case .worm:    debrisColors = [.systemPurple.withAlphaComponent(0.8),.systemPink.withAlphaComponent(0.6), .systemPink.withAlphaComponent(0.3),]
        case .steel:   debrisColors = [UIColor(white: 0.9, alpha: 1), UIColor(white: 0.6, alpha: 1)]
        case .hole:    return
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
        // your existing explode handling (camera shake, freeze, etc.)
        worms.removeAll()
        holeForWorm = [:]
        freezeCamera(at: car.position) // if you already have this helper
        pauseWorldForDeath()
    }
    
    private func freezeCamera(at pos: CGPoint) {
        cameraFrozenPos = pos      // uses your existing property
    }
    
    func carNodeRequestRespawnPoint(_ car: CarNode) -> CGPoint {
        // your existing respawn logic
        return safeSpawnPoint(in: cameraWorldRect(margin: 400).insetBy(dx: 120, dy: 120),
                              radius: spawnClearance)
    }
    
    private func pauseWorldForGameOver() {
        // Keep the scene responsive to touches; just stop physics & timers you own.
        physicsWorld.speed = 0
        isPaused = false
        cameraFrozenPos = car.position
    }
}

// =======================================
// GameScene — contacts: bullets & pickups
// =======================================
extension GameScene {
    // MARK: - SKPhysicsContactDelegate
    func didBegin(_ contact: SKPhysicsContact) {
        let a = contact.bodyA
        let b = contact.bodyB
        
        @inline(__always) func isCat(_ body: SKPhysicsBody, _ cat: UInt32) -> Bool { (body.categoryBitMask & cat) != 0 }
        @inline(__always) func isBullet(_ x: SKPhysicsBody) -> Bool { isCat(x, Category.bullet) }
        @inline(__always) func isCar(_ x: SKPhysicsBody) -> Bool { isCat(x, Category.car) }
        @inline(__always) func isObstacle(_ x: SKPhysicsBody) -> Bool { isCat(x, Category.obstacle) }
        @inline(__always) func isWall(_ x: SKPhysicsBody) -> Bool { isCat(x, Category.wall) }
        @inline(__always) func isRamp(_ x: SKPhysicsBody) -> Bool { isCat(x, Category.ramp) }
        @inline(__always) func isEnhancement(_ x: SKPhysicsBody) -> Bool { isCat(x, Category.enhancements) }
        @inline(__always) func isHill(_ x: SKPhysicsBody) -> Bool { x.node is HillNode }
        @inline(__always) func isWormSeg(_ x: SKPhysicsBody) -> Bool { x.node is WormSegmentNode }
        
        @inline(__always) func killBullet(_ body: SKPhysicsBody) {
            if let bn = body.node as? BulletNode { bn.playImpactFX(at: contact.contactPoint, in: self) }
            body.node?.removeAllActions()
            body.node?.removeFromParent()
        }
        
        // Helpful local helpers for worm logic
        @inline(__always) func isFrontImpact(car: CarNode, at p: CGPoint) -> Bool {
            let heading = car.zRotation + .pi/2
            let fwd = CGVector(dx: cos(heading), dy: sin(heading))
            let v   = CGVector(dx: p.x - car.position.x, dy: p.y - car.position.y)
            let len = max(0.001, hypot(v.dx, v.dy))
            let dot = (fwd.dx * v.dx + fwd.dy * v.dy) / len      // [-1,1]
            return dot > 0.45 // within ~63° cone in front
        }
        
        // ─────────────────────────────────────────────
        // Bullet ↔︎ WormSegment → damage that segment, remove bullet
        // (Do this BEFORE Bullet↔︎Obstacle so worm segments don't get treated as generic obstacles)
        // ─────────────────────────────────────────────
        if (isBullet(a) && isWormSeg(b)) || (isBullet(b) && isWormSeg(a)) {
            repeat {
                let a = contact.bodyA
                let b = contact.bodyB

                // find a WormSegmentNode and a bullet in the pair (order-agnostic)
                let seg = (a.node as? WormSegmentNode) ?? (b.node as? WormSegmentNode)
                let bulletNode: SKNode? =
                    ((a.categoryBitMask & Category.bullet) != 0) ? a.node :
                    ((b.categoryBitMask & Category.bullet) != 0) ? b.node : nil

                if let seg = seg, let bullet = bulletNode {
                    let dmg = (bullet.userData?["damage"] as? Int) ?? 40   // fallback damage
                    seg.worm?.damage(segment: seg, amount: dmg,
                                     at: contact.contactPoint, in: self)
                    bullet.removeAllActions()
                    bullet.removeFromParent()
                }
            } while false
        }
        
        // ─────────────────────────────────────────────
        // Car ↔︎ WormSegment → fixed crash damage (front 100, side 50)
        // ─────────────────────────────────────────────
        if (isCar(a) && isWormSeg(b)) || (isCar(b) && isWormSeg(a)) {
            let carBody = isCar(a) ? a : b
            let other   = isCar(a) ? b : a
            // let segBody = isWormSeg(a) ? a : b   // available if you want to react on worm side
            guard let carNode = carBody.node as? CarNode else { return }
            
            let front   = isFrontImpact(car: carNode, at: contact.contactPoint)
            let amount  = front ? 80 : 50
            
            carNode.handleCrash(contact: contact, other: other, damage: amount)
            
            if let seg = (other.node as? WormSegmentNode) {
                seg.worm?.damage(segment: seg, amount: 10, at: contact.contactPoint, in: self)
            }
            
            // Optional: small knockback so it "feels" like a bite/ram
            if let carPB = carNode.physicsBody {
                let hd = carNode.zRotation + .pi/2
                let dir = CGVector(dx: cos(hd), dy: sin(hd))
                carPB.applyImpulse(CGVector(dx: -dir.dx * 40, dy: -dir.dy * 40))
            }
            
            Audio.shared.noteCombatEvent(at: contact.contactPoint, intensity: front ? 0.4 : 0.25, now: CACurrentMediaTime())
            _hadSolidContactThisStep = true   // treat as a solid hit for this step’s “kick clamp”
            return
        }
        
        // ─────────────────────────────────────────────
        // Bullet ↔︎ Car  → apply projectile damage, then remove bullet
        // ─────────────────────────────────────────────
        if (isBullet(a) && isCar(b)) || (isBullet(b) && isCar(a)) {
            let bullet   = isBullet(a) ? a : b
            let carBody  = isCar(a)    ? a : b
            Audio.shared.noteCombatEvent(at: contact.contactPoint, intensity: 0.3, now: CACurrentMediaTime())
            if let target = carBody.node as? CarNode {
                // Optional friendly-fire guard
                if let shooter = bullet.node?.userData?["owner"] as? CarNode, shooter === target {
                    if let safe = bullet.node?.userData?["safeUntil"] as? TimeInterval, CACurrentMediaTime() < safe { return }
                    killBullet(bullet)
                    return
                }
                let dmg = (bullet.node as? BulletNode)?.damage ?? 10
                (bullet.node?.userData?["owner"] as? CarNode)?.rlNoteDealtDamage(dmg)
                target.receiveProjectile(damage: dmg, at: contact.contactPoint)
            }
            killBullet(bullet)
            return
        }
        
        // ─────────────────────────────────────────────
        // Car ↔︎ Car  → re-use your crash handler on both
        // ─────────────────────────────────────────────
        if isCar(a) && isCar(b) {
            Audio.shared.noteCombatEvent(at: contact.contactPoint, intensity: 0.1, now: CACurrentMediaTime())
            (a.node as? CarNode)?.handleCrash(contact: contact, other: b)
            (b.node as? CarNode)?.handleCrash(contact: contact, other: a)
            return
        }
        
        // Mark “solid” contact this step (used by your contact-boost clamp)
        if (isCar(a) && (isObstacle(b) || isWall(b) || isRamp(b))) ||
            (isCar(b) && (isObstacle(a) || isWall(a) || isRamp(a))) {
            _hadSolidContactThisStep = true
        }
        
        // ─────────────────────────────────────────────
        // Bullet ↔︎ Obstacle  → let the obstacle take damage, then remove bullet
        // ─────────────────────────────────────────────
        if (isBullet(a) && isObstacle(b)) || (isBullet(b) && isObstacle(a)) {
            let bullet   = isBullet(a) ? a : b
            let obstBody = isObstacle(a) ? a : b
            if let ob = obstBody.node as? ObstacleNode {
                let hitWorld = contact.contactPoint
                let hitLocal = ob.convert(hitWorld, from: self)
                let dmg = (bullet.node as? BulletNode)?.damage ?? 1
                (bullet.node?.userData?["owner"] as? CarNode)?.rlNoteDealtDamage(dmg)
                _ = ob.applyDamage(dmg, impact: hitLocal)
            }
            killBullet(bullet)
            return
        }
        
        // ─────────────────────────────────────────────
        // Bullet ↔︎ (Wall | Ramp | Hill) → just remove the bullet
        // ─────────────────────────────────────────────
        if isBullet(a) && (isWall(b) || isRamp(b) || isHill(b)) { killBullet(a); return }
        if isBullet(b) && (isWall(a) || isRamp(a) || isHill(a)) { killBullet(b); return }
        
        // ─────────────────────────────────────────────
        // Car ↔︎ Enhancement
        // ─────────────────────────────────────────────
        if (isCar(a) && isEnhancement(b)) || (isCar(b) && isEnhancement(a)) {
            let carBody = isCar(a) ? a : b
            let enhBody = isEnhancement(a) ? a : b
            guard let taker = carBody.node as? CarNode,
                  let node  = enhBody.node  as? EnhancementNode else { return }
            
            if taker.applyEnhancement(node.kind) {
                // One-shot: disable physics immediately so it can’t retrigger
                if let eb = node.physicsBody {
                    eb.categoryBitMask = 0
                    eb.contactTestBitMask = 0
                    eb.collisionBitMask = 0
                }
                
                node.run(.sequence([
                    .group([.scale(to: 1.25, duration: 0.08),
                            .fadeOut(withDuration: 0.10)]),
                    .removeFromParent()
                ]))
            } else {
                node.run(.sequence([.scale(to: 1.12, duration: 0.06),
                                    .scale(to: 1.00, duration: 0.12)]))
            }
            return
        }
        
        // ─────────────────────────────────────────────
        // Car ↔︎ Ramp → launch (no damage)
        // ─────────────────────────────────────────────
        if (isCar(a) && isRamp(b)) || (isCar(b) && isRamp(a)) {
            guard let carHit = (isCar(a) ? a.node : b.node) as? CarNode else { return }
            if carHit.isAirborne { return }      // avoid re-trigger mid-air
            guard let ramp = (isRamp(a) ? a.node : b.node) as? RampNode else { return }
            
            // Alignment (0..1) of car forward with ramp forward
            let carHeading = carHit.zRotation + .pi/2
            let align = max(0, cos(carHeading - ramp.heading))
            
            // Launch using CarNode’s air system (handles collision phasing + grace window)
            carHit.applyRampImpulse(
                vzAdd: ramp.strengthZ * max(0.55, align),
                forwardBoost: 120 * align,
                heading: ramp.heading
            )
            return
        }
        
        // ─────────────────────────────────────────────
        // Car ↔︎ (Obstacle | Wall)  → crash damage (never from hills)
        // ─────────────────────────────────────────────
        if (isCar(a) && isWall(b)) ||
            (isCar(b) && isWall(a)) {
            let carBody = isCar(a) ? a : b
            let other   = isCar(a) ? b : a
            (carBody.node as? CarNode)?.handleCrash(contact: contact, other: other)
            return
        }
        
        if (isCar(a) && isObstacle(b)) ||
            (isCar(b) && isObstacle(a)) {
            let carBody = isCar(a) ? a : b
            let other   = isCar(a) ? b : a
            
            let hitWorld = contact.contactPoint
            let hitLocal = (other.node as? ObstacleNode)?.convert(hitWorld, from: self)
            let dmg = 10
            
            if !isHill(other) {
                (other.node as? ObstacleNode)?.applyDamage(dmg, impact: hitLocal)
                (carBody.node as? CarNode)?.handleCrash(contact: contact, other: other)
            }
            return
        }
    }
    
    private func extractWormAndBullet(from c: SKPhysicsContact) -> (WormSegmentNode, SKNode)? {
        let a = c.bodyA.node, b = c.bodyB.node
        let segA = a as? WormSegmentNode
        let segB = b as? WormSegmentNode
        if let s = segA, b?.name == "bullet" { return (s, b!) }
        if let s = segB, a?.name == "bullet" { return (s, a!) }
        return nil
    }
    
    private func extractCarAndWorm(from c: SKPhysicsContact) -> (CarNode, WormSegmentNode)? {
        let a = c.bodyA.node, b = c.bodyB.node
        if let car = a as? CarNode, let seg = b as? WormSegmentNode { return (car, seg) }
        if let car = b as? CarNode, let seg = a as? WormSegmentNode { return (car, seg) }
        return nil
    }
    
    private func isFrontImpact(car: CarNode, at p: CGPoint) -> Bool {
        let heading = car.zRotation + .pi/2
        let fwd = CGVector(dx: cos(heading), dy: sin(heading))
        let v   = CGVector(dx: p.x - car.position.x, dy: p.y - car.position.y)
        let len = max(0.001, hypot(v.dx, v.dy))
        let dot = (fwd.dx * v.dx + fwd.dy * v.dy) / len      // [-1,1]
        return dot > 0.45 // >0.45 ≈ within ~63° of the front
    }
}

extension GameScene {
    
    // MARK: - RNG → kind
    @inline(__always)
    private func pickEnhancementKind(rng: inout SplitMix64) -> EnhancementKind {
        let roll = rng.unit()
        if roll < 0.22 { return .hp20 }
        else if roll < 0.44 { return .shield20 }
        else if roll < 0.62 { return .weaponRapid }
        else if roll < 0.76 { return .weaponDamage }
        else if roll < 0.88 { return .weaponSpread }
        else if roll < 0.94 { return .control }
        else { return .shrink }
    }
    
    // MARK: - Hills (80% chance, single open spawn near top)
    private func maybeSpawnEnhancement(on hill: HillNode, rng: inout SplitMix64) {
        if rng.unit() >= 0.80 { return }
        let kind = pickEnhancementKind(rng: &rng)
        let f = hill.calculateAccumulatedFrame()
        let p = CGPoint(
            x: rng.range((f.midX - f.width*0.12)...(f.midX + f.width*0.12)),
            y: rng.range((f.midY + f.height*0.02)...(f.midY + f.height*0.16))
        )
        _ = placeEnhancementTracked(kind, at: p)
    }
    
    // MARK: - Ground (independent rolls per chunk)
    // 40% behind a destructible obstacle; 10% open on ground.
    private func spawnGroundEnhancements(in rect: CGRect,
                                         nodesOut: inout [SKNode],
                                         cx: Int, cy: Int) {
        
        // ---- Behind obstacle roll (40%) ----
        let seedBehind = hash2(cx &* 11003 ^ 0x00BEEF, cy &* 22013 ^ 0x00FACE, seed: worldSeed ^ 0x4444_1111)
        var rngBehind = SplitMix64(seed: seedBehind)
        
        if rngBehind.unit() < 0.40,
           let ob = pickDestructibleObstacle(in: rect, rng: &rngBehind) {
            
            // Full ignore set: entire subtree + ancestor wrappers up to obstacleRoot
            let ignore = Array(subtreeSet(of: ob))
            
            if let p = pointBehindObstacle(ob,
                                           anchor: car.position,
                                           rng: &rngBehind,
                                           ignoring: ignore),
               let n = placeEnhancementTracked(pickEnhancementKind(rng: &rngBehind),
                                               at: p,
                                               ignoring: ignore) {
                nodesOut.append(n)
            }
        }
        
        // ---- Open-ground roll (10%) ----
        let seedOpen = hash2(cx &* 91079 ^ 0x00CAFE, cy &* 67819 ^ 0x00BEEF, seed: worldSeed ^ 0x9999_AAAA)
        var rngOpen = SplitMix64(seed: seedOpen)
        
        if rngOpen.unit() < 0.10,
           let p = randomOpenPoint(in: rect, rng: &rngOpen),
           let n = placeEnhancementTracked(pickEnhancementKind(rng: &rngOpen), at: p) {
            nodesOut.append(n)
        }
    }
    
    // MARK: - Pick an obstacle (physics-first, frame-fallback)
    // Any node with Category.obstacle counts. Optional soft filters.
    private func pickDestructibleObstacle(in rect: CGRect,
                                          rng: inout SplitMix64) -> SKNode? {
        // Try physics bodies first
        var bodies: [SKPhysicsBody] = []
        physicsWorld.enumerateBodies(in: rect.insetBy(dx: 24, dy: 24)) { body, _ in
            guard (body.categoryBitMask & Category.obstacle) != 0 else { return }
            guard let n = body.node else { return }
            if let d = n.userData?["destructible"] as? Bool, d == false { return }
            if let name = n.name?.lowercased(), name.contains("steel") { return }
            bodies.append(body)
        }
        
        if !bodies.isEmpty {
            let cx = rect.midX, cy = rect.midY
            let sorted = bodies.sorted {
                let a = $0.node!.position, b = $1.node!.position
                return hypot(a.x - cx, a.y - cy) < hypot(b.x - cx, b.y - cy)
            }
            let take = min(sorted.count, 8)
            return sorted[rng.int(0...(take - 1))].node
        }
        
        // Fallback: search obstacleRoot by frames (covers obstacles lacking category/multiple bodies)
        var candidates: [SKNode] = []
        obstacleRoot.enumerateChildNodes(withName: "//*") { n, _ in
            let fr = n.calculateAccumulatedFrame()
            if !fr.intersects(rect.insetBy(dx: 24, dy: 24)) { return }
            if let d = n.userData?["destructible"] as? Bool, d == false { return }
            if let name = n.name?.lowercased(), name.contains("steel") { return }
            candidates.append(n)
        }
        guard !candidates.isEmpty else { return nil }
        
        let cx = rect.midX, cy = rect.midY
        candidates.sort {
            hypot($0.position.x - cx, $0.position.y - cy)
            < hypot($1.position.x - cx, $1.position.y - cy)
        }
        return candidates[rng.int(0...min(7, candidates.count - 1))]
    }
    
    private func pointBehindObstacle(_ ob: SKNode,
                                     anchor: CGPoint,
                                     rng: inout SplitMix64,
                                     ignoring ignoreNodes: [SKNode] = []) -> CGPoint? {
        let ignoreSet = Set(ignoreNodes)
        
        let obWorld = ob.convert(CGPoint.zero, to: self)
        var dir = CGVector(dx: obWorld.x - anchor.x, dy: obWorld.y - anchor.y)
        let len = max(0.001, hypot(dir.dx, dir.dy))
        dir.dx /= len; dir.dy /= len
        let sx = -dir.dy, sy = dir.dx
        
        let maxRay: CGFloat = 2400
        let start = CGPoint(x: anchor.x - dir.dx * 6, y: anchor.y - dir.dy * 6)
        let end   = CGPoint(x: anchor.x + dir.dx * maxRay, y: anchor.y + dir.dy * maxRay)
        
        let baseGap: CGFloat = 64
        let attempts = 10
        // Include car in avoidance
        let avoid: UInt32 = Category.wall | Category.obstacle | Category.hole | Category.ramp | Category.enhancements | Category.car
        
        // 1) precise ray hit on the obstacle’s subtree
        if let hit = rayHitPoint(on: ob, start: start, end: end) {
            for step in 0..<attempts {
                let extra = CGFloat(step) * 10
                let lat = rng.range(CGFloat(-18.18)...CGFloat(18.18))
                let p = CGPoint(x: hit.x + dir.dx * (baseGap + extra) + sx * lat,
                                y: hit.y + dir.dy * (baseGap + extra) + sy * lat)
                if worldBounds.contains(p),
                   pointInBorderBand(p),
                   p.distance(to: car.position) >= 80,    // <— new buffer from car
                   clearanceOK(at: p, radius: 24, mask: avoid, ignoring: ignoreSet) {
                    return p
                }
            }
        }
        
        // 2) frame-radius fallback
        let fr  = ob.calculateAccumulatedFrame()
        let rad = 0.5 * max(fr.width, fr.height)
        for step in 0..<attempts {
            let extra = CGFloat(step) * 12
            let lat = rng.range(CGFloat(-20.20)...CGFloat(20.20))
            let p = CGPoint(x: fr.midX + dir.dx * (rad + baseGap + extra) + sx * lat,
                            y: fr.midY + dir.dy * (rad + baseGap + extra) + sy * lat)
            if worldBounds.contains(p),
               pointInBorderBand(p),
               p.distance(to: car.position) >= 80,        // <— new buffer from car
               clearanceOK(at: p, radius: 24, mask: avoid, ignoring: ignoreSet) {
                return p
            }
        }
        
        // 3) gentle sweep further out
        let sweepSteps = 24
        for step in 0..<sweepSteps {
            let out = baseGap + CGFloat(step) * 16
            let lat = rng.range(CGFloat(-24.24)...CGFloat(24.24))
            let p = CGPoint(x: obWorld.x + dir.dx * (rad + out) + sx * lat,
                            y: obWorld.y + dir.dy * (rad + out) + sy * lat)
            if worldBounds.contains(p),
               pointInBorderBand(p),
               p.distance(to: car.position) >= 80,        // <— new buffer from car
               clearanceOK(at: p, radius: 24, mask: avoid, ignoring: ignoreSet) {
                return p
            }
        }
        return nil
    }
    
    // MARK: - Raycast helper (closest hit on target's subtree)
    private func rayHitPoint(on target: SKNode, start: CGPoint, end: CGPoint) -> CGPoint? {
        let dx = end.x - start.x, dy = end.y - start.y
        if (dx*dx + dy*dy) < 1e-6 {
            return nil
        }
        
        var best: (dist: CGFloat, point: CGPoint)?
        physicsWorld.enumerateBodies(alongRayStart: start, end: end) { body, point, _, _ in
            guard (body.categoryBitMask & (Category.obstacle | Category.wall | Category.ramp)) != 0 else { return }
            guard let n = body.node else { return }
            guard n.inParentHierarchy(target) || target.inParentHierarchy(n) else { return }
            
            let d = hypot(point.x - start.x, point.y - start.y)
            if best == nil || d < best!.dist { best = (d, point) }
        }
        return best?.point
    }
    
    // MARK: - Open ground sampler
    // MARK: - Open ground sampler
    private func randomOpenPoint(in rect: CGRect, rng: inout SplitMix64) -> CGPoint? {
        // Also avoid the car
        let avoid: UInt32 = Category.wall | Category.obstacle | Category.hole | Category.ramp | Category.enhancements | Category.car
        for _ in 0..<24 {
            let p = CGPoint(
                x: rng.range(rect.minX...rect.maxX),
                y: rng.range(rect.minY...rect.maxY)
            )
            if worldBounds.contains(p),
               pointInBorderBand(p),
               clearanceOK(at: p, radius: 30, mask: avoid) {
                // Keep a little buffer from hills and the player
                var onHill = false
                for hill in hills where hill.parent != nil {
                    if hill.calculateAccumulatedFrame().insetBy(dx: -16, dy: -16).contains(p) { onHill = true; break }
                }
                if !onHill, p.distance(to: car.position) >= 80 {
                    return p
                }
            }
        }
        return nil
    }
    
    // MARK: - Place enhancement (with ignore threading)
    @discardableResult
    private func placeEnhancementTracked(_ kind: EnhancementKind,
                                         at p: CGPoint,
                                         ignoring ignore: [SKNode] = []) -> EnhancementNode? {
        // Also avoid the car by mask
        let avoidMask: UInt32 = Category.wall | Category.obstacle | Category.ramp | Category.hole | Category.enhancements | Category.car
        guard clearanceOK(at: p, radius: 24, mask: avoidMask, ignoring: Set(ignore)) else { return nil }
        
        // And enforce a hard distance from any active car (covers dynamic cases)
        for c in cars where c.parent != nil {
            if p.distance(to: c.position) < 80 { return nil }
        }
        
        let n = EnhancementNode(kind: kind)
        n.name = "enhancement"          // helps RL + debugging
        n.position = p
        n.zPosition = 3
        obstacleRoot.addChild(n)
        if let pb = n.physicsBody {
            pb.categoryBitMask    = Category.enhancements
            pb.collisionBitMask   = 0
            pb.contactTestBitMask = Category.car
            pb.isDynamic          = false
        }
        return n
    }
    
    
    // MARK: - Helper: full subtree + ancestor wrappers (for ignore set)
    private func subtreeSet(of root: SKNode) -> Set<SKNode> {
        var out: Set<SKNode> = [root]
        root.enumerateChildNodes(withName: "//*") { node, _ in out.insert(node) }
        var a = root.parent
        while let n = a, n !== obstacleRoot, n !== self {
            out.insert(n); a = n.parent
        }
        return out
    }
    
    // (Optional) quick debug breadcrumbs — comment out in production
#if DEBUG
    private func debugDot(_ p: CGPoint, _ c: UIColor) {
        let d = SKShapeNode(circleOfRadius: 4)
        d.position = p
        d.fillColor = c
        d.strokeColor = .clear
        d.zPosition = 9999
        addChild(d)
        d.run(.sequence([.wait(forDuration: 3), .fadeOut(withDuration: 0.2), .removeFromParent()]))
    }
#endif
}

// - Create property `enhHUD`
// - Place it in didMove(to:)
// - Re-place on didChangeSize(_:)
// - Tick in update(_:)
// - Handle Car ↔ Enhancement pickup in didBegin(_:) and show HUD

// Glue between pickups / CarNode state and .

extension GameScene {
    
    // 1) Call from didChangeSize (or wherever you already lay out HUD)
    
    // 2) Tick from update(_:)
    
    
    func updateHealthHUD() {
        healthHUD.set(hp: car.hp, maxHP: car.maxHP, shield: car.shield)
    }
    
    // 3) Call this right after a pickup is successfully applied to the car
    //    (i.e., after your game logic decides it can be taken).
    
    private func maybeSpawnWorm(car: CarNode, _ now: TimeInterval) {
        let time = 5.0
        DispatchQueue.main.asyncAfter(deadline: .now() + time) { [weak self] in
            guard let self else { return }
            let now  = now + time
            // throttle by time
            if now < nextWormAt { return }
            
            // cleanup stale handles
            worms.removeAll { $0.parent == nil }
            
            // cap live worms
            if worms.count >= maxLiveWorms {
                nextWormAt = now + 30.0
                return
            }
            
            let me = car.position
            
            // 1) Try to reuse a free hole near the player
            if let hole = freeHole(near: me, maxDist: 3200) {
                hole.userData = (hole.userData ?? NSMutableDictionary())
                hole.userData?["occupied"] = true
                let posScene = convert(hole.position, from: groundRoot)
                spawnWormFromHole(at: posScene)
                nextWormAt = now + TimeInterval.random(in: wormSpawnInterval)
                return
            }
            
            // 2) No hole? Create one in a safe ring around the player (kept away from obstacles)
            let preferredDistances: [CGFloat] = [780, 620, 980, 1100, 1000, 1300, 2000]
            var spot: CGPoint? = nil
            for dist in preferredDistances.shuffled() {
                if let p = findSafeHolePositionSpiral(
                    from: me,
                    step: 32, maxRadius: dist + 140,
                    samplesPerRing: 24,
                    avoidMask: holeAvoidMask,
                    withinAnnulus: (dist - 80)...(dist + 80)
                ) {
                    spot = p
                    break
                }
            }
            // Broader last-ditch search if the ring attempts failed
            if spot == nil {
                spot = findSafeHolePositionSpiral(
                    from: me,
                    step: 28, maxRadius: 800,
                    samplesPerRing: 28,
                    avoidMask: holeAvoidMask
                )
            }
            
            guard let place = spot else {
                // Scene is too crowded right now; try again soon.
                nextWormAt = now + 2.0
                return
            }
            
            // Create hole and then have a worm emerge from it shortly after (so you can see it)
            let hole = spawnHole(at: place, ttl: 12.0)
            hole.userData = (hole.userData ?? NSMutableDictionary())
            hole.userData?["occupied"] = true
            
            run(.sequence([
                .wait(forDuration: 0.25),
                .run { [weak self] in self?.spawnWormFromHole(at: place) }
            ]))
            
            nextWormAt = now + TimeInterval.random(in: wormSpawnInterval)
        }
    }
    
    // e.g., call when a worm is removed elsewhere
    private func onWormRemoved(_ w: WormNode) {
        if let hole = holeForWorm.removeValue(forKey: ObjectIdentifier(w)) {
            hole.run(.sequence([.fadeOut(withDuration: 0.18), .removeFromParent()]))
        }
    }
}

// Keep HUD in sync with CarNode state changes that don’t come directly
// from a pickup (e.g., death/reset, shield consumed, etc.).
extension GameScene: CarShieldReporting, CarWeaponReporting, CarStatusReporting {
    
    // Called by CarNode whenever shield value changes.
    func onShieldChanged(_ value: Int) {
        updateHealthHUD()
    }
    
    // Called by CarNode whenever weapon mode changes (including reset).
    func onWeaponChanged(_ name: String) {
        //        switch car.weaponMod {
        //        case .rapid:
        //            .setPersistent(.weaponRapid,  active: true)
        //            .setPersistent(.weaponDamage, active: false)
        //            .setPersistent(.weaponSpread, active: false)
        //        case .damage:
        //            .setPersistent(.weaponRapid,  active: false)
        //            .setPersistent(.weaponDamage, active: true)
        //            .setPersistent(.weaponSpread, active: false)
        //        case .spread:
        //            .setPersistent(.weaponRapid,  active: false)
        //            .setPersistent(.weaponDamage, active: false)
        //            .setPersistent(.weaponSpread, active: true)
        //        default:
        //            .setPersistent(.weaponRapid,  active: false)
        //            .setPersistent(.weaponDamage, active: false)
        //            .setPersistent(.weaponSpread, active: false)
        //        }
    }
    
    func onControlBoostChanged(_ active: Bool) {
    }
    
    func onMiniModeChanged(_ active: Bool) {
        
        // Only scale; no ring/poof or pulse UI on the car
        let target: CGFloat = active ? 0.9 : 1.0
        car.removeAction(forKey: "miniScale")
        let scale = SKAction.scale(to: target, duration: 0.18)
        scale.timingMode = .easeOut
        car.run(scale, withKey: "miniScale")
    }
}

extension GameScene {
    func playShrinkPoof(at p: CGPoint) {
        let r: CGFloat = 36
        let ring = SKShapeNode(circleOfRadius: r)
        ring.position = p
        ring.strokeColor = UIColor.white.withAlphaComponent(0.75)
        ring.fillColor = .clear
        ring.lineWidth = 2
        ring.glowWidth = 4
        addChild(ring)
        ring.run(.sequence([
            .group([.scale(to: 1.35, duration: 0.22), .fadeAlpha(to: 0, duration: 0.22)]),
            .removeFromParent()
        ]))
    }
}

extension GameScene {
    
    // MARK: glyph nodes
    private var weaponGlyph: SKShapeNode {
        if let n = fireButton.childNode(withName: "_weaponGlyph") as? SKShapeNode {
            return n
        }
        let n = SKShapeNode()
        n.name = "_weaponGlyph"
        n.zPosition = fireButton.zPosition + 1
        n.strokeColor = .clear
        n.fillColor = .white
        fireButton.addChild(n)
        layoutWeaponGlyph()
        return n
    }
    
    func buildWeaponGlyph() {
        _ = weaponGlyph // ensure exists
        refreshWeaponGlyph()
    }
    
    func layoutWeaponGlyph() {
        guard let n = fireButton.childNode(withName: "_weaponGlyph") as? SKShapeNode else { return }
        // 18×18 icon at top-left of button
        let r: CGFloat = 9
        n.path = CGPath(ellipseIn: CGRect(x: -r, y: -r, width: r*2, height: r*2), transform: nil)
        n.position = CGPoint(x: -28, y: 28)
    }
    
    func refreshWeaponGlyph() {
        guard let n = fireButton.childNode(withName: "_weaponGlyph") as? SKShapeNode else { return }
        
        switch car.weaponMod {
        case .rapid:
            n.fillColor = .systemYellow
            n.path = CGPath(ellipseIn: CGRect(x: -9, y: -9, width: 18, height: 18), transform: nil)
            
        case .damage:
            // triangle
            let p = CGMutablePath()
            p.move(to: CGPoint(x: 0, y: 10))
            p.addLine(to: CGPoint(x: 8, y: -8))
            p.addLine(to: CGPoint(x: -8, y: -8))
            p.closeSubpath()
            n.path = p
            n.fillColor = .systemOrange
            
        case .spread:
            // three dots
            let p = CGMutablePath()
            for x in [-6, 0, 6] {
                p.addEllipse(in: CGRect(x: x-2, y: -2, width: 4, height: 4))
            }
            n.path = p
            n.fillColor = .systemPurple
            
        default:
            n.fillColor = .white
            n.path = CGPath(ellipseIn: CGRect(x: -9, y: -9, width: 18, height: 18), transform: nil)
        }
    }
}

// ===== Drive arrow color helpers =====
extension GameScene {
    private func setDriveArrowColors(up: Bool, down: Bool, left: Bool, right: Bool, highlight: UIColor) {
        let hc = highlight.withAlphaComponent(0.95)
        driveArrowUp.strokeColor    = up    ? hc : driveArrowInactive
        driveArrowDown.strokeColor  = down  ? hc : driveArrowInactive
        driveArrowLeft.strokeColor  = left  ? hc : driveArrowInactive
        driveArrowRight.strokeColor = right ? hc : driveArrowInactive
    }
    
    private func updateDriveArrows(fromInput v: CGVector, tNorm: CGFloat, activeBand: Int) {
        guard tNorm > 0.05, v.dx.isFinite, v.dy.isFinite else {
            let c = (activeBand >= 0 && activeBand < ringPalette.count) ? ringPalette[activeBand] : .systemTeal
            setDriveArrowColors(up: false, down: false, left: false, right: false, highlight: c)
            return
        }
        let mag = max(1e-6, hypot(v.dx, v.dy))
        let nx = v.dx / mag, ny = v.dy / mag
        let thresh: CGFloat = 0.35
        let up    = ny >  thresh
        let down  = ny < -thresh
        let right = nx >  thresh
        let left  = nx < -thresh
        
        let c = (activeBand >= 0 && activeBand < ringPalette.count) ? ringPalette[activeBand] : .systemTeal
        setDriveArrowColors(up: up, down: down, left: left, right: right, highlight: c)
    }
}

extension GameScene {
    var agent: CarNode { car }   // exposes the player car to the helpers
}

// MARK: - RL card toggle (matches HUD cards)
final class RLCardToggle: SKNode {
    var isOn: Bool = false { didSet { refresh() } }
    var onChanged: ((Bool) -> Void)?
    
    private let card = SKShapeNode()
    private let title = SKLabelNode(fontNamed: "Menlo-Bold")
    private let switchBG = SKShapeNode()
    private let knob = SKShapeNode(circleOfRadius: 9)
    private let sizePx: CGSize
    
    init(size: CGSize = .init(width: 172, height: 44)) {
        self.sizePx = size
        super.init()
        isUserInteractionEnabled = true
        zPosition = 400 // same layer as other HUD cards
        
        // Card like other UI
        let r = CGRect(x: -size.width/2, y: -size.height/2, width: size.width, height: size.height)
        card.path = CGPath(roundedRect: r, cornerWidth: 14, cornerHeight: 14, transform: nil)
        card.fillColor = UIColor(white: 0, alpha: 0.28)
        card.strokeColor = UIColor(white: 1, alpha: 0.10)
        card.lineWidth = 1.0
        card.glowWidth = 2
        addChild(card)
        
        // Title
        title.fontSize = 12
        title.verticalAlignmentMode = .center
        title.horizontalAlignmentMode = .left
        title.fontColor = UIColor.white.withAlphaComponent(0.85)
        title.position = CGPoint(x: -size.width/2 + 14, y: 0)
        addChild(title)
        
        // Tiny switch on the right (inside the card)
        let sw = CGSize(width: 56, height: 22)
        let srect = CGRect(x: -sw.width/2, y: -sw.height/2, width: sw.width, height: sw.height)
        switchBG.path = CGPath(roundedRect: srect, cornerWidth: sw.height/2, cornerHeight: sw.height/2, transform: nil)
        switchBG.fillColor = UIColor(white: 0.12, alpha: 0.95)
        switchBG.strokeColor = UIColor.white.withAlphaComponent(0.18)
        switchBG.lineWidth = 1
        switchBG.position = CGPoint(x: size.width/2 - 14 - sw.width/2, y: 0)
        addChild(switchBG)
        
        knob.fillColor = .white
        knob.strokeColor = UIColor.black.withAlphaComponent(0.25)
        knob.lineWidth = 1
        switchBG.addChild(knob)
        
        isUserInteractionEnabled = CarNode.hasPolicyAvailable(named: "IonCircuitPolicy")
        
        refresh()
    }
    
    required init?(coder: NSCoder) { fatalError() }
    
    private func refresh() {
        // Move knob left/right and tint the border to match state
        let sw = switchBG.frame.size
        let inset: CGFloat = 6
        let xLeft  = -sw.width/2 + inset + 9
        let xRight =  sw.width/2 - inset - 9
        knob.position = CGPoint(x: isOn ? xRight : xLeft, y: 0)
        let accent = isOn ? UIColor.systemTeal : UIColor.systemGray
        knob.fillColor = accent.withAlphaComponent(0.55)
        
        title.text = isOn ? "train" : "play"
    }
    
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        run(.sequence([.scale(to: 0.98, duration: 0.04), .scale(to: 1.0, duration: 0.08)]))
        isOn.toggle()
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        title.text = isOn ? "train" : "play"
        onChanged?(isOn)
    }
}
