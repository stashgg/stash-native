//
//  ApiKeyStore.swift
//  StashNativeSample
//
//  Keychain-backed storage for saved credentials.
//

import UIKit
import Security

enum ApiKeyStore {
    private static let service = "com.stash.stashnative.sample"
    private static let account = "apiKeys"

    struct Payload: Codable {
        var keys: [ApiKeyEntry]
        var selectedId: String?
    }

    static func load() -> Payload {
        guard let data = read(),
              let payload = try? JSONDecoder().decode(Payload.self, from: data) else {
            return Payload(keys: [], selectedId: nil)
        }
        return payload
    }

    static func save(keys: [ApiKeyEntry], selectedId: String?) {
        guard let data = try? JSONEncoder().encode(
            Payload(keys: keys, selectedId: selectedId)) else { return }
        write(data)
    }

    private static func baseQuery() -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    private static func read() -> Data? {
        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        return SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess
            ? result as? Data : nil
    }

    private static func write(_ data: Data) {
        let status = SecItemUpdate(
            baseQuery() as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var add = baseQuery()
            add[kSecValueData as String] = data
            add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            SecItemAdd(add as CFDictionary, nil)
        }
    }
}
