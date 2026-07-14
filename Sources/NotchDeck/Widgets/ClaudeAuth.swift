import Foundation
import Security

// inputs {}, does {locates local Claude Code OAuth credentials (file, then Keychain with user consent) and tracks the connection state. The token is NEVER persisted or logged by NotchDeck — it is read on demand and lives only in memory for the duration of a request}, returns {namespace}
enum ClaudeAuth {
    private static let connectedKey = "dev.notchdeck.claudeConnected"
    private static let planKey = "dev.notchdeck.claudePlan"
    /// In-memory ONLY cache of the oauth dict — the Keychain is asked once per app launch,
    /// not on every panel expand (each SecItemCopyMatching can raise a consent prompt).
    private static var cachedOAuth: [String: Any]?
    private static let cacheLock = NSLock()

    static var isConnected: Bool {
        UserDefaults.standard.bool(forKey: connectedKey)
    }

    static var plan: String? {
        UserDefaults.standard.string(forKey: planKey)
    }

    // inputs {}, does {user-initiated connect (Settings): verifies credentials exist and remembers the plan name — not the token}, returns {plan name or error text}
    static func connect() -> Result<String, ConnectError> {
        guard let credentials = readCredentials() else {
            let status = lastKeychainStatus
            // errSecItemNotFound (-25300) = genuinely no credentials; anything else = access problem.
            if status != errSecItemNotFound && status != errSecSuccess {
                return .failure(.keychainDenied(status))
            }
            return .failure(.notFound)
        }
        cacheLock.lock()
        cachedOAuth = credentials
        cacheLock.unlock()
        let plan = (credentials["subscriptionType"] as? String ?? "unknown").capitalized
        UserDefaults.standard.set(true, forKey: connectedKey)
        UserDefaults.standard.set(plan, forKey: planKey)
        Log.info("claude: connected, plan=\(plan)")
        return .success(plan)
    }

    static func disconnect() {
        UserDefaults.standard.removeObject(forKey: connectedKey)
        UserDefaults.standard.removeObject(forKey: planKey)
        Log.info("claude: disconnected")
    }

    // inputs {}, does {returns the access token from the in-memory cache, re-reading credentials only when missing or expiring within a minute}, returns {token or nil}
    static func accessToken() -> String? {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        if let cached = cachedOAuth, !isExpiring(cached) {
            return cached["accessToken"] as? String
        }
        cachedOAuth = readCredentials()
        return cachedOAuth?["accessToken"] as? String
    }

    // inputs {}, does {drops the cached token (call on 401 — Claude Code may have refreshed it)}, returns {}
    static func invalidateCache() {
        cacheLock.lock()
        cachedOAuth = nil
        cacheLock.unlock()
    }

    private static func isExpiring(_ oauth: [String: Any]) -> Bool {
        guard let expiresAt = oauth["expiresAt"] as? Double else { return false }
        return expiresAt / 1000 < Date().timeIntervalSince1970 + 60
    }

    enum ConnectError: Error {
        case notFound
        case keychainDenied(OSStatus)

        var message: String {
            switch self {
            case .notFound:
                return "Claude Code credentials not found on this Mac. Install and sign in to Claude Code first."
            case .keychainDenied(let status):
                return "Keychain access was not granted (status \(status)). Click Connect again and choose Allow on the Keychain prompt."
            }
        }
    }

    /// OSStatus of the most recent Keychain lookup (for distinguishing "denied" from "absent").
    private(set) static var lastKeychainStatus: OSStatus = errSecSuccess

    // inputs {}, does {parses claudeAiOauth from ~/.claude/.credentials.json, falling back to the Claude Code Keychain item (the read triggers the standard macOS consent prompt — that IS the connect confirmation)}, returns {oauth dict or nil}
    private static func readCredentials() -> [String: Any]? {
        if let data = try? Data(contentsOf: URL(fileURLWithPath: NSHomeDirectory() + "/.claude/.credentials.json")),
           let oauth = parseOAuth(data) {
            return oauth
        }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "Claude Code-credentials",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        lastKeychainStatus = status
        if status != errSecSuccess {
            Log.info("claude: keychain read status=\(status)")
        }
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return parseOAuth(data)
    }

    private static func parseOAuth(_ data: Data) -> [String: Any]? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return root["claudeAiOauth"] as? [String: Any]
    }
}
