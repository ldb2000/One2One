import Foundation
import Security

// MARK: - Credentials model

struct GeminiOAuthCredentials: Codable {
    var accessToken: String
    var refreshToken: String
    var expiryDate: TimeInterval  // Unix ms
    var projectId: String
    var email: String?

    enum CodingKeys: String, CodingKey {
        case accessToken  = "access_token"
        case refreshToken = "refresh_token"
        case expiryDate   = "expiry_date"
        case projectId    = "project_id"
        case email
    }

    var isExpired: Bool {
        Date().timeIntervalSince1970 * 1000 >= expiryDate - 60_000
    }
}

// MARK: - Keychain Storage (Data Protection Keychain + cache)

final class GeminiTokenStorage {
    private let service = "com.onetoone.gemini-oauth"
    private let account = "oauth-credentials"

    /// In-memory cache to avoid repeated Keychain reads.
    private var cachedCredentials: GeminiOAuthCredentials?
    private var didLoadFromKeychain = false

    func save(_ credentials: GeminiOAuthCredentials) {
        guard let data = try? JSONEncoder().encode(credentials) else { return }

        deleteFromKeychain()

        var query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecValueData: data,
            kSecUseDataProtectionKeychain: true
        ]

        if let accessControl = SecAccessControlCreateWithFlags(
            nil,
            kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            .biometryAny,
            nil
        ) {
            query[kSecAttrAccessControl] = accessControl
        } else {
            query[kSecAttrAccessible] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        }

        let status = SecItemAdd(query as CFDictionary, nil)
        if status == errSecSuccess {
            cachedCredentials = credentials
            didLoadFromKeychain = true
        } else {
            // Fallback without data protection keychain
            let fallbackQuery: [CFString: Any] = [
                kSecClass: kSecClassGenericPassword,
                kSecAttrService: service,
                kSecAttrAccount: account,
                kSecValueData: data,
                kSecAttrAccessible: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            ]
            SecItemDelete(fallbackQuery as CFDictionary)
            if SecItemAdd(fallbackQuery as CFDictionary, nil) == errSecSuccess {
                cachedCredentials = credentials
                didLoadFromKeychain = true
            }
        }
    }

    func load() -> GeminiOAuthCredentials? {
        if didLoadFromKeychain {
            return cachedCredentials
        }
        cachedCredentials = loadFromKeychain()
        didLoadFromKeychain = true
        return cachedCredentials
    }

    private func loadFromKeychain() -> GeminiOAuthCredentials? {
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
        if SecItemCopyMatching(dpQuery as CFDictionary, &item) == errSecSuccess,
           let data = item as? Data,
           let creds = try? JSONDecoder().decode(GeminiOAuthCredentials.self, from: data) {
            return creds
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
        if SecItemCopyMatching(legacyQuery as CFDictionary, &item) == errSecSuccess,
           let data = item as? Data,
           let creds = try? JSONDecoder().decode(GeminiOAuthCredentials.self, from: data) {
            // Migrate to data protection keychain
            save(creds)
            return creds
        }

        return nil
    }

    func delete() {
        cachedCredentials = nil
        didLoadFromKeychain = true
        deleteFromKeychain()
    }

    private func deleteFromKeychain() {
        for useDP in [true, false] {
            var query: [CFString: Any] = [
                kSecClass: kSecClassGenericPassword,
                kSecAttrService: service,
                kSecAttrAccount: account
            ]
            if useDP { query[kSecUseDataProtectionKeychain] = true }
            SecItemDelete(query as CFDictionary)
        }
    }

    /// Import from ~/.gemini/oauth_creds.json (if Gemini CLI is installed)
    func importFromGeminiCLI() -> GeminiOAuthCredentials? {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let credsPath = home.appendingPathComponent(".gemini/oauth_creds.json")
        guard let data = try? Data(contentsOf: credsPath) else { return nil }

        struct CLIFormat: Decodable {
            let access_token: String
            let refresh_token: String
            let expiry_date: TimeInterval
        }
        guard let cli = try? JSONDecoder().decode(CLIFormat.self, from: data) else { return nil }
        return GeminiOAuthCredentials(
            accessToken: cli.access_token,
            refreshToken: cli.refresh_token,
            expiryDate: cli.expiry_date,
            projectId: "",
            email: nil
        )
    }

    func reload() -> GeminiOAuthCredentials? {
        didLoadFromKeychain = false
        return load()
    }
}

