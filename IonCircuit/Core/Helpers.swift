//
//  Helpers.swift
//  IonCircuit
//
//  Created by Barak Ben Hur on 12/10/2025.
//

import Foundation
internal import CoreGraphics

// ===== Helpers (file-scope) =====
@inline(__always)
func smoothstep(edge0: CGFloat, edge1: CGFloat, x: CGFloat) -> CGFloat {
    // Clamp to [0,1] then cubic hermite (smooth in/out)
    let t = CGFloat.clamp((x - edge0) / (edge1 - edge0), 0, 1)
    return t * t * (3 - 2 * t)
}

// Optional unlabeled overload (either call style will compile)
@inline(__always)
func smoothstep(_ edge0: CGFloat, _ edge1: CGFloat, _ x: CGFloat) -> CGFloat {
    smoothstep(edge0: edge0, edge1: edge1, x: x)
}

// Tiny sign helper used in the steering code
@inline(__always)
func sign(_ v: CGFloat) -> CGFloat { v >= 0 ? 1 : -1 }

extension CGRect {
    var center: CGPoint { CGPoint(x: midX, y: midY) }
}

// Clamp helpers
extension CGFloat {
    static func clamp(_ v: CGFloat, _ a: CGFloat, _ b: CGFloat) -> CGFloat {
        return Swift.min(Swift.max(v, a), b)
    }
    func clamped(_ a: CGFloat, _ b: CGFloat) -> CGFloat {
        return CGFloat.clamp(self, a, b)
    }
    
    static func lerp(_ a: CGFloat, _ b: CGFloat, _ t: CGFloat) -> CGFloat { a + (b - a) * t }
    
    static func random(in range: ClosedRange<CGFloat>) -> CGFloat {
        let r = CGFloat(Double.random(in: Double(range.lowerBound)...Double(range.upperBound)))
        return r
    }
}

extension CGPoint {
    func distance(to p: CGPoint) -> CGFloat { hypot(x - p.x, y - p.y) }
}

