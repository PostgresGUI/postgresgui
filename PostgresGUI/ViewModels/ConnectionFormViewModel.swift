//
//  ConnectionFormViewModel.swift
//  PostgresGUI
//
//  Created by ghazi on 12/17/25.
//

import Foundation
import SwiftUI
import SwiftData
import AppKit

/// Input mode for connection form
enum ConnectionInputMode {
    case individual
    case connectionString
}

/// ViewModel for ConnectionFormView - handles all business logic and state
@Observable
@MainActor
class ConnectionFormViewModel {
    // MARK: - Dependencies

    private let appState: AppState
    private let keychainService: KeychainServiceProtocol
    let connectionToEdit: ConnectionProfile?

    // MARK: - Form State - Individual Fields

    var individualName: String = ""
    var host: String = "localhost"
    var port: String = "5432"
    var username: String = "postgres"
    var password: String = ""
    var database: String = "postgres"
    var showPassword: Bool = false
    var showIndividualNameField: Bool = false

    // MARK: - Form State - Connection String

    var connectionString: String = ""
    var connectionStringName: String = ""
    var showConnectionStringNameField: Bool = false
    var copyButtonLabel: String = "Copy"

    // MARK: - SSL Mode State

    var sslModeSelection: SSLMode = .default
    private var isSSLModeUserSelected: Bool = false

    // MARK: - Input Mode

    var inputMode: ConnectionInputMode = .individual

    // MARK: - Connection Test State

    var isConnecting: Bool = false
    var connectionTestStatus: ConnectionTestStatus = .idle

    // MARK: - Password Management

    var hasStoredPassword: Bool = false
    var actualStoredPassword: String = ""
    var passwordModified: Bool = false

    // MARK: - Alert State

    var showKeychainAlert: Bool = false
    var keychainAlertMessage: String = ""

    // Connection saved alert state
    var showConnectionSavedAlert: Bool = false
    var savedConnectionProfile: ConnectionProfile?
    private var savedConnectionPassword: String = ""

    // MARK: - Computed Properties

    var isEditing: Bool {
        connectionToEdit != nil
    }

    var currentName: String? {
        if inputMode == .individual {
            return showIndividualNameField && !individualName.isEmpty ? individualName : nil
        } else {
            return showConnectionStringNameField && !connectionStringName.isEmpty ? connectionStringName : nil
        }
    }

    var navigationTitle: LocalizedStringKey {
        isEditing ? "Edit Connection" : "Create New Connection"
    }

    var toggleLabel: LocalizedStringKey {
        isEditing ? "View Connection String" : "Use Connection String"
    }

    // MARK: - Initialization

    init(
        appState: AppState,
        keychainService: KeychainServiceProtocol? = nil,
        connectionToEdit: ConnectionProfile? = nil
    ) {
        self.appState = appState
        self.keychainService = keychainService ?? KeychainServiceImpl()
        self.connectionToEdit = connectionToEdit
    }

    /// Load connection data when editing
    func loadConnectionIfNeeded() {
        guard let connection = connectionToEdit else { return }

        // Populate both name fields with the same value initially
        individualName = connection.name ?? ""
        connectionStringName = connection.name ?? ""
        host = connection.host
        port = String(connection.port)
        username = connection.username
        database = connection.database

        // Password handling - don't access keychain on form load
        hasStoredPassword = true
        actualStoredPassword = ""
        passwordModified = false
        password = String(repeating: "•", count: 8)

        // Show name fields when editing only if name is not nil
        showIndividualNameField = connection.name != nil
        showConnectionStringNameField = connection.name != nil

        // If in connection string mode, populate the connection string
        if inputMode == .connectionString {
            connectionString = generateConnectionString()
        }

    }

    // MARK: - Input Mode Handling

    func handleInputModeChange(to newMode: ConnectionInputMode) {
        connectionTestStatus = .idle

        // If switching to connection string mode in edit mode, populate the connection string
        if newMode == .connectionString, isEditing {
            connectionString = generateConnectionString()
        }

        inputMode = newMode

        if newMode == .individual {
            updateSSLModeForHostIfNeeded(host)
        }
    }

    // MARK: - Password Handling

    /// Load password from keychain when user clicks "Show Password"
    func loadPasswordFromKeychain() -> Bool {
        guard let connection = connectionToEdit else { return true }

        do {
            if let keychainPassword = try keychainService.getPassword(for: connection.id) {
                actualStoredPassword = keychainPassword
                return true
            } else {
                actualStoredPassword = ""
                return true
            }
        } catch {
            connectionTestStatus = .error(
                message: "Unable to retrieve password from keychain. You may need to grant access in System Settings > Privacy & Security."
            )
            return false
        }
    }

    /// Get the actual password value for connection
    func getActualPassword() -> String {
        if let connection = connectionToEdit {
            if hasStoredPassword && !passwordModified {
                return (try? keychainService.getPassword(for: connection.id)) ?? ""
            }
        }
        return password
    }

    /// Handle password field change
    func handlePasswordChange(_ newValue: String) {
        password = newValue
        if hasStoredPassword && !passwordModified {
            passwordModified = true
        }
    }

