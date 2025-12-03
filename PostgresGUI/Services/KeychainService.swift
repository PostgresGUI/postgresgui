//
//  KeychainService.swift
//  PostgresGUI
//
//  Created by ghazi on 11/28/25.
//

import Foundation
import Security

enum KeychainService {
    private static let serviceName = "com.postgresgui.connections"
    
    /// Save password to Keychain
    static func savePassword(_ password: String, for connectionId: UUID) throws {
        let passwordData = password.data(using: .utf8)!
        let account = connectionId.uuidString
        
        // Delete existing password if any
        try? deletePassword(for: connectionId)
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: account,
            kSecValueData as String: passwordData
        ]
        
        let status = SecItemAdd(query as CFDictionary, nil)
        
        guard status == errSecSuccess else {
            throw KeychainError.saveFailed(status)
        }
    }
    
    /// Get password from Keychain
    static func getPassword(for connectionId: UUID) throws -> String? {
        let account = connectionId.uuidString
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        if status == errSecItemNotFound {
            return nil
        }
        
        guard status == errSecSuccess else {
            throw KeychainError.retrieveFailed(status)
        }
        
        guard let data = result as? Data,
              let password = String(data: data, encoding: .utf8) else {
            throw KeychainError.invalidData
        }
        
        return password
    }
    
    /// Delete password from Keychain
    static func deletePassword(for connectionId: UUID) throws {
        let account = connectionId.uuidString
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: account
        ]
        
        let status = SecItemDelete(query as CFDictionary)
        
        // Ignore errSecItemNotFound - item doesn't exist, which is fine
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.deleteFailed(status)
        }
    }
}

enum KeychainError: LocalizedError {
    case saveFailed(OSStatus)
    case retrieveFailed(OSStatus)
    case deleteFailed(OSStatus)
    case invalidData
    
    var errorDescription: String? {
        switch self {
        case .saveFailed(let status):
            return "Failed to save password to Keychain (error: \(status))"
        case .retrieveFailed(let status):
            return "Failed to retrieve password from Keychain (error: \(status))"
        case .deleteFailed(let status):
            return "Failed to delete password from Keychain (error: \(status))"
        case .invalidData:
            return "Invalid password data in Keychain"
        }
    }
}
