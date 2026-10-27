import Foundation
import Security

/// Ключ Notion хранится только в Keychain телефона. В коде, логах и файлах его нет.
enum NotionKeychain {
    private static let service = "de.mathiasweiss.creatorstudio.notion"
    private static let account = "integration-token"

    private static var baseQuery: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    static var hasKey: Bool { read() != nil }

    static func read() -> String? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data, let key = String(data: data, encoding: .utf8), !key.isEmpty
        else { return nil }
        return key
    }

    @discardableResult
    static func save(_ key: String) -> Bool {
        let clean = key.trimmed
        guard !clean.isEmpty else { return false }
        delete()
        var query = baseQuery
        query[kSecValueData as String] = Data(clean.utf8)
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        return SecItemAdd(query as CFDictionary, nil) == errSecSuccess
    }

    static func delete() {
        SecItemDelete(baseQuery as CFDictionary)
    }
}
