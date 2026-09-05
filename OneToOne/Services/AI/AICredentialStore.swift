import Foundation
import Security

protocol AICredentialStore {
    func read(id: String) throws -> String?
    func write(_ secret: String, id: String) throws
}

struct KeychainAICredentialStore: AICredentialStore {
    private func query(id: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: "com.onetoone.ai-endpoints",
         kSecAttrAccount as String: id]
    }

    func read(id: String) throws -> String? {
        var query = query(id: id)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = item as? Data,
              let secret = String(data: data, encoding: .utf8) else { throw AIEndpointError.credentialStorage }
        return secret
    }

    func write(_ secret: String, id: String) throws {
        let attributes = [kSecValueData as String: Data(secret.utf8)]
        let status = SecItemUpdate(query(id: id) as CFDictionary, attributes as CFDictionary)
        if status == errSecSuccess { return }
        guard status == errSecItemNotFound else { throw AIEndpointError.credentialStorage }
        var insertion = query(id: id)
        insertion[kSecValueData as String] = Data(secret.utf8)
        insertion[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        guard SecItemAdd(insertion as CFDictionary, nil) == errSecSuccess else { throw AIEndpointError.credentialStorage }
    }
}
