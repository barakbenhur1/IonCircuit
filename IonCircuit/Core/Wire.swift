//
//  Wire.swift
//  IonCircuit
//
//  Created by Barak Ben Hur on 22/10/2025.
//

import Foundation
import Network

// Pure data types (never touch SpriteKit/UI)
struct ICWireStep: Codable, Sendable { let a: [Double] }
struct ICWireResp: Codable, Sendable { let obs: [Double]; let reward: Double; let done: Bool }
struct ICWireSavePolicy: Codable, Sendable {
    let cmd: String            // "save_policy"
    let name: String?          // optional policy name
    let data_b64: String?      // base64 payload (.mlmodel or compiled)
}
struct ICWireAck: Codable, Sendable {
    let ok: Bool
    let saved_path: String?
    let error: String?
}

// Simple TCP line codec – NOT an actor, not @MainActor
final class ICLineConn {
    private let conn: NWConnection
    private let q = DispatchQueue(label: "rl.line")

    init(_ c: NWConnection) { conn = c }
    func start() { conn.start(queue: q) }

    func sendJSON<T: Encodable>(_ x: T) {
        do {
            let data = try JSONEncoder().encode(x)
            conn.send(content: data + Data([0x0A]), completion: .contentProcessed { _ in })
        } catch { print("RL send error:", error) }
    }

    func recvLines(_ onLine: @escaping (Data) -> Void) {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [weak self] data, _, _, _ in
            guard let self, let data else { return }
            for chunk in data.split(separator: 0x0A, omittingEmptySubsequences: true) {
                onLine(Data(chunk))
            }
            self.recvLines(onLine) // keep streaming
        }
    }
}
