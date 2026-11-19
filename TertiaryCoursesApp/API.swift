import Foundation
import Security

struct APIError: LocalizedError {
    let message: String
    var status: Int = 0
    var errorDescription: String? { message }
}

extension Notification.Name {
    /// Posted when the server rejects the saved token; the app returns to sign-in.
    static let sessionExpired = Notification.Name("sessionExpired")
}

/// JSON client for the site's learner API (`/mobileapi/*`, MMD_MobileApi in ai-mms).
/// Every response is `{"ok": true, ...}` or `{"ok": false, "error": "<message>"}`.
final class API {
    static let shared = API()

    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }()

    var token: String? { Keychain.read() }

    static let userAgent: String = {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        return "TCLMS-iOS/\(version) (\(Site.code); \(Bundle.main.bundleIdentifier ?? ""))"
    }()

    func get<T: Decodable>(_ path: String, query: [String: String] = [:]) async throws -> T {
        try await send(path, method: "GET", query: query, body: nil)
    }

    func post<T: Decodable>(_ path: String, body: [String: Any] = [:]) async throws -> T {
        try await send(path, method: "POST", query: [:], body: body)
    }

    private func send<T: Decodable>(_ path: String, method: String, query: [String: String], body: [String: Any]?) async throws -> T {
        var components = URLComponents(url: Site.baseURL.appendingPathComponent("mobileapi/" + path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty {
            components.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        var request = URLRequest(url: components.url!)
        request.httpMethod = method
        request.timeoutInterval = 30
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        // The sites' .htaccess bot list blocks any User-Agent containing "CFNetwork"
        // (the iOS default), so identify the app explicitly.
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        if let token {
            request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
        }
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }

        #if DEBUG
        // Screenshot / contract checks: MOCK_DIR holds canned replies named after the
        // path ("trainer/class" -> trainer_class.json); anything else goes to the site.
        if let dir = ProcessInfo.processInfo.environment["MOCK_DIR"],
           let canned = try? Data(contentsOf: URL(fileURLWithPath: dir).appendingPathComponent(path.replacingOccurrences(of: "/", with: "_") + ".json")) {
            do { return try decoder.decode(T.self, from: canned) } catch {
                print("MOCK decode failed for \(path): \(error)")
                throw APIError(message: "The server sent an unexpected reply. Please try again.")
            }
        }
        #endif

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw APIError(message: "Can't reach \(Site.siteName). Check your connection and try again.")
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            if status == 401, token != nil, !path.hasPrefix("auth/") {
                await MainActor.run { NotificationCenter.default.post(name: .sessionExpired, object: nil) }
            }
            throw APIError(message: json?["error"] as? String ?? "Something went wrong (\(status)). Please try again.", status: status)
        }
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw APIError(message: "The server sent an unexpected reply. Please try again.", status: status)
        }
    }
}

/// The session token, stored in the Keychain on this device only.
enum Keychain {
    private static var baseQuery: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: Site.keychainService,
         kSecAttrAccount as String: "session"]
    }

    static func save(_ token: String) throws {
        clear()
        var q = baseQuery
        q[kSecValueData as String] = Data(token.utf8)
        q[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        guard SecItemAdd(q as CFDictionary, nil) == errSecSuccess else {
            throw APIError(message: "Unable to save your session securely.")
        }
    }

    static func read() -> String? {
        var q = baseQuery
        q[kSecReturnData as String] = true
        var value: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &value) == errSecSuccess, let data = value as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func clear() {
        SecItemDelete(baseQuery as CFDictionary)
    }
}
