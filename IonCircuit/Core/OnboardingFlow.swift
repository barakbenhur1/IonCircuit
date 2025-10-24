//
//  OnboardingFlow.swift
//  IonCircuit
//
//  Created by Barak Ben Hur on 22/10/2025.
//

import SpriteKit
import UIKit
import ObjectiveC

// MARK: - Persistent flags
enum OnboardKeys {
    static let finishedTutorial = "onboard.finishedTutorial.v1"
    static let choseHandedness  = "onboard.choseHandedness.v1"
    static let chosenSideRaw    = "onboard.chosenSide.v1"
}

// MARK: - Public tiny API
protocol OnboardingControllable: AnyObject {
    func startOnboardingFlowTutorialFirst()
    func syncOnboardingUIWithCamera()
}

// MARK: - GameScene integration
extension GameScene: OnboardingControllable {

    enum OnboardingState { case idle, tutorial, handedness, done }

    private struct Assoc { static var state = 0; static var uiRoot = 0 }
    var onboardingState: OnboardingState {
        get { (objc_getAssociatedObject(self, &Assoc.state) as? OnboardingState) ?? .idle }
        set { objc_setAssociatedObject(self, &Assoc.state, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC) }
    }

    // Screen-fixed overlay root
    private var uiRoot: SKNode {
        if let n = objc_getAssociatedObject(self, &Assoc.uiRoot) as? SKNode { return n }
        let n = SKNode()
        n.zPosition = 10000
        // ✅ Always attach (if camera is nil at this moment, fall back to scene)
        (camera ?? self).addChild(n)
        objc_setAssociatedObject(self, &Assoc.uiRoot, n, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        return n
    }

    public func startOnboardingFlowTutorialFirst() {
        guard onboardingState == .idle else { return }
        if !aiControlsPlayer && !UserDefaults.standard.bool(forKey: OnboardKeys.finishedTutorial) {
            presentTutorial()
        } else {
            if !aiControlsPlayer {
                self.uiRoot.removeAllChildren()
                showHandednessPicker()   // wrapper added below
            } else {
                onboardingState = .done
            }
        }
    }

    // Keep overlays screen-fixed regardless of camera transforms
    public func syncOnboardingUIWithCamera() {
        if let cam = camera {
            // If uiRoot isn't under the camera yet (e.g., camera set later), move it.
            if uiRoot.parent !== cam {
                uiRoot.removeFromParent()
                cam.addChild(uiRoot)
            }
            let invX = 1.0 / max(cam.xScale, 0.0001)
            let invY = 1.0 / max(cam.yScale, 0.0001)
            uiRoot.xScale = invX
            uiRoot.yScale = invY
            uiRoot.zRotation = -cam.zRotation
            uiRoot.position = .zero
        } else {
            // Still keep it centered on screen coordinates
            uiRoot.xScale = 1.0
            uiRoot.yScale = 1.0
            uiRoot.zRotation = 0.0
            uiRoot.position = .zero
        }

        // Use real view bounds/safe area for layout.
        let screenSize = view?.bounds.size ?? size
        let insets = view?.safeAreaInsets ?? .zero

        if let t = uiRoot.children.first as? TutorialOverlay {
            t.relayout(screenSize: screenSize, safeInsets: insets)
        } else if let h = uiRoot.children.first as? HandednessOverlay {
            h.relayout(screenSize: screenSize, safeInsets: insets)
        }
    }

    private func presentTutorial() {
        onboardingState = .tutorial
        uiRoot.removeAllChildren()

        let overlay = TutorialOverlay(
            screenSize: view?.bounds.size ?? size,
            safeInsets: view?.safeAreaInsets ?? .zero
        )
        overlay.onFinish = { [weak self] in
            guard let self else { return }
            UserDefaults.standard.set(true, forKey: OnboardKeys.finishedTutorial)
            if !aiControlsPlayer {
                self.uiRoot.removeAllChildren()
                self.showHandednessPicker()
            } else {
                self.onboardingState = .done
            }
        }
        uiRoot.addChild(overlay)
        syncOnboardingUIWithCamera()
    }

    private func presentHandedness() {
        onboardingState = .handedness
        uiRoot.removeAllChildren()

        let overlay = HandednessOverlay(
            screenSize: view?.bounds.size ?? size,
            safeInsets: view?.safeAreaInsets ?? .zero
        )
        overlay.onChoose = { [weak self] side in
            guard let self else { return }
            UserDefaults.standard.set(true, forKey: OnboardKeys.choseHandedness)
            UserDefaults.standard.set(side == .left ? "left" : "right", forKey: OnboardKeys.chosenSideRaw)
            self.onboardingState = .done
            self.uiRoot.removeAllChildren()
            // self.configureControls(for: side)
        }
        uiRoot.addChild(overlay)
        syncOnboardingUIWithCamera()
    }
}

// MARK: - Button
final class SKTapButton: SKNode {
    var onTap: (() -> Void)?
    private let bg: SKShapeNode
    private let label: SKLabelNode

