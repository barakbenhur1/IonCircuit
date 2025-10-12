//
//  DamageableObstacle.swift
//  IonCircuit
//
//  Created by Barak Ben Hur on 13/10/2025.
//

protocol DamageableObstacle {
    var kind: ObstacleKind { get }
    var hitPoints: Int { get set }
    /// returns true when it reached 0
    mutating func applyDamage(_ d: Int) -> Bool
}
