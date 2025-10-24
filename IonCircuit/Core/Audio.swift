//
//  Audio.swift
//  IonCircuit
//
//  Created by Barak Ben Hur on 20/10/2025.
//

import AVFoundation
#if canImport(AVFAudio)
import AVFAudio // brings .AVAudioEngineConfigurationChange on some SDKs
#endif
import SpriteKit

#if !canImport(AVFAudio)
extension Notification.Name {
    static let AVAudioEngineConfigurationChange = Notification.Name("AVAudioEngineConfigurationChange")
}
#endif

final class Audio {
    static let shared = Audio()
    
    // Engine / graph
    private let engine = AVAudioEngine()
    private let mainMixer: AVAudioMixerNode
    
    // Car engine loop
    private let enginePlayer  = AVAudioPlayerNode()
    private let engineSpeed   = AVAudioUnitVarispeed()
    
    // Brake squeal (loop while slipping)
    private let brakePlayer   = AVAudioPlayerNode()
    private let brakeSpeed    = AVAudioUnitVarispeed()
    
    // “Fight” tension layer (auto on/off)
    private let fightPlayer   = AVAudioPlayerNode()
    
    // Optional ambient loop (legacy)
    private let ambientPlayer = AVAudioPlayerNode()
    
    // SFX pool
    private var sfxPool: [AVAudioPlayerNode] = []
    
    // Buffer caches for scheduleBuffer paths
    private var buffers:   [String: AVAudioPCMBuffer] = [:]                 // original
    private var converted: [String: [String: AVAudioPCMBuffer]] = [:]       // name -> "ch@rate" -> converted
    
    // Music deck (streaming via scheduleFile with crossfade)
    private let musicA = AVAudioPlayerNode()
    private let musicB = AVAudioPlayerNode()
    private var musicFrontIsA = true
    private var musicTimer: Timer?
    private var musicCrossfadeSec: Double = 2.0
    private var musicVolume: Float = 0.7
    private var playlist: [URL] = []
    private var playlistIndex = 0
    
    // Engine gating
    private var engineIdleFade: Float = 0
    
    // Brake state
    private var brakeLevel: Float = 0
    
    // Fight state
    private var fightHoldUntil: CFTimeInterval = 0
    private var fightPos: CGPoint = .zero
    
    // Listener (camera) for spatialization
    private var listenerPos: CGPoint = .zero
    private var listenerHalfWidth: CGFloat = 512
    
    private var isStarted = false
    
