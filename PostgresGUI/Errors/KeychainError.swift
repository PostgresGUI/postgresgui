//
//  KeychainError.swift
//  PostgresGUI
//
//  Created by ghazi on 11/28/25.
//

import Foundation

enum KeychainError: LocalizedError {
    case saveFailed(OSStatus)
    case retrieveFailed(OSStatus)
    case deleteFailed(OSStatus)
    case invalidData
    case accessGroupUnavailable
    
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
        case .accessGroupUnavailable:
            return "The app's Keychain access group is unavailable"
        }
    }
}
