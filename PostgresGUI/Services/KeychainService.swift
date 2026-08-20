//
//  KeychainService.swift
//  PostgresGUI
//
//  Low-level keychain operations for secure password storage.
//  Uses macOS Keychain Services API to store connection passwords securely.
//
//  Design: Static enum provides direct keychain access. Use KeychainServiceImpl
//  (which conforms to KeychainServiceProtocol) for dependency injection and testing.
//

import Foundation
import Security

enum KeychainService {
    private static let serviceName = "com.postgresgui.connections"
    private static let accessGroupEntitlement = "keychain-access-groups"

    // Save password to Keychain
    static func savePassword(_ password: String, for connectionId: UUID) throws {
        try saveItem(password, account: connectionId.uuidString)
    }

    /// Get password from Keychain
    static func getPassword(for connectionId: UUID) throws -> String? {
        try getItem(account: connectionId.uuidString)
    }
    
    /// Delete password from Keychain
    static func deletePassword(for connectionId: UUID) throws {
        try deleteItem(account: connectionId.uuidString)
    }

    // MARK: - SSH Credentials

    static func saveSSHPassword(_ password: String, for connectionId: UUID) throws {
        try saveItem(password, account: "\(connectionId.uuidString).ssh-password")
    }

    static func getSSHPassword(for connectionId: UUID) throws -> String? {
        try getItem(account: "\(connectionId.uuidString).ssh-password")
    }

    static func deleteSSHPassword(for connectionId: UUID) throws {
        try deleteItem(account: "\(connectionId.uuidString).ssh-password")
    }

    static func saveSSHPassphrase(_ passphrase: String, for connectionId: UUID) throws {
        try saveItem(passphrase, account: "\(connectionId.uuidString).ssh-passphrase")
    }

    static func getSSHPassphrase(for connectionId: UUID) throws -> String? {
        try getItem(account: "\(connectionId.uuidString).ssh-passphrase")
    }

    static func deleteSSHPassphrase(for connectionId: UUID) throws {
        try deleteItem(account: "\(connectionId.uuidString).ssh-passphrase")
    }

    static func saveSSHPrivateKey(_ key: String, for connectionId: UUID) throws {
        try saveItem(key, account: "\(connectionId.uuidString).ssh-private-key")
    }

    static func getSSHPrivateKey(for connectionId: UUID) throws -> String? {
        try getItem(account: "\(connectionId.uuidString).ssh-private-key")
    }

    static func deleteSSHPrivateKey(for connectionId: UUID) throws {
        try deleteItem(account: "\(connectionId.uuidString).ssh-private-key")
    }

    // MARK: - Private Helpers

    private static func saveItem(_ value: String, account: String) throws {
        let data = value.data(using: .utf8)!

        // Delete existing item if any
        try? deleteItem(account: account)

        var query = try query(account: account)
        query.merge([
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]) { _, newValue in newValue }

        let status = SecItemAdd(query as CFDictionary, nil)

        guard status == errSecSuccess else {
            throw KeychainError.saveFailed(status)
        }
    }

    private static func getItem(account: String) throws -> String? {
        var query = try query(account: account)
        query.merge([
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]) { _, newValue in newValue }

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        if status == errSecItemNotFound {
            return nil
        }

        guard status == errSecSuccess else {
            throw KeychainError.retrieveFailed(status)
        }

        guard let data = result as? Data,
              let value = String(data: data, encoding: .utf8) else {
            throw KeychainError.invalidData
        }

        return value
    }

    private static func deleteItem(account: String) throws {
        let query = try query(account: account)

        let status = SecItemDelete(query as CFDictionary)

        // Ignore errSecItemNotFound - item doesn't exist, which is fine
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.deleteFailed(status)
        }
    }

    private static func query(account: String) throws -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: account,
            kSecAttrAccessGroup as String: try accessGroup()
        ]
    }

    private static func accessGroup() throws -> String {
        guard let task = SecTaskCreateFromSelf(nil),
              let groups = SecTaskCopyValueForEntitlement(
                  task,
                  accessGroupEntitlement as CFString,
                  nil
              ) as? [String],
              let accessGroup = groups.first else {
            throw KeychainError.accessGroupUnavailable
        }

        return accessGroup
    }
}
