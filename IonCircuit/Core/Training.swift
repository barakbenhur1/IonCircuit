//
//  Training.swift
//  IonCircuit
//
//  Created by Barak Ben Hur on 22/10/2025.
//

import Foundation
import Network
import SpriteKit
#if canImport(CoreML)
import CoreML
#endif

// MARK: - Policy installer
enum PolicyInstaller {
    static func installedPoliciesDirectory() throws -> URL {
        let fm = FileManager.default
        let base = try fm.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let dir  = base.appendingPathComponent("Policies", isDirectory: true)
        if !fm.fileExists(atPath: dir.path) {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    /// Install from raw bytes (.mlmodel or compiled). Returns final .mlmodelc folder URL.
    @discardableResult
    static func installPolicyData(_ data: Data, named name: String) async throws -> URL {
        let fm = FileManager.default
        let dir = try installedPoliciesDirectory()
        let dest = dir.appendingPathComponent("\(name).mlmodelc", isDirectory: true)

        let stage = dir.appendingPathComponent(".staging-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: stage, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: stage) }

        let raw = stage.appendingPathComponent("\(name).mlmodel")
        try data.write(to: raw, options: .atomic)

        #if canImport(CoreML)
        let compiled = (try? await MLModel.compileModel(at: raw)) ?? raw

        let stagedBundle: URL
        if (try? compiled.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true,
           compiled.pathExtension == "mlmodelc" {
            stagedBundle = stage.appendingPathComponent("\(name).mlmodelc", isDirectory: true)
            if fm.fileExists(atPath: stagedBundle.path) { try fm.removeItem(at: stagedBundle) }
            try fm.copyItem(at: compiled, to: stagedBundle)
        } else {
            let wrap = stage.appendingPathComponent("\(name).mlmodelc", isDirectory: true)
            try fm.createDirectory(at: wrap, withIntermediateDirectories: true)
            let inside = wrap.appendingPathComponent(compiled.lastPathComponent)
            try fm.moveItem(at: compiled, to: inside)
            stagedBundle = wrap
        }

        _ = try fm.replaceItemAt(dest, withItemAt: stagedBundle, backupItemName: nil, options: .usingNewMetadataOnly)
        print("✅ Saved/updated policy:", dest.path)
        return dest
        #else
        throw NSError(domain: "RLPolicy", code: 2,
                      userInfo: [NSLocalizedDescriptionKey: "CoreML unavailable to compile .mlmodel"])
        #endif
    }
}

// MARK: - RL server (SpriteKit touches are marshalled to MainActor)
final class RLServer {
    private let listener: NWListener
    private weak var scene: SKScene?
    private weak var agent: CarNode?
    private weak var target: CarNode?

    private var prevAgentHP = 0
    private var prevTargetLives = 0
    private var stepCount = 0
    private let maxSteps = 2048
    
    var isRunning: Bool = false
    
    private let didSave: (() -> ())?

    init(scene: SKScene, agent: CarNode, target: CarNode, port: UInt16 = 5556, didSave: (() -> ())? = nil) throws {
        self.scene = scene
        self.agent = agent
        self.target = target
        self.didSave = didSave

        let nwPort = NWEndpoint.Port(rawValue: port)!
        listener = try NWListener(using: .tcp, on: nwPort)
        listener.newConnectionHandler = { [weak self] c in
            guard let self else { return }
            let line = ICLineConn(c)  // from Wire.swift
            line.start()
            isRunning = true
            self.handle(line)
        }
    }

    func start() { listener.start(queue: .global()) }
    func stop()  { listener.cancel() }

    private func resetEpisode() async -> ICWireResp {
        guard let agent, let target else { return ICWireResp(obs: [], reward: 0, done: true) }
        stepCount = 0
        prevAgentHP     = await MainActor.run { agent.hp }
        prevTargetLives = await MainActor.run { target.livesLeft }
        let obs = await MainActor.run { target.rlObservation() }
        return ICWireResp(obs: obs, reward: 0, done: false)
    }

    private func stepOnce(throttle: CGFloat, steer: CGFloat, fire: Bool) async -> ICWireResp {
        guard let scene, let agent, let target else {
            return ICWireResp(obs: [], reward: 0, done: true)
        }

        var reward: Double = 0
        var done = false

        await MainActor.run {
            let dt: CGFloat = 1.0 / 60.0

            // 1) Apply controls. CarNode.update(_:) will handle rotation/traction.
            let t = max(-1, min(1, throttle))
            let s = max(-1, min(1, steer))
            precondition(t.isFinite && s.isFinite)
            agent.setControls(throttle: t, steer: s, fire: fire, reverseIntent: t < -0.1)

            // 2) Fire gating (don’t force-fire if tactically bad).
            if fire, (scene as? GameScene)?.aiShouldFire(shooter: agent, at: target) == true {
                agent.startAutoFire(on: scene)
            } else {
                agent.stopAutoFire()
            }

            // 3) Advance simulation exactly one tick. This calls CarNode.update(dt:).
            agent.stepOnceForTraining(dt: dt)

            // 4) HUD (optional).
            agent.refreshMiniHUD()

            // 5) Reward shaping.
            stepCount += 1
            let v = agent.physicsBody?.velocity ?? .zero
            let spd = hypot(v.dx, v.dy)

            let tookDamage = -max(0, prevAgentHP - agent.hp)
            prevAgentHP = agent.hp

            let speedTerm = Double(spd) / 400.0
            var killBonus = 0.0
            let tl = target.livesLeft
            if tl < prevTargetLives {
                killBonus = 5.0
                prevTargetLives = tl
            }

            let deathPenalty   = agent.isDead ? -3.0 : 0.0
            let reversePenalty = agent.consumeReversePenalty()
            let wallPenalty    = agent.consumeWallPenalty()
            let winBonus       = agent.consumeWinBonus()
            let losePenalty    = agent.consumeLosePenalty()

            reward = 0.001 + speedTerm + 0.20 * Double(tookDamage)
                   + killBonus + wallPenalty + deathPenalty
                   + reversePenalty + winBonus + losePenalty

            done = agent.isDead || stepCount >= maxSteps
        }

        let obs = await MainActor.run { target.rlObservation() }
        return ICWireResp(obs: obs, reward: reward, done: done)
    }

    private func handle(_ line: ICLineConn) {
        Task { [weak self] in
            guard let self else { return }

            let initResp = await self.resetEpisode()
            line.sendJSON(initResp)                // no 'await'

            line.recvLines { [weak self] data in   // no 'await'
                guard let self else { return }

                // control: save_policy
                if let ctrl = try? JSONDecoder().decode(ICWireSavePolicy.self, from: data),
                   ctrl.cmd == "save_policy",
                   let b64 = ctrl.data_b64
                {
                    Task {
                        do {
                            guard let raw = Data(base64Encoded: b64) else {
                                throw NSError(domain: "RLPolicy", code: 4,
                                              userInfo: [NSLocalizedDescriptionKey: "Bad Base64 payload"])
                            }
                            let dest = try await PolicyInstaller.installPolicyData(raw, named: ctrl.name ?? "IonCircuitPolicy")
                            line.sendJSON(ICWireAck(ok: true, saved_path: dest.path, error: nil))
                            self.didSave?()
                        } catch {
                            line.sendJSON(ICWireAck(ok: false, saved_path: nil, error: error.localizedDescription))
                        }
                    }
                    return // keep streaming; training continues
                }

                // normal step
                if let step = try? JSONDecoder().decode(ICWireStep.self, from: data) {
                    let a = step.a
                    let throttle = CGFloat(a.indices.contains(0) ? a[0] : 0)
                    let steer    = CGFloat(a.indices.contains(1) ? a[1] : 0)
                    let fire     = (a.indices.contains(2) ? a[2] > 0.5 : false)

                    Task { [weak self] in
                        guard let self else { return }
                        let resp = await self.stepOnce(throttle: throttle, steer: steer, fire: fire)
                        line.sendJSON(resp)
                        if resp.done {
                            let again = await self.resetEpisode()
                            line.sendJSON(again)
                        }
                    }
                }
            }
        }
    }
    
    func setTraining(_ on: Bool) {
        Task {
            do {
                let token = try await AuthManager.shared.userAuthToken() // refreshes if needed
                var req = URLRequest(url: URL(string: "https://api.yourgame.com/train/\(on ? "start" : "stop")")!)
                req.httpMethod = "POST"
                req.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                if on {
                    req.addValue("application/json", forHTTPHeaderField: "Content-Type")
                    req.httpBody = try JSONSerialization.data(withJSONObject: [
                        "role": "enemy"   // whatever your server expects
                    ])
                }
                _ = try await URLSession.shared.data(for: req)
            } catch {
                print("train toggle failed:", error)
            }
        }
    }
    
    func compiledPolicyURLFromDocuments(_ name: String) -> URL? {
        let fm = FileManager.default
        guard let docs = fm.urls(for: .documentDirectory, in: .userDomainMask).first else { return nil }
        let src = docs.appendingPathComponent("\(name).mlmodel")
        guard fm.fileExists(atPath: src.path) else { return nil }
        do {
            // Compiles to a .mlmodelc folder in a temp/cache location
            let compiled = try MLModel.compileModel(at: src)
            return compiled
        } catch {
            print("⚠️ CoreML compile failed:", error)
            return nil
        }
    }
}
