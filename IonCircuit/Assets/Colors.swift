//
//  Colors.swift
//  IonCircuit
//
//  Created by Barak Ben Hur on 20/10/2025.
//

import SwiftUI
import UIKit
import SpriteKit

public struct IonPalette {
    public let h: Double
    public init(hue: Double = 0.48) { self.h = hue }

    public var neon: UIColor     { UIColor(hue: h, saturation: 0.92, brightness: 1.00, alpha: 1) }
    public var accentA: UIColor  { UIColor(hue: max(min(h-0.04,1),0), saturation: 0.90, brightness: 1.00, alpha: 1) }
    public var accentB: UIColor  { UIColor(hue: max(min(h+0.04,1),0), saturation: 0.90, brightness: 1.00, alpha: 1) }
    public var deep: UIColor     { UIColor(hue: h, saturation: 0.95, brightness: 0.40, alpha: 1) }
    public var shadow: UIColor   { UIColor(hue: h, saturation: 0.85, brightness: 0.20, alpha: 1) }
    public var edge: UIColor     { UIColor(hue: h, saturation: 0.60, brightness: 0.24, alpha: 1) }
    public var bg: UIColor       { UIColor(hue: h, saturation: 0.08, brightness: 0.06, alpha: 1) }
    public var bgAlt: UIColor    { UIColor(hue: h, saturation: 0.10, brightness: 0.10, alpha: 1) }
    public var strike: UIColor   { UIColor(hue: h, saturation: 0.50, brightness: 0.60, alpha: 1) }
    public var text: UIColor     { UIColor(white: 0.94, alpha: 1) }
    public var textDim: UIColor  { UIColor(white: 0.72, alpha: 1) }

    // gradients
    public var ionBeam: LinearGradient {
        LinearGradient(colors: [Color(deep), Color(neon), Color(accentB)], startPoint: .leading, endPoint: .trailing)
    }
    public var ionGlowRing: AngularGradient {
        AngularGradient(gradient: Gradient(colors: [Color(accentA), Color(neon), Color(accentB), Color(neon)]),
                        center: .center)
    }
}

public enum Ion {
    public static let palette = IonPalette()

    // direct hex access if you prefer fixed values
    public static let hex = (
        neon:     0x19FF14,
        accentA:  0x55FF19,
        accentB:  0x19FF4C,
        deep:     0x076605,
        shadow:   0x093308,
        edge:     0x193D18,
        bg:       0x0E0F0E,
        bgAlt:    0x171A17,
        strike:   0x4E994C,
        text:     0xF0F0F0,
        textDim:  0xB8B8B8
    )
}
