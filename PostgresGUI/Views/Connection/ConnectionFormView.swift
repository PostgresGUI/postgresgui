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
    
    @State private var name: String = ""
    @State private var host: String = "localhost"
    @State private var port: String = "5432"
    @State private var username: String = "postgres"
    @State private var password: String = ""
    @State private var database: String = "postgres"
    
    @State private var testResult: String?
    @State private var testResultColor: Color = .primary
    @State private var isConnecting: Bool = false
    
    init(connectionToEdit: ConnectionProfile? = nil) {
        self.connectionToEdit = connectionToEdit
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Connection Name", text: $name)
                    TextField("Host", text: $host)
                    TextField("Port", text: $port)
                    TextField("Username", text: $username)
                    SecureField("Password", text: $password)
                    TextField("Database", text: $database)
                } header: {
                    Text(connectionToEdit == nil ? "Create New Connection" : "Edit Connection")
                }
                
                if let testResult = testResult {
                    Text(testResult)
                        .foregroundColor(testResultColor)
                }
            }
            .formStyle(.grouped)
            .onAppear {
                if let connection = connectionToEdit {
                    name = connection.name
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
                        .disabled(isConnecting || name.isEmpty)
                    }
                }
            }
        }
        .frame(width: 500, height: 400)
    }
    
    private func testConnection() async {
        isConnecting = true
        testResult = nil
        
        guard let portInt = Int(port), portInt > 0 && portInt <= 65535 else {
            testResult = "Invalid port number"
            testResultColor = .red
            isConnecting = false
            return
        }
        
        // Use password from field, or from Keychain if editing and field is empty
        let passwordToUse: String
        if !password.isEmpty {
            passwordToUse = password
        } else if let connection = connectionToEdit {
            passwordToUse = (try? KeychainService.getPassword(for: connection.id)) ?? ""
        } else {
            passwordToUse = ""
        }
        
        do {
            let success = try await DatabaseService.testConnection(
                host: host.isEmpty ? "localhost" : host,
                port: portInt,
                username: username.isEmpty ? "postgres" : username,
                password: passwordToUse,
                database: database.isEmpty ? "postgres" : database
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
        
        guard !name.isEmpty else {
            testResult = "Connection name is required"
            testResultColor = .red
            isConnecting = false
            return
        }
        
        guard let portInt = Int(port), portInt > 0 && portInt <= 65535 else {
            testResult = "Invalid port number"
            testResultColor = .red
            isConnecting = false
            return
        }
        
        do {
            let profile: ConnectionProfile
            
            if let existingConnection = connectionToEdit {
                // Update existing connection
                profile = existingConnection
                profile.name = name
                profile.host = host.isEmpty ? "localhost" : host
                profile.port = portInt
                profile.username = username.isEmpty ? "postgres" : username
                profile.database = database.isEmpty ? "postgres" : database
                
                // Update password in Keychain only if provided
                if !password.isEmpty {
                    try KeychainService.savePassword(password, for: profile.id)
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
                    name: name,
                    host: host.isEmpty ? "localhost" : host,
                    port: portInt,
                    username: username.isEmpty ? "postgres" : username,
                    database: database.isEmpty ? "postgres" : database
                )
                
                // Save password to Keychain
                if !password.isEmpty {
                    try KeychainService.savePassword(password, for: profile.id)
                }
                
                // Save profile to SwiftData
                modelContext.insert(profile)
                try modelContext.save()
            }
            
            // Connect to database (for both new and edited connections)
            let passwordToUse: String
            if !password.isEmpty {
                passwordToUse = password
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
