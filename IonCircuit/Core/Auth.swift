//
//  Keychain.swift
//  IonCircuit
//
//  Created by Barak Ben Hur on 22/10/2025.
//

import Security
import Foundation
import DeviceCheck

enum Keychain {
    static func set(_ value: String, for key: String) {
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.app.ioncircuit",
            kSecAttrAccount as String: key
        ]
        SecItemDelete(query as CFDictionary)
        var add = query
        add[kSecValueData as String] = data
        SecItemAdd(add as CFDictionary, nil)
    }

    static func get(_ key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.app.ioncircuit",
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var out: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &out) == errSecSuccess,
              let data = out as? Data,
              let str = String(data: data, encoding: .utf8) else { return nil }
        return str
    }

    static func delete(_ key: String) {
        let q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.app.ioncircuit",
            kSecAttrAccount as String: key
        ]
        SecItemDelete(q as CFDictionary)
    }
}

struct TokenPair: Decodable {
    let access_token: String
    let refresh_token: String?
    let expires_in: Int?
}

final class AuthManager {
    static let shared = AuthManager()
    private init() {}

    private let base = URL(string: "https://api.yourgame.com")!
    private let accessKey  = "access_token"
    private let refreshKey = "refresh_token"
    private var accessExpiry: Date?

    // Email/password example
    func login(email: String, password: String) async throws {
        var req = URLRequest(url: base.appendingPathComponent("/auth/login"))
        req.httpMethod = "POST"
        req.addValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: ["email": email, "password": password])

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }

        let tok = try JSONDecoder().decode(TokenPair.self, from: data)
        Keychain.set(tok.access_token, for: accessKey)
        if let r = tok.refresh_token { Keychain.set(r, for: refreshKey) }
        if let s = tok.expires_in { accessExpiry = Date().addingTimeInterval(TimeInterval(s - 30)) }
    }

    // Sign in with Apple → exchange on your backend
    func loginWithApple(identityToken: String) async throws {
        var req = URLRequest(url: base.appendingPathComponent("/auth/apple"))
        req.httpMethod = "POST"
        req.addValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: ["identity_token": identityToken])

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }

        let tok = try JSONDecoder().decode(TokenPair.self, from: data)
        Keychain.set(tok.access_token, for: accessKey)
        if let r = tok.refresh_token { Keychain.set(r, for: refreshKey) }
        if let s = tok.expires_in { accessExpiry = Date().addingTimeInterval(TimeInterval(s - 30)) }
    }

    // Get a valid access token (refresh if needed)
    func userAuthToken() async throws -> String {
        // if not expiring, return cached
        if let exp = accessExpiry, Date() < exp, let t = Keychain.get(accessKey) { return t }

        // try refresh
        if let refresh = Keychain.get(refreshKey) {
            var req = URLRequest(url: base.appendingPathComponent("/auth/refresh"))
            req.httpMethod = "POST"
            req.addValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONSerialization.data(withJSONObject: ["refresh_token": refresh])

            let (data, resp) = try await URLSession.shared.data(for: req)
            if (resp as? HTTPURLResponse)?.statusCode == 200 {
                let tok = try JSONDecoder().decode(TokenPair.self, from: data)
                Keychain.set(tok.access_token, for: accessKey)
                if let s = tok.expires_in { accessExpiry = Date().addingTimeInterval(TimeInterval(s - 30)) }
                return tok.access_token
            }
        }

        // otherwise force re-login
        throw URLError(.userAuthenticationRequired)
    }
    
    func bootstrap(accessToken: String, refreshToken: String? = nil, expiresIn seconds: Int? = nil) {
        Keychain.set(accessToken, for: "access_token")
        if let r = refreshToken { Keychain.set(r, for: "refresh_token") }
        if let s = seconds { accessExpiry = Date().addingTimeInterval(TimeInterval(s - 30)) }
    }
}

enum DeviceAttestation {
    static func tokenBase64() async throws -> String {
        guard DCDevice.current.isSupported else {
            throw NSError(domain: "attest", code: 1, userInfo: [NSLocalizedDescriptionKey: "DeviceCheck not supported"])
        }
        return try await withCheckedThrowingContinuation { cont in
            DCDevice.current.generateToken { data, err in
                if let err = err { cont.resume(throwing: err); return }
                guard let data = data else {
                    cont.resume(throwing: NSError(domain: "attest", code: 2, userInfo: [NSLocalizedDescriptionKey: "No token"]))
                    return
                }
                cont.resume(returning: data.base64EncodedString())
            }
        }
    }
}

enum NetworkUtils {
    static func currentWiFiIP() -> String? {
        var addr: String?
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        if getifaddrs(&ifaddr) == 0 {
            var p = ifaddr
            while p != nil {
                let i = p!.pointee
                if i.ifa_addr.pointee.sa_family == UInt8(AF_INET),
                   let name = String(validatingUTF8: i.ifa_name), name == "en0" {
                    var a = i.ifa_addr.pointee
                    var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    getnameinfo(&a, socklen_t(i.ifa_addr.pointee.sa_len),
                                &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST)
                    addr = String(cString: host)
                    break
                }
                p = i.ifa_next
            }
            freeifaddrs(ifaddr)
        }
        return addr
    }
}

enum TrainingService {
    static let baseURL = URL(string: "https://api.yourgame.com")!  // your endpoint

    static func start(host: String, port: Int = 5556, name: String = "enemy") async throws {
        let token = try await DeviceAttestation.tokenBase64()
        var req = URLRequest(url: baseURL.appendingPathComponent("/train/start"))
        req.httpMethod = "POST"
        req.addValue("application/json", forHTTPHeaderField: "Content-Type")
        req.addValue(token, forHTTPHeaderField: "X-DeviceCheck-Token")
        let body: [String: Any] = ["host": host, "port": port, "name": name]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        _ = try await URLSession.shared.data(for: req)
    }

    static func stop(name: String = "enemy") async throws {
        let token = try await DeviceAttestation.tokenBase64()
        var req = URLRequest(url: baseURL.appendingPathComponent("/train/stop"))
        req.httpMethod = "POST"
        req.addValue("application/json", forHTTPHeaderField: "Content-Type")
        req.addValue(token, forHTTPHeaderField: "X-DeviceCheck-Token")
        req.httpBody = try JSONSerialization.data(withJSONObject: ["name": name])
        _ = try await URLSession.shared.data(for: req)
    }
}
