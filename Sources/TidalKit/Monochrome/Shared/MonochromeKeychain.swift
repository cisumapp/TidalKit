import Foundation
import Security

public enum MonochromeKeychain {
    public static func save(_ value: String, key: String, service: String) {
        guard let data = value.data(using: .utf8) else { return }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
        ]

        SecItemDelete(query as CFDictionary)
        SecItemAdd(query as CFDictionary, nil)
    }

    public static func load(key: String, service: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var value: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &value)
        guard status == errSecSuccess,
              let data = value as? Data,
              let decoded = String(data: data, encoding: .utf8) else {
            return nil
        }

        return decoded
    }

    public static func delete(key: String, service: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]

        SecItemDelete(query as CFDictionary)
    }
}