    init(title: String, size: CGSize) {
        bg = SKShapeNode(rectOf: size, cornerRadius: 12)
        bg.fillColor = UIColor(white: 0.10, alpha: 0.94)
        bg.strokeColor = UIColor.white.withAlphaComponent(0.25)
        bg.lineWidth = 1

        label = SKLabelNode(fontNamed: "Avenir-Heavy")
        label.text = title
        label.fontSize = 18
        label.verticalAlignmentMode = .center
        label.horizontalAlignmentMode = .center

        super.init()
        isUserInteractionEnabled = true
        addChild(bg); addChild(label)
    }
    required init?(coder: NSCoder) { fatalError() }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        bg.run(.sequence([.scale(to: 0.98, duration: 0.05), .scale(to: 1.0, duration: 0.08)]))
        onTap?()
    }
}

// MARK: - Tutorial (full-screen, centered, zoom-proof)
final class TutorialOverlay: SKNode {
    var onFinish: (() -> Void)?

    private let pages: [(title: String, bullets: [String])] = [
        ("Movement",
         ["Steer with the wheel",
          "Throttle & brake on the center of the wheel",
          "Keep momentum"]),
        ("Combat",
         ["Tap the crosshair to fire",
          "Mods: Rapid / Damage / Spread",
          "Flank for higher damage"]),
        ("Pickups",
         ["❤️ Health +20",
          "🛡 Shield absorbs damage",
          "⚡ Control boost",
          "🌀 Shrink: smaller car"]),
        ("Terrain",
         ["Obstacles time loss, take damage",
          "Worms: they are the worst be careful, time loss, big damage",
          "Hills reduce grip & speed",
          "Ramps launch you—carry speed",
          "Walls: time loss, no damage"]),
        ("Win Rounds",
         ["Destroy the opponent to remove a life",
          "Low HP? kite, heal, survive"])
    ]

    private let bg: SKSpriteNode
    private let titleLabel = SKLabelNode(fontNamed: "Avenir-Heavy")
    private var bulletNodes: [SKLabelNode] = []
    private var dots: [SKShapeNode] = []
    private var nextBtn: SKTapButton!
    private var skipBtn: SKTapButton!

    private var screenSize: CGSize
    private var insets: UIEdgeInsets
    private var page = 0

    // swipe
    private var touchStart: CGPoint = .zero
    private var touchTime: TimeInterval = 0

    init(screenSize: CGSize, safeInsets: UIEdgeInsets) {
        self.screenSize = screenSize
        self.insets = safeInsets

        bg = SKSpriteNode(color: UIColor(red: 0.02, green: 0.06, blue: 0.12, alpha: 0.98),
                          size: screenSize)
        bg.zPosition = -1
        bg.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        bg.position = .zero

        super.init()
        isUserInteractionEnabled = true

        addChild(bg)

        titleLabel.fontSize = 26
        titleLabel.fontColor = .green
        titleLabel.horizontalAlignmentMode = .center
        titleLabel.verticalAlignmentMode = .center
        addChild(titleLabel)

        for _ in 0..<6 {
            let l = SKLabelNode(fontNamed: "Avenir-Medium")
            l.fontSize = 18
            l.alpha = 0.94
            l.horizontalAlignmentMode = .left
            l.verticalAlignmentMode = .center
            bulletNodes.append(l)
            addChild(l)
        }

        for _ in 0..<pages.count {
            let d = SKShapeNode(circleOfRadius: 4)
            d.fillColor = .white
            d.alpha = 0.3
            d.strokeColor = .clear
            dots.append(d)
            addChild(d)
        }

        let btnW = (min(520, screenSize.width - insets.left - insets.right - 48) - 12)/2
        nextBtn = SKTapButton(title: "Next ▶︎", size: CGSize(width: btnW, height: 48))
        skipBtn = SKTapButton(title: "Skip",    size: CGSize(width: btnW, height: 48))
        addChild(nextBtn); addChild(skipBtn)

        nextBtn.onTap = { [weak self] in self?.advance() }
        skipBtn.onTap = { [weak self] in self?.finish() }

        relayout(screenSize: screenSize, safeInsets: safeInsets)
        applyPage()
    }

    required init?(coder: NSCoder) { fatalError() }

    func relayout(screenSize: CGSize, safeInsets: UIEdgeInsets) {
        self.screenSize = screenSize
        self.insets = safeInsets

        // Oversize ×3 to absolutely cover the viewport
        let k: CGFloat = 3.0
        bg.size = CGSize(width: screenSize.width * k, height: screenSize.height * k)
        bg.position = .zero

        // centered coordinates
        let left   = -screenSize.width/2  + safeInsets.left  + 24
        let right  =  screenSize.width/2  - safeInsets.right - 24
        let topY   =  screenSize.height/2 - safeInsets.top   - 28
        let botY   = -screenSize.height/2 + safeInsets.bottom + 24

        let contentW = right - left

        titleLabel.position = CGPoint(x: 0, y: topY - 24)

        let firstY = titleLabel.position.y - 56
        for (i, l) in bulletNodes.enumerated() {
            l.preferredMaxLayoutWidth = contentW
            l.position = CGPoint(x: left, y: firstY - CGFloat(i) * 34)
        }

        let dotsY: CGFloat = botY + 72
        let spacing: CGFloat = 16
        let totalW = spacing * CGFloat(max(0, dots.count - 1))
        for (i, d) in dots.enumerated() {
            d.position = CGPoint(x: -totalW/2 + CGFloat(i)*spacing, y: dotsY)
        }

        let btnY = botY + 28
        let bw = (min(520, screenSize.width - insets.left - insets.right - 48) - 12)/2
        nextBtn.position = CGPoint(x: +bw/2 + 6, y: btnY)
        skipBtn.position = CGPoint(x: -bw/2 - 6, y: btnY)
    }

