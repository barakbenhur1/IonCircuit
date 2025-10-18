//
//  Step.swift
//  IonCircuit
//
//  Created by Barak Ben Hur on 17/10/2025.
//

import Foundation

/// Trainer → Game: actions
public struct RLStep: Sendable {
    public let a: [Double]
    public init(a: [Double]) { self.a = a }
}

// Make decoding explicitly non-isolated (works even in Swift 6)
extension RLStep: Decodable {
    enum CodingKeys: String, CodingKey { case a }
    public nonisolated init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.a = try c.decode([Double].self, forKey: .a)
    }
}

/// Game → Trainer: observation + reward
public struct RLResp: Sendable {
    public let o: [Double]
    public let r: Double
    public let d: Bool
    public init(o: [Double], r: Double, d: Bool) {
        self.o = o; self.r = r; self.d = d
    }
}

extension RLResp: Encodable {
    enum CodingKeys: String, CodingKey { case o, r, d }
    public nonisolated func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(o,    forKey: .o)
        try c.encode(r, forKey: .r)
        try c.encode(d,   forKey: .d)
    }
}
