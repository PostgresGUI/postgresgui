//
//  NavigationState.swift
//  PostgresGUI
//
//  Created by ghazi on 12/17/25.
//

import SwiftUI

/// Manages navigation and modal presentation state
@Observable
@MainActor
class NavigationState {
    enum Sheet: Identifiable {
        case connectionForm(ConnectionProfile?)
        case createDatabase
        case keyboardShortcuts
        case help

        var id: String {
            switch self {
            case let .connectionForm(connection):
                return "connection-form-\(connection?.id.uuidString ?? "new")"
            case .createDatabase:
                return "create-database"
            case .keyboardShortcuts:
                return "keyboard-shortcuts"
            case .help:
                return "help"
            }
        }
    }

    // Navigation
    var navigationPath: NavigationPath = NavigationPath()

    // Modal/Sheet state
    var activeSheet: Sheet?

    var isShowingConnectionForm: Bool {
        if case .connectionForm = activeSheet {
            return true
        }
        return false
    }

    // Sheet management helpers
    func showConnectionForm(connectionToEdit: ConnectionProfile? = nil) {
        activeSheet = .connectionForm(connectionToEdit)
    }

    func showCreateDatabase() {
        activeSheet = .createDatabase
    }

    func showKeyboardShortcuts() {
        activeSheet = .keyboardShortcuts
    }

    func showHelp() {
        activeSheet = .help
    }

    func dismissSheet() {
        activeSheet = nil
    }
}
