import Foundation
import Security
import LocalAuthentication

// MARK: - Token Storage (Data Protection Keychain + Touch ID)

final class AnthropicTokenStorage {
    private let service = "com.onetoone.anthropic-oauth"
    private let account = "setup-token"

    /// In-memory cache to avoid repeated Keychain reads.
    private var cachedToken: String?
    private var didLoadFromKeychain = false

    func save(_ token: String) {
        // Delete existing item first
        deleteFromKeychain()

        let data = Data(token.utf8)
        var query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecValueData: data,
            kSecUseDataProtectionKeychain: true
        ]

        // Try to add with Touch ID access control
        if let accessControl = SecAccessControlCreateWithFlags(
            nil,
            kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            .biometryAny,
            nil
        ) {
            query[kSecAttrAccessControl] = accessControl
        } else {
            // Fallback without biometry
            query[kSecAttrAccessible] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        }

        let status = SecItemAdd(query as CFDictionary, nil)
        if status == errSecSuccess {
            cachedToken = token
            didLoadFromKeychain = true
            print("[OAuthStorage] Token saved to Keychain (data protection)")
        } else {
            // Fallback: save without biometry and without data protection keychain
            print("[OAuthStorage] Data protection save failed (\(status)), trying fallback")
            saveFallback(data)
        }
    }

    private func saveFallback(_ data: Data) {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecValueData: data,
            kSecAttrAccessible: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        SecItemDelete(query as CFDictionary)
        let status = SecItemAdd(query as CFDictionary, nil)
        if status == errSecSuccess {
            cachedToken = String(data: data, encoding: .utf8)
            didLoadFromKeychain = true
        } else {
            print("[OAuthStorage] Fallback keychain save error: \(status)")
        }
    }

    /// Load token. Uses in-memory cache after first successful load.
    func load() -> String? {
        if didLoadFromKeychain {
            return cachedToken
        }
        cachedToken = loadFromKeychain()
        didLoadFromKeychain = true
        return cachedToken
    }

    private func loadFromKeychain() -> String? {
        // Try data protection keychain first
        let dpQuery: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne,
            kSecUseDataProtectionKeychain: true
        ]
        var item: CFTypeRef?
        var status = SecItemCopyMatching(dpQuery as CFDictionary, &item)
        if status == errSecSuccess, let data = item as? Data {
            return String(data: data, encoding: .utf8)
        }

        // Fallback to legacy keychain
        let legacyQuery: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne
        ]
        item = nil
        status = SecItemCopyMatching(legacyQuery as CFDictionary, &item)
        if status == errSecSuccess, let data = item as? Data {
            let token = String(data: data, encoding: .utf8)
            // Migrate to data protection keychain
            if let token {
                print("[OAuthStorage] Migrating token to data protection keychain")
                save(token)
            }
            return token
        }

        return nil
    }

    func delete() {
        cachedToken = nil
        didLoadFromKeychain = true
        deleteFromKeychain()
    }

    private func deleteFromKeychain() {
        // Delete from both keychains
        let dpQuery: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecUseDataProtectionKeychain: true
        ]
        SecItemDelete(dpQuery as CFDictionary)

        let legacyQuery: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account
        ]
        SecItemDelete(legacyQuery as CFDictionary)
    }

    func isValidFormat(_ token: String) -> Bool {
        token.hasPrefix("sk-ant-")
    }

    /// Force reload from Keychain (e.g. after user explicitly requests it).
    func reload() -> String? {
        didLoadFromKeychain = false
        return load()
    }
}

// MARK: - Anthropic OAuth Client

final class AnthropicOAuthClient {
    static let shared = AnthropicOAuthClient()

    let storage = AnthropicTokenStorage()

    // Headers beta obligatoires pour token sk-ant-oat01
    private let oauthBetas = [
        "claude-code-20250219",
        "oauth-2025-04-20",
        "interleaved-thinking-2025-05-14",
        "code-editor-2025-03-15",
        "extended-context-2025-04-15"
    ].joined(separator: ",")

    private let session: URLSession

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 120
        self.session = URLSession(configuration: config)
    }

    /// Sends a message using the OAuth token and returns the text response.
    func sendMessage(prompt: String, model: String, maxTokens: Int = 4096, systemPrompt: String? = nil) async throws -> String {
        guard let token = storage.load(), storage.isValidFormat(token) else {
            throw OAuthError.noToken
        }

        let url = URL(string: "https://api.anthropic.com/v1/messages")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"

        // Try x-api-key first; fall back to Bearer if needed
        request.setValue(token, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue(oauthBetas, forHTTPHeaderField: "anthropic-beta")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 120

        var body: [String: Any] = [
            "model": model,
            "max_tokens": maxTokens,
            "messages": [["role": "user", "content": prompt]]
        ]
        if let sys = systemPrompt {
            body["system"] = sys
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw OAuthError.networkError("Invalid response")
        }

        guard httpResponse.statusCode == 200 else {
            let errorBody = String(data: data, encoding: .utf8) ?? "unknown"
            if httpResponse.statusCode == 401 {
                // Show actual API error for better diagnostics
                if errorBody.contains("expired") || errorBody.contains("invalid_token") {
                    throw OAuthError.tokenExpired
                }
                throw OAuthError.apiError(401, errorBody)
            }
            throw OAuthError.apiError(httpResponse.statusCode, errorBody)
        }

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let contentArray = json?["content"] as? [[String: Any]],
              let textBlock = contentArray.first(where: { $0["type"] as? String == "text" }),
              let content = textBlock["text"] as? String else {
            throw OAuthError.parseError("Cannot extract text from response")
        }

        return content
    }

    enum OAuthError: LocalizedError {
        case noToken
        case tokenExpired
        case networkError(String)
        case apiError(Int, String)
        case parseError(String)

        var errorDescription: String? {
            switch self {
            case .noToken:
                return "Aucun token OAuth configure. Lancez `claude setup-token` dans un terminal et collez le token dans les parametres."
            case .tokenExpired:
                return "Token OAuth expire. Relancez `claude setup-token` pour en generer un nouveau."
            case .networkError(let msg):
                return "Erreur reseau: \(msg)"
            case .apiError(let code, let body):
                return "Erreur API (\(code)): \(String(body.prefix(200)))"
            case .parseError(let msg):
                return "Erreur de parsing: \(msg)"
            }
        }
    }
}
