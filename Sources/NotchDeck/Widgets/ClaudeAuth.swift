import Foundation
import Security

// inputs {}, does {locates local Claude Code OAuth credentials (file, then Keychain with user consent) and tracks the connection state. The token is NEVER persisted or logged by NotchDeck — it is read on demand and lives only in memory for the duration of a request}, returns {namespace}
enum ClaudeAuth {
    private static let connectedKey = "dev.notchdeck.claudeConnected"
    private static let planKey = "dev.notchdeck.claudePlan"

    static var isConnected: Bool {
        UserDefaults.standard.bool(forKey: connectedKey)
    }

    static var plan: String? {
        UserDefaults.standard.string(forKey: planKey)
    }

    // inputs {}, does {user-initiated connect (Settings): verifies credentials exist and remembers the plan name — not the token}, returns {plan name or error text}
    static func connect() -> Result<String, ConnectError> {
        guard let credentials = readCredentials() else {
            return .failure(.notFound)
        }
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

    // inputs {}, does {reads the access token on demand for one request}, returns {token or nil}
    static func accessToken() -> String? {
        readCredentials()?["accessToken"] as? String
    }

    enum ConnectError: Error {
        case notFound

        var message: String {
            "Claude Code credentials not found on this Mac. Install and sign in to Claude Code first."
        }
    }

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
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return parseOAuth(data)
    }

    private static func parseOAuth(_ data: Data) -> [String: Any]? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return root["claudeAiOauth"] as? [String: Any]
    }
}
