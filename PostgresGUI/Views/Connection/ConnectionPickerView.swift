//
//  ConnectionPickerView.swift
//  PostgresGUI
//
//  Created by ghazi on 11/28/25.
//

import SwiftUI
import SwiftData

struct ConnectionPickerView: View {
    @Query(sort: \ConnectionProfile.name) private var connections: [ConnectionProfile]
    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var modelContext
    
    var body: some View {
        Picker("Connection", selection: Binding(
            get: { appState.currentConnection },
            set: { appState.currentConnection = $0 }
        )) {
            Text("Select Connection").tag(nil as ConnectionProfile?)
            ForEach(connections) { connection in
                Text(connection.name).tag(connection as ConnectionProfile?)
            }
        }
        .pickerStyle(.menu)
        .labelsHidden()
        .onAppear {
            // If no connection is selected, try to restore last connection or auto-select first
            if appState.currentConnection == nil {
                // Try to restore last connection
                if let lastConnectionIdString = UserDefaults.standard.string(forKey: Constants.UserDefaultsKeys.lastConnectionId),
                   let lastConnectionId = UUID(uuidString: lastConnectionIdString),
                   let lastConnection = connections.first(where: { $0.id == lastConnectionId }) {
                    appState.currentConnection = lastConnection
                } else if let firstConnection = connections.first {
                    // Fallback to first connection if no last connection found
                    appState.currentConnection = firstConnection
                }
            }
        }
        .onChange(of: appState.currentConnection) { oldValue, newValue in
            if let connection = newValue {
                Task {
                    await connect(to: connection)
                }
            }
        }
    }
    
    private func connect(to connection: ConnectionProfile) async {
        do {
            // Get password from Keychain
            let password = try KeychainService.getPassword(for: connection.id) ?? ""
            
            // Connect
            try await appState.databaseService.connect(
                host: connection.host,
                port: connection.port,
                username: connection.username,
                password: password,
                database: connection.database
            )
            
            try? modelContext.save()
            
            // Update app state
            appState.isConnected = true
            
            // Save last connection ID
            UserDefaults.standard.set(connection.id.uuidString, forKey: Constants.UserDefaultsKeys.lastConnectionId)
            
            // Load databases
            await loadDatabases()
            
        } catch {
            // Handle error - could show alert here
            print("Failed to connect: \(error)")
        }
    }
    
    private func loadDatabases() async {
        do {
            appState.databases = try await appState.databaseService.fetchDatabases()
        } catch {
            print("Failed to load databases: \(error)")
        }
    }
}