    private func applyPage() {
        let p = pages[page]
        titleLabel.text = p.title

        for (i, node) in bulletNodes.enumerated() {
            if i < p.bullets.count {
                node.text = "• " + p.bullets[i]
                node.isHidden = false
            } else {
                node.isHidden = true
            }
        }

        for (i, d) in dots.enumerated() {
            d.alpha = i == page ? 1.0 : 0.3
            d.setScale(i == page ? 1.2 : 1.0)
        }
        if let lab = nextBtn.children.compactMap({ $0 as? SKLabelNode }).first {
            lab.text = (page == pages.count - 1) ? "Finish" : "Next ▶︎"
        }
    }

    private func advance() {
        if page < pages.count - 1 {
            page += 1
            applyPage()
        } else {
            finish()
        }
    }

    private func finish() { onFinish?() }

    // Swipe support
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        if let t = touches.first {
            touchStart = t.location(in: self)
            touchTime = t.timestamp
        }
    }
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let t = touches.first else { return }
        let end = t.location(in: self)
        let dx = end.x - touchStart.x
        let dt = CGFloat(t.timestamp - touchTime)
        if abs(dx) > 40 && dt < 0.6 {
            if dx < 0 { advance() }
            else if page > 0 { page -= 1; applyPage() }
        }
    }
}

// MARK: - Handedness overlay (centered card, zoom-proof)
final class HandednessOverlay: SKNode {
    enum Side { case left, right }
    var onChoose: ((Side) -> Void)?

    private let dim: SKSpriteNode
    private let card = SKShapeNode()

    private var screenSize: CGSize
    private var insets: UIEdgeInsets

    init(screenSize: CGSize, safeInsets: UIEdgeInsets) {
        self.screenSize = screenSize
        self.insets = safeInsets

        dim = SKSpriteNode(color: UIColor.black.withAlphaComponent(0.55), size: screenSize)
        dim.zPosition = -1
        dim.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        dim.position = .zero

        super.init()

        addChild(dim)

        let cardW = min(screenSize.width - 40, 380)
        let cardH: CGFloat = 240
        card.path = CGPath(roundedRect: CGRect(x: -cardW/2, y: -cardH/2, width: cardW, height: cardH),
                           cornerWidth: 18, cornerHeight: 18, transform: nil)
        card.fillColor = UIColor(white: 0.08, alpha: 0.96)
        card.strokeColor = UIColor.white.withAlphaComponent(0.18)
        card.lineWidth = 1
        addChild(card)

        let title = SKLabelNode(fontNamed: "Avenir-Heavy")
        title.text = "Pick your control side"
        title.fontSize = 22
        title.verticalAlignmentMode = .center
        title.horizontalAlignmentMode = .center
        title.position = CGPoint(x: 0, y: cardH/2 - 50)
        card.addChild(title)

        let hint = SKLabelNode(fontNamed: "Avenir-Medium")
        hint.text = "You can change this later in Settings"
        hint.fontSize = 14
        hint.alpha = 0.82
        hint.verticalAlignmentMode = .center
        hint.horizontalAlignmentMode = .center
        hint.position = CGPoint(x: 0, y: cardH/2 - 78)
        card.addChild(hint)

        let btnSize = CGSize(width: (cardW - 60)/2, height: 48)
        let leftBtn  = SKTapButton(title: "Left-handed",  size: btnSize)
        let rightBtn = SKTapButton(title: "Right-handed", size: btnSize)
        leftBtn.position  = CGPoint(x: -btnSize.width/2 - 10, y: -20)
        rightBtn.position = CGPoint(x:  btnSize.width/2 + 10, y: -20)
        leftBtn.onTap  = { [weak self] in self?.onChoose?(.left) }
        rightBtn.onTap = { [weak self] in self?.onChoose?(.right) }
        card.addChild(leftBtn); card.addChild(rightBtn)

        relayout(screenSize: screenSize, safeInsets: safeInsets)
    }

    required init?(coder: NSCoder) { fatalError() }

    func relayout(screenSize: CGSize, safeInsets: UIEdgeInsets) {
        self.screenSize = screenSize
        self.insets = safeInsets

        let k: CGFloat = 3.0
        dim.size = CGSize(width: screenSize.width * k, height: screenSize.height * k)
        dim.position = .zero

        // Center card on screen
        card.position = .zero
    }
}