    // MARK: - Connection String Handling

    func generateConnectionString() -> String {
        guard let connection = connectionToEdit else { return "" }

        let passwordPlaceholder = hasStoredPassword ? "YOUR_PASSWORD" : nil

        return ConnectionStringParser.build(
            username: connection.username,
            password: passwordPlaceholder,
            host: connection.host,
            port: connection.port,
            database: connection.database,
            sslMode: connection.sslModeEnum
        )
    }

    func copyConnectionStringToClipboard() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(connectionString, forType: .string)

        copyButtonLabel = "Copied!"
        Task {
            try? await Task.sleep(nanoseconds: 1.5.nanoseconds)
            copyButtonLabel = "Copy"
        }
    }

    // MARK: - Connection Testing

    func testConnection() async {
        isConnecting = true

        let testStartTime = Date()
        connectionTestStatus = .testing

        DebugLog.print("🧪 [ConnectionFormViewModel] ========== Starting Connection Test ==========")
        DebugLog.print("   Mode: \(inputMode == .connectionString ? "Connection String" : "Individual Fields")")

        do {
            let details = try parseConnectionDetails()

            DebugLog.print("   Final connection parameters:")
            DebugLog.print("     Host: \(details.host)")
            DebugLog.print("     Port: \(details.port)")
            DebugLog.print("     Username: \(details.username)")
            DebugLog.print("     Database: \(details.database)")
            DebugLog.print("     SSL Mode: \(details.sslMode.rawValue)")

            let success = try await DatabaseService.testConnection(
                host: details.host,
                port: details.port,
                username: details.username,
                password: details.password,
                database: details.database,
                sslMode: details.sslMode
            )

            // Ensure testing state is visible for at least 150ms
            let elapsed = Date().timeIntervalSince(testStartTime)
            if elapsed < 0.15 {
                try? await Task.sleep(nanoseconds: (0.15 - elapsed).nanoseconds)
            }

            if success {
                DebugLog.print("   ✅ Connection test successful!")
                connectionTestStatus = .success
            } else {
                DebugLog.print("   ❌ Connection test failed (returned false)")
                connectionTestStatus = .error(message: "Could not connect to \(details.host):\(details.port)")
            }
        } catch let error as ConnectionFormError {
            await handleTestError(error.message, startTime: testStartTime)
        } catch {
            let message = PostgresError.extractDetailedMessage(error)
            await handleTestError(message, startTime: testStartTime)
        }

        isConnecting = false
    }

    private func handleTestError(_ message: String, startTime: Date) async {
        let elapsed = Date().timeIntervalSince(startTime)
        if elapsed < 0.15 {
            try? await Task.sleep(nanoseconds: (0.15 - elapsed).nanoseconds)
        }
        connectionTestStatus = .error(message: message)
        DebugLog.print("   ❌ \(message)")
    }

    // MARK: - Save Connection

    func saveConnection(modelContext: ModelContext) async -> Bool {
        isConnecting = true

        do {
            let details = try parseConnectionDetails()

            let profile: ConnectionProfile

            if let existingConnection = connectionToEdit {
                // Update existing connection
                profile = existingConnection

                // Check if connection-critical parameters changed (requires reconnect)
                let connectionParamsChanged = profile.host != details.host ||
                    profile.port != details.port ||
                    profile.username != details.username ||
                    profile.database != details.database ||
                    profile.sslMode != details.sslMode.rawValue ||
                    passwordModified

                profile.name = currentName
                profile.host = details.host
                profile.port = details.port
                profile.username = details.username
                profile.database = details.database
                profile.sslMode = details.sslMode.rawValue

                // Update password if modified
                if passwordModified {
                    if !password.isEmpty {
                        try keychainService.savePassword(password, for: profile.id)
                    } else {
                        try? keychainService.deletePassword(for: profile.id)
                    }
                }

                // Save changes to SwiftData
                try modelContext.save()

                // Only disconnect if connection-critical parameters changed
                // (name-only changes don't require reconnection)
                if connectionParamsChanged && appState.connection.currentConnection?.id == profile.id {
                    await appState.connection.databaseService.disconnect()
                    appState.connection.currentConnection = nil
                    appState.connection.selectedDatabase = nil
                    appState.connection.selectedTable = nil
                    appState.connection.tables = []
                    appState.connection.databases = []
                    appState.connection.databasesVersion += 1
                }
            } else {
                // Create new connection
                profile = ConnectionProfile(
                    name: currentName,
                    host: details.host,
                    port: details.port,
                    username: details.username,
                    database: details.database,
                    sslMode: details.sslMode,
                    password: nil
                )

                // Save password to keychain
                if !details.password.isEmpty {
                    try keychainService.savePassword(details.password, for: profile.id)
                }

                modelContext.insert(profile)
                try modelContext.save()

                // Auto-connect if first connection, otherwise show alert
                let descriptor = FetchDescriptor<ConnectionProfile>()
                let allConnections = try modelContext.fetch(descriptor)

                if allConnections.count == 1 {
                    await autoConnect(to: profile, password: details.password)
                } else {
                    // Show connection saved alert with Connect/Dismiss options
                    savedConnectionProfile = profile
                    savedConnectionPassword = details.password
                    showConnectionSavedAlert = true
                    return false  // Don't dismiss yet - wait for alert response
                }
            }

            DebugLog.print("✅ [ConnectionFormViewModel] Connection profile saved successfully")
            isConnecting = false
            return true

        } catch let error as ConnectionFormError {
            keychainAlertMessage = error.message
            showKeychainAlert = true
            isConnecting = false
            return false
        } catch {
            DebugLog.print("❌ [ConnectionFormViewModel] Save error: \(error)")
            keychainAlertMessage = error.localizedDescription
            showKeychainAlert = true
            isConnecting = false
            return false
        }
    }

    private func autoConnect(to connection: ConnectionProfile, password: String) async {
        let connectionService = ConnectionService(
            appState: appState,
            keychainService: keychainService
        )

        let result = await connectionService.connect(
            to: connection,
            password: password,
            saveAsLast: true
        )

        switch result {
        case .success:
            DebugLog.print("✅ [ConnectionFormViewModel] Auto-connect successful")
        case .failure(let error):
            DebugLog.print("❌ [ConnectionFormViewModel] Auto-connect failed: \(error)")
        }
    }

    /// Called when user chooses to connect from the "Connection Saved" alert
    func connectToSavedConnection() async {
        guard let profile = savedConnectionProfile else { return }
        await autoConnect(to: profile, password: savedConnectionPassword)
        clearSavedConnectionState()
    }

    /// Called when user chooses "Not Now" from the "Connection Saved" alert
    func dismissSavedConnectionAlert() {
        clearSavedConnectionState()
    }

    private func clearSavedConnectionState() {
        savedConnectionProfile = nil
        savedConnectionPassword = ""
        showConnectionSavedAlert = false
    }

    // MARK: - Private Helpers

    private struct ConnectionDetails {
        let host: String
        let port: Int
        let username: String
        let password: String
        let database: String
        let sslMode: SSLMode
    }

    private func parseConnectionDetails() throws -> ConnectionDetails {
        if inputMode == .connectionString {
            return try parseConnectionString()
        } else {
            return try parseIndividualFields()
        }
    }

    private func parseConnectionString() throws -> ConnectionDetails {
        let parsed = try ConnectionStringParser.parse(connectionString)

        var parsedPassword = parsed.password ?? ""

        // Replace YOUR_PASSWORD placeholder with keychain password
        if let connection = connectionToEdit, parsedPassword == "YOUR_PASSWORD" {
            if let keychainPassword = try? keychainService.getPassword(for: connection.id), !keychainPassword.isEmpty {
                parsedPassword = keychainPassword
            }
        }

        return ConnectionDetails(
            host: parsed.host,
            port: parsed.port,
            username: parsed.username ?? Constants.PostgreSQL.defaultUsername,
            password: parsedPassword,
            database: parsed.database ?? Constants.PostgreSQL.defaultDatabase,
            sslMode: parsed.sslMode
        )
    }

    private func parseIndividualFields() throws -> ConnectionDetails {
        let trimmedHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPort = port.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedUsername = username.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedDatabase = database.trimmingCharacters(in: .whitespacesAndNewlines)

        guard let portInt = Int(trimmedPort), portInt > 0 && portInt <= 65535 else {
            throw ConnectionFormError(message: "Invalid port number")
        }

        let passwordToUse: String
        if let connection = connectionToEdit {
            if let keychainPassword = try? keychainService.getPassword(for: connection.id), !keychainPassword.isEmpty {
                passwordToUse = passwordModified ? password : keychainPassword
            } else {
                passwordToUse = password
            }
        } else {
            passwordToUse = password
        }

        return ConnectionDetails(
            host: trimmedHost.isEmpty ? "localhost" : trimmedHost,
            port: portInt,
            username: trimmedUsername.isEmpty ? "postgres" : trimmedUsername,
            password: passwordToUse,
            database: trimmedDatabase.isEmpty ? "postgres" : trimmedDatabase,
            sslMode: sslModeSelection
        )
    }

    // MARK: - SSL Mode Handling

    func handleHostChange(_ newHost: String) {
        updateSSLModeForHostIfNeeded(newHost)
    }

    func setSSLModeSelection(_ newMode: SSLMode) {
        sslModeSelection = newMode
        isSSLModeUserSelected = true
    }

    func initializeSSLModeIfNeeded() {
        if let connection = connectionToEdit {
            sslModeSelection = connection.sslModeEnum
            isSSLModeUserSelected = true
        } else {
            sslModeSelection = SSLMode.defaultFor(host: host)
            isSSLModeUserSelected = false
        }
    }

    private func updateSSLModeForHostIfNeeded(_ newHost: String) {
        guard !isSSLModeUserSelected else { return }
        let trimmedHost = newHost.trimmingCharacters(in: .whitespacesAndNewlines)
        sslModeSelection = SSLMode.defaultFor(host: trimmedHost)
    }
}

// MARK: - Error Type

private struct ConnectionFormError: Error {
    let message: String
}
