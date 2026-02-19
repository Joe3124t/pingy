import Foundation
import Security

enum KeychainStoreError: Error {
    case unexpectedStatus(OSStatus)
    case dataEncodingFailed
    case dataDecodingFailed
}

final class KeychainStore {
    static let shared = KeychainStore()
    private init() {}

    func set(_ value: String, for key: String) throws {
        guard let data = value.data(using: .utf8) else {
            throw KeychainStoreError.dataEncodingFailed
        }

        try setData(data, for: key)
    }

    func string(for key: String) throws -> String? {
        guard let data = try data(for: key) else {
            return nil
        }

        guard let value = String(data: data, encoding: .utf8) else {
            throw KeychainStoreError.dataDecodingFailed
        }

        return value
    }

    func setData(_ data: Data, for key: String) throws {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrAccount: key,
            kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecValueData: data
        ]

        SecItemDelete(query as CFDictionary)
        let status = SecItemAdd(query as CFDictionary, nil)

        guard status == errSecSuccess else {
            throw KeychainStoreError.unexpectedStatus(status)
        }
    }

    func data(for key: String) throws -> Data? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrAccount: key,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne
        ]

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        if status == errSecItemNotFound {
            return nil
        }

        guard status == errSecSuccess else {
            throw KeychainStoreError.unexpectedStatus(status)
        }

        return result as? Data
    }

    func delete(_ key: String) throws {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrAccount: key
        ]

        let status = SecItemDelete(query as CFDictionary)

        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainStoreError.unexpectedStatus(status)
        }
    }

    func deleteAll(matchingAccountPrefix prefix: String) throws {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecReturnAttributes: true,
            kSecMatchLimit: kSecMatchLimitAll
        ]

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        if status == errSecItemNotFound {
            return
        }

        guard status == errSecSuccess else {
            throw KeychainStoreError.unexpectedStatus(status)
        }

        let entries = result as? [[CFString: Any]] ?? []

        for entry in entries {
            guard let account = entry[kSecAttrAccount] as? String else {
                continue
            }
            guard account.hasPrefix(prefix) else {
                continue
            }
            try delete(account)
        }
    }
}