    private init() {
        mainMixer = engine.mainMixerNode
        
        // Session
        do {
            let s = AVAudioSession.sharedInstance()
            try s.setCategory(.ambient, mode: .default, options: [.mixWithOthers]) // respects mute switch
            try s.setActive(true)
        } catch { print("AudioSession error:", error) }
        
        // Attach
        engine.attach(enginePlayer)
        engine.attach(engineSpeed)
        
        engine.attach(brakePlayer)
        engine.attach(brakeSpeed)
        
        engine.attach(fightPlayer)
        engine.attach(ambientPlayer)
        
        engine.attach(musicA)
        engine.attach(musicB)
        
        // Use mixer format everywhere for buffer-based nodes (pre-convert buffers)
        let fmt = mainMixer.outputFormat(forBus: 0)
        engine.connect(enginePlayer, to: engineSpeed, format: fmt)
        engine.connect(engineSpeed,  to: mainMixer,   format: fmt)
        
        engine.connect(brakePlayer,  to: brakeSpeed,  format: fmt)
        engine.connect(brakeSpeed,   to: mainMixer,   format: fmt)
        
        engine.connect(fightPlayer,  to: mainMixer,   format: fmt)
        engine.connect(ambientPlayer,to: mainMixer,   format: fmt)
        
        // IMPORTANT: connect music players with `nil` format so scheduleFile can use file's format safely
        engine.connect(musicA, to: mainMixer, format: nil)
        engine.connect(musicB, to: mainMixer, format: nil)
        
        // SFX pool
        for _ in 0..<8 {
            let p = AVAudioPlayerNode()
            engine.attach(p)
            engine.connect(p, to: mainMixer, format: fmt)
            sfxPool.append(p)
        }
        
        // Auto-recover on route/graph changes
        NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main
        ) { [weak self] _ in self?.restartIfNeeded() }
    }
    
    // MARK: Session helpers
    func setRespectsSilentSwitch(_ yes: Bool) {
        do {
            let s = AVAudioSession.sharedInstance()
            let cat: AVAudioSession.Category = yes ? .ambient : .playback
            try s.setCategory(cat, mode: .default, options: [.mixWithOthers])
            try s.setActive(true)
        } catch { print("AudioSession toggle error:", error) }
    }
    
    // MARK: Engine control
    private func startIfNeeded() {
        guard !isStarted else { return }
        do { try engine.start(); isStarted = true }
        catch { print("AudioEngine failed:", error) }
    }
    
    private func restartIfNeeded() {
        guard isStarted, engine.isRunning == false else { return }
        do { try engine.start() } catch { print("AudioEngine restart failed:", error) }
    }
    
    // MARK: Loading / conversion
    private func locate(_ name: String) -> (url: URL, ext: String)? {
        for e in ["wav","caf","aiff","mp3","m4a"] {
            if let u = Bundle.main.url(forResource: name, withExtension: e) { return (u, e) }
        }
        return nil
    }
    
    private func loadBufferIfNeeded(_ name: String) -> AVAudioPCMBuffer? {
        if let b = buffers[name] { return b }
        guard let (url, _) = locate(name) else {
            print("⚠️ Missing audio file ‘\(name)’ (tried wav/caf/aiff/mp3/m4a)")
            return nil
        }
        do {
            let file = try AVAudioFile(forReading: url)
            guard let buf = AVAudioPCMBuffer(pcmFormat: file.processingFormat,
                                             frameCapacity: AVAudioFrameCount(file.length)) else { return nil }
            try file.read(into: buf)
            buffers[name] = buf
            return buf
        } catch {
            print("Load \(name) failed:", error)
            return nil
        }
    }
    
    private func buffer(_ name: String, convertedTo format: AVAudioFormat) -> AVAudioPCMBuffer? {
        let key = "\(Int(format.channelCount))ch@\(Int(format.sampleRate))"
        if let cached = converted[name]?[key] { return cached }
        guard let src = loadBufferIfNeeded(name) else { return nil }
        
        if src.format == format {
            var map = converted[name] ?? [:]; map[key] = src; converted[name] = map
            return src
        }
        
        guard let conv = AVAudioConverter(from: src.format, to: format) else {
            print("⚠️ Converter init failed \(name) \(src.format) → \(format)")
            return nil
        }
        
        let ratio = format.sampleRate / src.format.sampleRate
        let outCap = AVAudioFrameCount(Double(src.frameLength) * ratio + 32)
        guard let out = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: outCap) else { return nil }
        
        var error: NSError?
        var consumed = false
        let inputBlock: AVAudioConverterInputBlock = { _, outStatus in
            if consumed { outStatus.pointee = .endOfStream; return nil }
            consumed = true
            outStatus.pointee = .haveData
            return src
        }
        conv.convert(to: out, error: &error, withInputFrom: inputBlock)
        if let e = error { print("⚠️ Convert \(name) failed:", e); return nil }
        
        var map = converted[name] ?? [:]; map[key] = out; converted[name] = map
        return out
    }
    
    func preload() {
        let fmt = mainMixer.outputFormat(forBus: 0)
        _ = buffer("ambient_loop", convertedTo: fmt)
        _ = buffer("engine_loop",  convertedTo: fmt)
        _ = buffer("shoot",        convertedTo: fmt)
        _ = buffer("crash",        convertedTo: fmt)
        _ = buffer("explode",      convertedTo: fmt)
        _ = buffer("break",        convertedTo: fmt)
        _ = buffer("fight_loop",   convertedTo: fmt)
    }
    
    // MARK: Music (playlist + crossfade)
    private func scheduleTrack(_ url: URL, on node: AVAudioPlayerNode, volume: Float) -> Double {
        guard let file = try? AVAudioFile(forReading: url) else { return 0 }
        node.volume = volume
        // scheduleFile requires the node to accept the file's processing format.
        // We connected music nodes with `format: nil`, so this is safe.
        node.scheduleFile(file, at: nil, completionHandler: nil)
        return Double(file.length) / file.processingFormat.sampleRate
    }
    
    private func fade(_ node: AVAudioPlayerNode, to target: Float, over seconds: Double) {
        guard seconds > 0 else { node.volume = target; return }
        let steps = 30
        let dt = seconds / Double(steps)
        var i = 0
        let start = node.volume
        Timer.scheduledTimer(withTimeInterval: dt, repeats: true) { t in
            i += 1
            let k = Float(i) / Float(steps)
            node.volume = start + (target - start) * k
            if i >= steps { t.invalidate() }
        }
    }
    
    private func frontNode() -> AVAudioPlayerNode { musicFrontIsA ? musicA : musicB }
    private func backNode()  -> AVAudioPlayerNode { musicFrontIsA ? musicB : musicA }
    private func advanceIndex() { playlistIndex = (playlistIndex + 1) % max(playlist.count, 1) }
    
    private func startCurrentTrack(crossfade: Bool) {
        guard !playlist.isEmpty else { return }
        startIfNeeded()
        
        let front = frontNode()
        let back  = backNode()
        let url   = playlist[playlistIndex]
        
        if back.isPlaying { back.stop() }
        back.volume = crossfade ? 0 : musicVolume
        let dur = scheduleTrack(url, on: back, volume: back.volume)
        
        back.play()
        if crossfade {
            fade(back,  to: musicVolume, over: musicCrossfadeSec)
            fade(front, to: 0,            over: musicCrossfadeSec)
        }
        
        // swap after fade completes
        DispatchQueue.main.asyncAfter(deadline: .now() + musicCrossfadeSec) {
            if front.isPlaying { front.stop() }
            self.musicFrontIsA.toggle()
        }
        
        // schedule next crossfade slightly before end
        musicTimer?.invalidate()
        let lead = max(0.25, musicCrossfadeSec + 0.15)
        let when = max(0.1, dur - lead)
        musicTimer = Timer.scheduledTimer(withTimeInterval: when, repeats: false) { [weak self] _ in
            guard let self else { return }
            self.advanceIndex()
            self.startCurrentTrack(crossfade: true)
        }
    }
    
    /// Play background music with crossfade. `names` are basenames (no extension).
    func playMusic(names: [String], crossfade seconds: Double = 2.0, volume: Float = 0.05) {
        let urls: [URL] = names.compactMap { name in
            for e in ["mp3","m4a","caf","wav","aiff"] {
                if let u = Bundle.main.url(forResource: name, withExtension: e) { return u }
            }
            return nil
        }
        guard !urls.isEmpty else {
            print("⚠️ playMusic: none of the files found: \(names)")
            return
        }
        musicCrossfadeSec = seconds
        musicVolume = volume
        playlist = urls
        playlistIndex = 0
        startCurrentTrack(crossfade: false)
    }
    
    func stopMusic(fade seconds: Double = 0.5) {
        musicTimer?.invalidate()
        fade(musicA, to: 0, over: seconds)
        fade(musicB, to: 0, over: seconds)
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) {
            if self.musicA.isPlaying { self.musicA.stop() }
            if self.musicB.isPlaying { self.musicB.stop() }
        }
    }
    
    func duckMusic(_ on: Bool, amount: Float = 0.35, over: Double = 0.15) {
        let target = on ? musicVolume * amount : musicVolume
        fade(frontNode(), to: target, over: over)
        fade(backNode(),  to: target, over: over)
    }
    
    // MARK: Ambient (legacy)
    func startAmbient(volume: Float = 0.35) {
        startIfNeeded()
        let fmt = mainMixer.outputFormat(forBus: 0)
        guard let buf = buffer("ambient_loop", convertedTo: fmt) else { return }
        if ambientPlayer.isPlaying { ambientPlayer.stop() }
        ambientPlayer.volume = volume
        ambientPlayer.scheduleBuffer(buf, at: nil, options: .loops, completionHandler: nil)
        ambientPlayer.play()
    }
    
    func stopAmbient(fade: Double = 0.4) {
        guard ambientPlayer.isPlaying else { return }
        if fade <= 0 { ambientPlayer.stop(); return }
        let steps = 20, dt = fade / Double(steps)
        var i = 0; let startVol = ambientPlayer.volume
        Timer.scheduledTimer(withTimeInterval: dt, repeats: true) { [weak self] t in
            guard let self else { t.invalidate(); return }
            i += 1; let k = max(0, 1 - Float(i) / Float(steps))
            self.ambientPlayer.volume = startVol * k
            if i >= steps {
                t.invalidate()
                self.ambientPlayer.stop()
                self.ambientPlayer.volume = startVol
            }
        }
    }
    
    // MARK: Engine (driving)
    // Do NOT auto-start this at scene load; let updateEngine(run:normalized:) control it.
    func startEngine(volume: Float = 0.1) {
        startIfNeeded()
        let fmt = mainMixer.outputFormat(forBus: 0)
        guard let buf = buffer("engine_loop", convertedTo: fmt) else { return }
        if enginePlayer.isPlaying { enginePlayer.stop() }
        engineSpeed.rate    = 1.0
        enginePlayer.volume = volume
        enginePlayer.scheduleBuffer(buf, at: nil, options: .loops, completionHandler: nil)
        enginePlayer.play()
    }
    
    func stopEngine() { if enginePlayer.isPlaying { enginePlayer.stop() } }
    
    /// n ∈ [0,1]; maps to 0.8…1.6× pitch and 0.5…1.0 volume.
    func setEngineSpeed(normalized n: CGFloat) {
        let c = CGFloat.clamp(n, 0, 1)
        engineSpeed.rate    = 0.8 + Float(c) * 0.8
        enginePlayer.volume = 0.5 + Float(c) * 0.5
    }
    
    /// Distance-aware engine loudness + pan.
    func setEngineSpeed(normalized n: CGFloat, at worldPos: CGPoint) {
        let c = CGFloat.clamp(n, 0, 1)
        engineSpeed.rate    = 0.8 + Float(c) * 0.8
        let base            = 0.5 + Float(c) * 0.5
        let (pan, gain)     = panGain(for: worldPos)
        enginePlayer.pan    = pan
        enginePlayer.volume = base * gain
    }
    
    /// Call each frame. If `run` is false, we fade and stop the loop.
    func updateEngine(run: Bool, normalized n: CGFloat) {
        startIfNeeded()
        let fmt = mainMixer.outputFormat(forBus: 0)
        engineSpeed.rate = 0.85 + Float(CGFloat.clamp(n, 0, 1)) * 0.80
        
        if run {
            if !enginePlayer.isPlaying, let buf = buffer("engine_loop", convertedTo: fmt) {
                enginePlayer.scheduleBuffer(buf, at: nil, options: .loops, completionHandler: nil)
                enginePlayer.play()
            }
            // fast ramp-in when engaged
            engineIdleFade = min(1, engineIdleFade + 0.25)
            enginePlayer.volume = max(enginePlayer.volume, 0.2)
        } else {
            if enginePlayer.isPlaying {
                engineIdleFade = max(0, engineIdleFade - 0.10) // ~10 frames fade
                enginePlayer.volume = 0.12 * engineIdleFade
                if engineIdleFade <= 0.01 { enginePlayer.stop() }
            }
        }
    }
    
    // MARK: 2D spatialization
    func updateListener(camera: CGPoint, viewportSize: CGSize) {
        listenerPos = camera
        listenerHalfWidth = max(1, viewportSize.width * 0.5)
    }
    
    private func panGain(for src: CGPoint,
                         near: CGFloat = 140,
                         far:  CGFloat = 1400) -> (pan: Float, gain: Float) {
        let dx = src.x - listenerPos.x
        let pan = Float(CGFloat.clamp(dx / listenerHalfWidth, -1, 1))
        let dy = src.y - listenerPos.y
        let r  = hypot(dx, dy)
        if r <= near { return (pan, 1) }
        if r >= far  { return (pan, 0) }
        let t = CGFloat.clamp((r - near) / max(far - near, 1), 0, 1)
        let s = 1 - (t * t * (3 - 2 * t)) // smoothstep(1 - t)
        return (pan, Float(s))
    }
    
    // MARK: SFX (spatial)
    func playShoot(at worldPos: CGPoint, baseVolume: Float = 0.38) {
        startIfNeeded()
        let fmt = mainMixer.outputFormat(forBus: 0)
        guard let buf = buffer("shoot", convertedTo: fmt) else { return }
        let (pan, gain) = panGain(for: worldPos)
        let p = (sfxPool.first { !$0.isPlaying }) ?? sfxPool.randomElement()!
        p.pan = pan
        p.volume = baseVolume * gain
        p.scheduleBuffer(buf, at: nil, options: [], completionHandler: nil)
        p.play()
    }
    
    func playCrash(at worldPos: CGPoint, baseVolume: Float = 0.5) {
        startIfNeeded()
        let fmt = mainMixer.outputFormat(forBus: 0)
        guard let buf = buffer("crash", convertedTo: fmt) else { return }
        let (pan, gain) = panGain(for: worldPos, near: 160, far: 1600)
        let p = (sfxPool.first { !$0.isPlaying }) ?? sfxPool.randomElement()!
        p.pan = pan
        p.volume = baseVolume * gain * 0.8
        p.scheduleBuffer(buf, at: nil, options: [], completionHandler: nil)
        p.play()
    }
    
    func playExplode(at worldPos: CGPoint, baseVolume: Float = 0.8) {
        startIfNeeded()
        let fmt = mainMixer.outputFormat(forBus: 0)
        guard let buf = buffer("explode", convertedTo: fmt) else { return }
        let (pan, gain) = panGain(for: worldPos, near: 220, far: 1800)
        let p = (sfxPool.first { !$0.isPlaying }) ?? sfxPool.randomElement()!
        p.pan = pan
        p.volume = baseVolume * gain
        p.scheduleBuffer(buf, at: nil, options: [], completionHandler: nil)
        p.play()
    }
    
    /// “Shatter” (object break). Uses asset named `break.*` in bundle.
    func playShatter(at worldPos: CGPoint?, baseVolume: Float = 0.45) {
        startIfNeeded()
        let fmt = mainMixer.outputFormat(forBus: 0)
        guard let buf = buffer("break", convertedTo: fmt) else { return }
        let (pan, gain) = panGain(for: worldPos ?? CGPoint.zero, near: 160, far: 1400)
        let p = (sfxPool.first { !$0.isPlaying }) ?? sfxPool.randomElement()!
        p.pan = pan
        p.volume = baseVolume * gain
        p.scheduleBuffer(buf, at: nil, options: [], completionHandler: nil)
        p.play()
    }
    
    // MARK: Brake loop (car squeal under slip)
    func updateBrake(slip: CGFloat, at worldPos: CGPoint) {
        startIfNeeded()
        let fmt = mainMixer.outputFormat(forBus: 0)
        let s = CGFloat.clamp(slip, 0, 1)
        
        // Start on demand
        if s > 0.02, !brakePlayer.isPlaying, let buf = buffer("brake", convertedTo: fmt) {
            brakeSpeed.rate = 0.9 + Float(s) * 0.3   // subtle pitch with slip
            brakePlayer.volume = 0
            brakePlayer.scheduleBuffer(buf, at: nil, options: .loops, completionHandler: nil)
            brakePlayer.play()
        }
        
        // Spatialize + smooth volume
        let (pan, gain) = panGain(for: worldPos, near: 100, far: 1200)
        brakePlayer.pan = pan
        let target = Float(s) * gain
        brakeLevel += (target - brakeLevel) * 0.25
        brakeLevel = max(0, min(1, brakeLevel))
        brakePlayer.volume = brakeLevel
        
        // Stop when inaudible
        if brakePlayer.isPlaying && brakePlayer.volume < 0.01 && target < 0.01 {
            brakePlayer.stop()
            brakeLevel = 0
        }
    }
    
    // MARK: Fight loop
    func noteCombatEvent(at pos: CGPoint, intensity: CGFloat = 0.7,
                         now: CFTimeInterval = CACurrentMediaTime()) {
        let add = 0.8 + 0.4 * Double(CGFloat.clamp(intensity, 0, 1))
        fightHoldUntil = max(fightHoldUntil, now + add)
        fightPos = pos
    }

    func updateFight(now: CFTimeInterval = CACurrentMediaTime()) {
        startIfNeeded()
        let active = now < fightHoldUntil
        if active {
            if !fightPlayer.isPlaying {
                let fmt = mainMixer.outputFormat(forBus: 0)
                if let buf = buffer("fight_loop", convertedTo: fmt) {
                    fightPlayer.volume = 0
                    fightPlayer.scheduleBuffer(buf, at: nil, options: .loops, completionHandler: nil)
                    fightPlayer.play()
                }
            }
            let (pan, gain) = panGain(for: fightPos, near: 220, far: 1800)
            fightPlayer.pan = pan
            let target: Float = max(0.2, 0.6 * gain)
            fightPlayer.volume += (target - fightPlayer.volume) * 0.15
        } else if fightPlayer.isPlaying {
            fightPlayer.volume = max(0, fightPlayer.volume - 0.08)
            if fightPlayer.volume <= 0.01 { fightPlayer.stop() }
        }
    }
    
    // MARK: Diagnostics
    func diagnose() {
        let s = AVAudioSession.sharedInstance()
        print("🔊 session:", s.category.rawValue, "@", s.sampleRate, "Hz, io:", s.outputNumberOfChannels, "ch")
        let mixFmt = mainMixer.outputFormat(forBus: 0)
        print("🔊 mixer:", mixFmt.channelCount, "ch @", mixFmt.sampleRate, "Hz; mixerVol:", mainMixer.outputVolume)
        print("🔊 engine running:", engine.isRunning)
    }
    
    /// Plays a 440Hz/0.5s tone to verify audio path even without assets.
    func playTestTone() {
        startIfNeeded()
        let fmt = mainMixer.outputFormat(forBus: 0)
        let sr  = fmt.sampleRate
        let n   = Int(sr * 0.5)
        guard let buf = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: AVAudioFrameCount(n)) else { return }
        buf.frameLength = AVAudioFrameCount(n)
        
        let freq = 440.0
        let step = 2.0 * .pi * freq / sr
        
        if let ch0 = buf.floatChannelData?[0] {
            for i in 0..<n { ch0[i] = sinf(Float(Double(i) * step)) * 0.3 }
        }
        if fmt.channelCount > 1, let ch1 = buf.floatChannelData?[1] {
            memcpy(ch1, buf.floatChannelData![0], n * MemoryLayout<Float>.size)
        }
        
        let node = AVAudioPlayerNode()
        engine.attach(node)
        engine.connect(node, to: mainMixer, format: fmt)
        node.scheduleBuffer(buf, at: nil, options: []) { [weak self, weak node] in
            if let n = node { self?.engine.detach(n) }
        }
        node.play()
    }
}

extension Audio {
    // simple state so we don't re-trigger every frame
    private static var _fightArmed = false
    private static var _lastAmbientPulse: CFTimeInterval = 0

    /// Only “poke” the fight layer when the scene is really hot,
    /// and not more than ~once per second.
    func updateFight(intensity: CGFloat, at pos: CGPoint, now: CFTimeInterval) {
        let onThresh: CGFloat  = 0.72   // engage
        let offThresh: CGFloat = 0.45   // disarm when it cools down
        let cooldown: CFTimeInterval = 1.2

        if intensity >= onThresh,
           !Self._fightArmed,
           now - Self._lastAmbientPulse > cooldown {
            noteCombatEvent(at: pos, intensity: intensity, now: CACurrentMediaTime())
            Self._fightArmed = true
            Self._lastAmbientPulse = now
        } else if intensity <= offThresh {
            Self._fightArmed = false
        }
        updateFight(now: now)
    }
}
