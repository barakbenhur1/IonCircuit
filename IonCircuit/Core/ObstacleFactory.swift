//
//  ObstacleFactory.swift
//  IonCircuit
//
//  Created by Barak Ben Hur on 12/10/2025.
//

import SpriteKit

enum ObstacleKind: CaseIterable { case barrel, rock, cone, ramp }

struct ObstacleFactory {
    static func make(_ kind: ObstacleKind) -> SKNode {
        switch kind {
        case .barrel:
            let n = SKShapeNode(circleOfRadius: 18)
            n.fillColor = .brown; n.strokeColor = .black; n.lineWidth = 2
            n.physicsBody = SKPhysicsBody(circleOfRadius: 18)
            n.physicsBody?.isDynamic = false
            n.physicsBody?.categoryBitMask = Category.obstacle
            return n

        case .rock:
            let path = CGMutablePath()
            let r: CGFloat = 26
            for i in 0..<6 {
                let a = CGFloat(i)/6 * 2 * .pi
                let mag = r + CGFloat.random(in: -6...6)
                let pt = CGPoint(x: cos(a)*mag, y: sin(a)*mag)
                (i==0) ? path.move(to: pt) : path.addLine(to: pt)
            }
            path.closeSubpath()
            let n = SKShapeNode(path: path)
            n.fillColor = .gray; n.strokeColor = .black; n.lineWidth = 1.5
            n.physicsBody = SKPhysicsBody(polygonFrom: path)
            n.physicsBody?.isDynamic = false
            n.physicsBody?.categoryBitMask = Category.obstacle
            return n

        case .cone:
            let path = CGMutablePath()
            path.move(to: CGPoint(x: -12, y: -16))
            path.addLine(to: CGPoint(x: 12,  y: -16))
            path.addLine(to: CGPoint(x: 0,   y: 20))
            path.closeSubpath()
            let n = SKShapeNode(path: path)
            n.fillColor = .orange; n.strokeColor = .black; n.lineWidth = 2
            n.physicsBody = SKPhysicsBody(polygonFrom: path)
            n.physicsBody?.isDynamic = false
            n.physicsBody?.categoryBitMask = Category.obstacle
            return n

        case .ramp:
            // A short ramp: treat as low-friction pad that nudges forward
            let path = CGMutablePath()
            path.addRoundedRect(in: CGRect(x: -40, y: -16, width: 80, height: 32), cornerWidth: 10, cornerHeight: 10)
            let n = SKShapeNode(path: path)
            n.fillColor = .cyan; n.strokeColor = .black; n.lineWidth = 2
            let pb = SKPhysicsBody(polygonFrom: path)
            pb.isDynamic = false
            pb.friction = 0.0
            pb.categoryBitMask = Category.obstacle
            n.physicsBody = pb
            n.name = "ramp"
            return n
        }
    }
}
