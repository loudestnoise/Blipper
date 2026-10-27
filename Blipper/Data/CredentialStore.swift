//
//  CredentialStore.swift
//  Blipper
//

import Foundation
import Security

nonisolated struct TidepoolCredentials: Sendable, Equatable {
    var email: String
    var password: String
}

/// Keeps the Tidepool login in the Keychain so it survives relaunches without touching disk in plain text.
nonisolated enum CredentialStore {
    private static let service = "com.PickleTron.Blipper.tidepool"
    private static let emailAccount = "email"
    private static let passwordAccount = "password"

    static func load() -> TidepoolCredentials? {
        guard let email = read(account: emailAccount),
              let password = read(account: passwordAccount) else { return nil }
        return TidepoolCredentials(email: email, password: password)
    }

    static func save(_ credentials: TidepoolCredentials) throws {
        try write(credentials.email, account: emailAccount)
        try write(credentials.password, account: passwordAccount)
    }

    static func clear() {
        for account in [emailAccount, passwordAccount] {
            SecItemDelete(baseQuery(account: account) as CFDictionary)
        }
    }

    // MARK: Keychain plumbing

    private static func baseQuery(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    private static func read(account: String) -> String? {
        var query = baseQuery(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func write(_ value: String, account: String) throws {
        let data = Data(value.utf8)
        let query = baseQuery(account: account)
        let update: [String: Any] = [kSecValueData as String: data]
        var status = SecItemUpdate(query as CFDictionary, update as CFDictionary)
        if status == errSecItemNotFound {
            var add = query
            add[kSecValueData as String] = data
            add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            status = SecItemAdd(add as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw KeychainError(status: status) }
    }

    struct KeychainError: LocalizedError {
        let status: OSStatus
        var errorDescription: String? {
            "Couldn't save login to the Keychain (\(status))."
        }
    }
}