// MARK: - Gemini OAuth Client

final class GeminiOAuthClient {
    static let shared = GeminiOAuthClient()

    let storage = GeminiTokenStorage()

    private var clientId: String = ""
    private var clientSecret: String = ""

    private let session: URLSession

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 120
        self.session = URLSession(configuration: config)
        extractGeminiCLICredentials()
    }

    private func extractGeminiCLICredentials() {
        let paths = [
            "/usr/local/lib/node_modules/@google/gemini-cli-core/dist/src/code_assist/oauth2.js",
            "/opt/homebrew/lib/node_modules/@google/gemini-cli-core/dist/src/code_assist/oauth2.js",
            FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".npm-global/lib/node_modules/@google/gemini-cli-core/dist/src/code_assist/oauth2.js").path
        ]

        for path in paths {
            guard let content = try? String(contentsOfFile: path, encoding: .utf8) else { continue }

            if let range = content.range(of: #"[0-9]+-[a-z0-9]*\.apps\.googleusercontent\.com"#, options: .regularExpression) {
                clientId = String(content[range])
            }
            if let range = content.range(of: #"GOCSPX-[A-Za-z0-9_-]+"#, options: .regularExpression) {
                clientSecret = String(content[range])
            }
            if !clientId.isEmpty && !clientSecret.isEmpty { break }
        }
    }

    func setClientCredentials(id: String, secret: String) {
        clientId = id
        clientSecret = secret
    }

    var hasCredentials: Bool {
        storage.load() != nil
    }

    var hasClientCredentials: Bool {
        !clientId.isEmpty && !clientSecret.isEmpty
    }

    func sendMessage(prompt: String, model: String, maxTokens: Int = 4096) async throws -> String {
        let credentials = try await resolveValidCredentials()

        let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(credentials.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 120

        let body: [String: Any] = [
            "contents": [["role": "user", "parts": [["text": prompt]]]],
            "generationConfig": ["maxOutputTokens": maxTokens]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            let errBody = String(data: data, encoding: .utf8) ?? ""
            throw IngestionError.apiError(code, errBody)
        }

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let candidates = json?["candidates"] as? [[String: Any]],
              let content = candidates.first?["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]],
              let text = parts.first?["text"] as? String else {
            throw IngestionError.parseError("Cannot extract text from Gemini response")
        }
        return text
    }

    private func resolveValidCredentials() async throws -> GeminiOAuthCredentials {
        guard var credentials = storage.load() else {
            throw IngestionError.noAPIKey
        }

        if credentials.isExpired {
            guard !clientId.isEmpty, !clientSecret.isEmpty else {
                throw IngestionError.parseError("Client ID/Secret manquants. Installez Gemini CLI.")
            }
            credentials = try await refreshAccessToken(credentials)
            storage.save(credentials)
        }

        return credentials
    }

    private func refreshAccessToken(_ credentials: GeminiOAuthCredentials) async throws -> GeminiOAuthCredentials {
        let url = URL(string: "https://oauth2.googleapis.com/token")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded;charset=UTF-8", forHTTPHeaderField: "Content-Type")

        var components = URLComponents()
        components.queryItems = [
            URLQueryItem(name: "client_id", value: clientId),
            URLQueryItem(name: "client_secret", value: clientSecret),
            URLQueryItem(name: "refresh_token", value: credentials.refreshToken),
            URLQueryItem(name: "grant_type", value: "refresh_token")
        ]
        request.httpBody = components.percentEncodedQuery?.data(using: .utf8)

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let msg = String(data: data, encoding: .utf8) ?? "unknown"
            throw IngestionError.apiError((response as? HTTPURLResponse)?.statusCode ?? 0, msg)
        }

        struct RefreshResponse: Decodable {
            let access_token: String
            let expires_in: Int
        }
        let refreshed = try JSONDecoder().decode(RefreshResponse.self, from: data)

        var updated = credentials
        updated.accessToken = refreshed.access_token
        updated.expiryDate = Date().timeIntervalSince1970 * 1000 + Double(refreshed.expires_in) * 1000 - 300_000
        return updated
    }
}
