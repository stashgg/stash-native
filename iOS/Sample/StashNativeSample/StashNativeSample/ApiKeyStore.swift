//
//  ApiKeyStore.swift
//  StashNativeSample
//
//  Keychain-backed storage for saved credentials.
//

import Foundation
import Security

enum ApiKeyStore {
    private static let service = "com.stash.stashnative.sample"
    private static let account = "apiKeys"

    struct Payload: Codable {
        var keys: [ApiKeyEntry]
        var selectedId: String?
    }

    enum StoreError: Error {
        case keychain(OSStatus)
        case invalidData
    }

    /// Only a missing item returns nil; unreadable or malformed data must not be replaced.
    static func load() throws -> Payload? {
        guard let data = try read() else { return nil }
        return try JSONDecoder().decode(Payload.self, from: data)
    }

    static func save(keys: [ApiKeyEntry], selectedId: String?) throws {
        let data = try JSONEncoder().encode(Payload(keys: keys, selectedId: selectedId))
        try write(data)
    }

    private static func baseQuery() -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    private static func read() throws -> Data? {
        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw StoreError.keychain(status) }
        guard let data = result as? Data else { throw StoreError.invalidData }
        return data
    }

    /// Device-local, like the Android sample's backup exclusion: secrets never migrate to another
    /// device through a backup or transfer. Updates also move items saved with the old class.
    private static let accessibility = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly

    private static func write(_ data: Data) throws {
        var status = SecItemUpdate(
            baseQuery() as CFDictionary,
            [kSecValueData as String: data, kSecAttrAccessible as String: accessibility] as CFDictionary)
        if status == errSecItemNotFound {
            var add = baseQuery()
            add[kSecValueData as String] = data
            add[kSecAttrAccessible as String] = accessibility
            status = SecItemAdd(add as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw StoreError.keychain(status) }
    }
}
