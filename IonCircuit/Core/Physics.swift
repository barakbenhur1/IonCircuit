//
//  Physics.swift
//  IonCircuit
//
//  Created by Barak Ben Hur on 12/10/2025.
//

import SpriteKit

// Bit masks as plain UInt32 constants (easy to use with SpriteKit)
enum Category {
    static let car: UInt32        = 1 << 0
    static let wall: UInt32       = 1 << 1
    static let obstacle: UInt32   = 1 << 2
    static let hole: UInt32       = 1 << 3
    static let checkpoint: UInt32 = 1 << 4
    static let ramp: UInt32       = 1 << 5
    static let bullet: UInt32     = 1 << 6
}

func shortestAngle(from a: CGFloat, to b: CGFloat) -> CGFloat {
    var x = b - a
    while x > .pi { x -= 2 * .pi }
    while x < -.pi { x += 2 * .pi }
    return x
}

func lerpAngle(_ a: CGFloat, _ b: CGFloat, alpha: CGFloat) -> CGFloat {
    var d = b - a
    while d > .pi { d -= 2 * .pi }
    while d < -.pi { d += 2 * .pi }
    return a + d * alpha
}



// Vector utilities
extension CGVector {
    var length: CGFloat { sqrt(dx*dx + dy*dy) }
    func dot(_ o: CGVector) -> CGFloat { dx*o.dx + dy*o.dy }
    func scaled(_ k: CGFloat) -> CGVector { .init(dx: dx*k, dy: dy*k) }
    static func +(l: CGVector, r: CGVector) -> CGVector { .init(dx: l.dx+r.dx, dy: l.dy+r.dy) }
    static func -(l: CGVector, r: CGVector) -> CGVector { .init(dx: l.dx-r.dx, dy: l.dy-r.dy) }
}

// Convenience
extension SKNode {
    var vel: CGVector {
        get { physicsBody?.velocity ?? .zero }
        set { physicsBody?.velocity = newValue }
    }
}

