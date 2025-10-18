//
//  RLPolicy.swift
//  IonCircuit
//
//  Created by Barak Ben Hur on 18/10/2025.
//

import CoreML

// MARK: - Core ML policy wrapper
final class RLPolicy {
    private let model: MLModel
    private let obsKey: String
    private let actKeys: [String]

    /// Accepts either compiled .mlmodelc URL or uncompiled .mlmodel (Xcode compiles at build).
    init(modelURL: URL, obsKey: String = "obs", actKeys: [String] = ["actions","mu","action"]) throws {
        // If a .mlmodel was passed, compile it first
        let url: URL
        if modelURL.pathExtension == "mlmodel" {
            url = try MLModel.compileModel(at: modelURL)
        } else {
            url = modelURL
        }
        self.model = try MLModel(contentsOf: url)
        self.obsKey = obsKey
        self.actKeys = actKeys
    }

    struct Action { let throttle: CGFloat; let steer: CGFloat; let fire: Bool }

    func act(obs: [Double]) throws -> Action {
        let arr = try MLMultiArray(shape: [NSNumber(value: obs.count)], dataType: .double)
        for (i, v) in obs.enumerated() { arr[i] = NSNumber(value: v) }
        let provider = try MLDictionaryFeatureProvider(dictionary: [obsKey: MLFeatureValue(multiArray: arr)])
        let out = try model.prediction(from: provider)

        // Find an output multiarray (support several common names)
        var vec: [Double] = []
        if let named = actKeys.compactMap({ out.featureValue(for: $0)?.multiArrayValue }).first {
            vec = named.toDoubles()
        } else if let anyKey = out.featureNames
            .compactMap({ out.featureValue(for: $0)?.multiArrayValue }).first {
            vec = anyKey.toDoubles()
        }

        // Defensive defaults
        let t = (vec.indices.contains(0) ? vec[0] : 0)
        let s = (vec.indices.contains(1) ? vec[1] : 0)
        let f = (vec.indices.contains(2) ? vec[2] : 0)

        // Many PPO heads are already tanh-bounded; if not, clamp/tanh now.
        func clamp01(_ x: Double) -> Double { max(-1, min(1, x)) }
        let throttle = CGFloat(clamp01(t))
        let steer    = CGFloat(clamp01(s))
        let fire     = f > 0.5

        return Action(throttle: throttle, steer: steer, fire: fire)
    }
}

// QoL: read doubles from an MLMultiArray
private extension MLMultiArray {
    func toDoubles() -> [Double] {
        if dataType == .double {
            return (0..<count).map { self[$0].doubleValue }
        } else if dataType == .float32 || dataType == .float {
            return (0..<count).map { Double(truncating: self[$0]) }
        } else {
            return (0..<count).map { self[$0].doubleValue }
        }
    }
}
