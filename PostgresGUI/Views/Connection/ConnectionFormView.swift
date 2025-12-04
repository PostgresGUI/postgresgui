//
//  ConnectionFormView.swift
//  PostgresGUI
//
//  Created by ghazi on 11/28/25.
//

import SwiftUI
import SwiftData

struct ConnectionFormView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(AppState.self) private var appState

    var connectionToEdit: ConnectionProfile?

    // Separate connection names for each tab
    @State private var individualName: String = ""
    @State private var connectionStringName: String = ""

    // Individual fields
    @State private var host: String = "localhost"
    @State private var port: String = "5432"
    @State private var username: String = "postgres"
    @State private var password: String = ""
    @State private var database: String = "postgres"

    @State private var testResult: String?
    @State private var testResultColor: Color = .primary
    @State private var isConnecting: Bool = false

    @State private var inputMode: ConnectionInputMode = .individual
    @State private var connectionString: String = ""
    @State private var connectionStringWarnings: [String] = []

    enum ConnectionInputMode {
        case individual
        case connectionString
    }

    init(connectionToEdit: ConnectionProfile? = nil) {
        self.connectionToEdit = connectionToEdit
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Header with title and toggle
                HStack {
                    Text(connectionToEdit == nil ? "Create New Connection" : "Edit Connection")
                        .font(.headline)

                    Spacer()

                    Button(action: {
                        let oldMode = inputMode
                        let newMode: ConnectionInputMode = inputMode == .individual ? .connectionString : .individual
                        handleInputModeChange(from: oldMode, to: newMode)
                        inputMode = newMode
                    }) {
                        Image(systemName: "link")
                            .imageScale(.large)
                    }
                    .padding()
                    .buttonBorderShape(.circle)
                    .buttonStyle(.glass)
                }
                .padding()
                .background(Color(nsColor: .controlBackgroundColor))

                Divider()

                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        if inputMode == .individual {
                            individualFieldsView
                        } else {
                            connectionStringView
                        }

                        // Test result
                        if let testResult = testResult {
                            Divider()
                            HStack(spacing: 12) {
                                Text("")
                                    .frame(width: 120, alignment: .trailing)
                                Text(testResult)
                                    .foregroundColor(testResultColor)
                                    .font(.caption)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .padding(.vertical, 6)
                        }
                    }
                    .padding(20)
                }
                .background(Color(nsColor: .controlBackgroundColor))
            }
            .onAppear {
                if let connection = connectionToEdit {
                    // Populate both name fields with the same value initially
                    individualName = connection.name
                    connectionStringName = connection.name
                    host = connection.host
                    port = String(connection.port)
                    username = connection.username
                    database = connection.database
                    // Don't load password - user needs to re-enter if changing
                    password = ""
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    HStack {
                        Button("Test") {
                            Task {
                                await testConnection()
                            }
                        }
                        .disabled(isConnecting)

                        Button(connectionToEdit == nil ? "Connect" : "Save") {
                            Task {
                                await connect()
                            }
                        }
                        .disabled(isConnecting || currentName.isEmpty)
                    }
                }
            }
        }
        .frame(width: 500, height: 400)
    }

    // MARK: - Individual Fields View

    private var individualFieldsView: some View {
        VStack(alignment: .leading, spacing: 0) {
            formRow(label: "Connection Name") {
                TextField("", text: $individualName)
                    .textFieldStyle(.roundedBorder)
            }

            Divider()

            formRow(label: "Host") {
                TextField("localhost", text: $host)
                    .textFieldStyle(.roundedBorder)
            }

            Divider()

            formRow(label: "Port") {
                TextField("5432", text: $port)
                    .textFieldStyle(.roundedBorder)
            }

            Divider()

            formRow(label: "Username") {
                TextField("postgres", text: $username)
                    .textFieldStyle(.roundedBorder)
            }

            Divider()

            formRow(label: "Password") {
                SecureField("", text: $password)
                    .textFieldStyle(.roundedBorder)
            }

            Divider()

            formRow(label: "Database") {
                TextField("postgres", text: $database)
                    .textFieldStyle(.roundedBorder)
            }
        }
    }

    // MARK: - Connection String View

    private var connectionStringView: some View {
        VStack(alignment: .leading, spacing: 0) {
            formRow(label: "Connection Name") {
                TextField("", text: $connectionStringName)
                    .textFieldStyle(.roundedBorder)
            }

            Divider()

            formRow(label: "Connection String") {
                VStack(alignment: .leading, spacing: 4) {
                    TextEditor(text: $connectionString)
                        .font(.system(.body, design: .monospaced))
                        .frame(height: 80)
                        .padding(4)
                        .background(Color(nsColor: .textBackgroundColor))
                        .cornerRadius(4)
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
                        )
                        .onChange(of: connectionString) { _, _ in
                            validateConnectionString()
                        }

                    if !connectionStringWarnings.isEmpty {
                        ForEach(connectionStringWarnings, id: \.self) { warning in
                            Label(warning, systemImage: "exclamationmark.triangle.fill")
                                .foregroundColor(.orange)
                                .font(.caption)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Helper Views

    private func formRow<Content: View>(
        label: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(label)
                .frame(width: 120, alignment: .trailing)
                .foregroundColor(.secondary)
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 6)
    }

    // MARK: - Computed Properties

    private var currentName: String {
        inputMode == .individual ? individualName : connectionStringName
    }

    // MARK: - Helper Methods

    private func handleInputModeChange(from oldMode: ConnectionInputMode, to newMode: ConnectionInputMode) {
        // No automatic sync - each tab maintains its own state independently
        // Clear any previous errors when switching tabs
        testResult = nil
        connectionStringWarnings.removeAll()
    }

    private func validateConnectionString() {
        connectionStringWarnings.removeAll()

        guard !connectionString.isEmpty else { return }

        do {
            let parsed = try ConnectionStringParser.parse(connectionString)

            // Check for unsupported parameters
            if !parsed.unsupportedParameters.isEmpty {
                let params = parsed.unsupportedParameters.joined(separator: ", ")
                connectionStringWarnings.append("Unsupported parameters will be ignored: \(params)")
            }

            // Clear any previous parse errors
            if testResultColor == .red {
                testResult = nil
            }
        } catch {
            // Show parse error
            testResult = error.localizedDescription
            testResultColor = .red
        }
    }

    private func testConnection() async {
        isConnecting = true
        testResult = nil
        connectionStringWarnings.removeAll()

        // Parse connection details based on input mode
        let connectionDetails: (host: String, port: Int, username: String, password: String, database: String)

        do {
            if inputMode == .connectionString {
                let parsed = try ConnectionStringParser.parse(connectionString)

                // Show warnings for unsupported parameters
                if !parsed.unsupportedParameters.isEmpty {
                    let params = parsed.unsupportedParameters.joined(separator: ", ")
                    connectionStringWarnings.append("Unsupported parameters will be ignored: \(params)")
                }

                connectionDetails = (
                    host: parsed.host,
                    port: parsed.port,
                    username: parsed.username ?? Constants.PostgreSQL.defaultUsername,
                    password: parsed.password ?? "",
                    database: parsed.database ?? Constants.PostgreSQL.defaultDatabase
                )
            } else {
                // Individual fields mode (existing logic)
                guard let portInt = Int(port), portInt > 0 && portInt <= 65535 else {
                    testResult = "Invalid port number"
                    testResultColor = .red
                    isConnecting = false
                    return
                }

                let passwordToUse: String
                if !password.isEmpty {
                    passwordToUse = password
                } else if let connection = connectionToEdit {
                    passwordToUse = (try? KeychainService.getPassword(for: connection.id)) ?? ""
                } else {
                    passwordToUse = ""
                }

                connectionDetails = (
                    host: host.isEmpty ? "localhost" : host,
                    port: portInt,
                    username: username.isEmpty ? "postgres" : username,
                    password: passwordToUse,
                    database: database.isEmpty ? "postgres" : database
                )
            }

            // Test connection with parsed details
            let success = try await DatabaseService.testConnection(
                host: connectionDetails.host,
                port: connectionDetails.port,
                username: connectionDetails.username,
                password: connectionDetails.password,
                database: connectionDetails.database
            )

            if success {
                testResult = "Connection successful!"
                testResultColor = .green
            } else {
                testResult = "Connection failed"
                testResultColor = .red
            }
        } catch {
            testResult = error.localizedDescription
            testResultColor = .red
        }

        isConnecting = false
    }

    private func connect() async {
        isConnecting = true
        connectionStringWarnings.removeAll()

        guard !currentName.isEmpty else {
            testResult = "Connection name is required"
            testResultColor = .red
            isConnecting = false
            return
        }

        // Parse connection details based on input mode
        let connectionDetails: (host: String, port: Int, username: String, password: String, database: String)

        do {
            if inputMode == .connectionString {
                let parsed = try ConnectionStringParser.parse(connectionString)

                // Show warnings for unsupported parameters
                if !parsed.unsupportedParameters.isEmpty {
                    let params = parsed.unsupportedParameters.joined(separator: ", ")
                    connectionStringWarnings.append("Unsupported parameters will be ignored: \(params)")
                }

                connectionDetails = (
                    host: parsed.host,
                    port: parsed.port,
                    username: parsed.username ?? Constants.PostgreSQL.defaultUsername,
                    password: parsed.password ?? "",
                    database: parsed.database ?? Constants.PostgreSQL.defaultDatabase
                )
            } else {
                // Individual fields mode (existing logic)
                guard let portInt = Int(port), portInt > 0 && portInt <= 65535 else {
                    testResult = "Invalid port number"
                    testResultColor = .red
                    isConnecting = false
                    return
                }

                let passwordToUse: String
                if !password.isEmpty {
                    passwordToUse = password
                } else if let connection = connectionToEdit {
                    passwordToUse = (try? KeychainService.getPassword(for: connection.id)) ?? ""
                } else {
                    passwordToUse = ""
                }

                connectionDetails = (
                    host: host.isEmpty ? "localhost" : host,
                    port: portInt,
                    username: username.isEmpty ? "postgres" : username,
                    password: passwordToUse,
                    database: database.isEmpty ? "postgres" : database
                )
            }

            let profile: ConnectionProfile

            if let existingConnection = connectionToEdit {
                // Update existing connection
                profile = existingConnection
                profile.name = currentName
                profile.host = connectionDetails.host
                profile.port = connectionDetails.port
                profile.username = connectionDetails.username
                profile.database = connectionDetails.database

                // Update password in Keychain only if provided
                if !connectionDetails.password.isEmpty {
                    try KeychainService.savePassword(connectionDetails.password, for: profile.id)
                }

                // Save changes to SwiftData
                try modelContext.save()

                // If this is the current connection, disconnect and reconnect
                if appState.currentConnection?.id == profile.id {
                    await appState.databaseService.disconnect()
                    appState.isConnected = false
                }
            } else {
                // Create new connection
                profile = ConnectionProfile(
                    name: currentName,
                    host: connectionDetails.host,
                    port: connectionDetails.port,
                    username: connectionDetails.username,
                    database: connectionDetails.database
                )

                // Save password to Keychain
                if !connectionDetails.password.isEmpty {
                    try KeychainService.savePassword(connectionDetails.password, for: profile.id)
                }

                // Save profile to SwiftData
                modelContext.insert(profile)
                try modelContext.save()
            }

            // Connect to database (for both new and edited connections)
            let passwordToUse: String
            if !connectionDetails.password.isEmpty {
                passwordToUse = connectionDetails.password
            } else {
                // Try to get password from Keychain
                passwordToUse = (try? KeychainService.getPassword(for: profile.id)) ?? ""
            }

            try await appState.databaseService.connect(
                host: profile.host,
                port: profile.port,
                username: profile.username,
                password: passwordToUse,
                database: profile.database
            )

            try? modelContext.save()

            // Update app state
            appState.currentConnection = profile
            appState.isConnected = true
            appState.isShowingWelcomeScreen = false

            // Load databases
            await loadDatabases()

            // Dismiss and transition to MainSplitView
            dismiss()

        } catch {
            testResult = error.localizedDescription
            testResultColor = .red
        }

        isConnecting = false
    }

    private func loadDatabases() async {
        do {
            appState.databases = try await appState.databaseService.fetchDatabases()
        } catch {
            testResult = "Connected but failed to load databases: \(error.localizedDescription)"
            testResultColor = .orange
        }
    }
}
