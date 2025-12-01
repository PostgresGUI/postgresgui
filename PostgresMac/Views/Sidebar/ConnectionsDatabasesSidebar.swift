//
//  ConnectionsDatabasesSidebar.swift
//  PostgresMac
//
//  Created by ghazi on 11/28/25.
//

import SwiftUI

struct ConnectionsDatabasesSidebar: View {
    @Environment(AppState.self) private var appState
    @State private var selectedDatabaseID: DatabaseInfo.ID?

    var body: some View {
        List(selection: Binding<DatabaseInfo.ID?>(
            get: { selectedDatabaseID },
            set: { newID in
                guard let unwrappedID = newID else {
                    selectedDatabaseID = nil
                    appState.selectedDatabase = nil
                    appState.tables = []
                    appState.isLoadingTables = false
                    print("🔴 [ConnectionsDatabasesSidebar] Selection cleared")
                    return
                }
                selectedDatabaseID = unwrappedID
                print("🟢 [ConnectionsDatabasesSidebar] selectedDatabaseID changed to \(unwrappedID)")

                // Find the database object from the ID
                let database = appState.databases.first { $0.id == unwrappedID }

                print("🔵 [ConnectionsDatabasesSidebar] Updating selectedDatabase to: \(database?.name ?? "nil")")
                appState.selectedDatabase = database

                // Clear tables immediately and show loading state
                appState.tables = []
                appState.isLoadingTables = true
                print("🟡 [ConnectionsDatabasesSidebar] Cleared tables, isLoadingTables=true")

                // Clear table selection and all query-related state
                appState.selectedTable = nil
                appState.queryText = ""
                appState.queryResults = []
                appState.queryColumnNames = nil
                appState.showQueryResults = false
                appState.queryError = nil
                appState.queryExecutionTime = nil
                print("🧹 [ConnectionsDatabasesSidebar] Cleared table selection and query state")

                if let database = database {
                    print("🟠 [ConnectionsDatabasesSidebar] Starting loadTables for: \(database.name)")
                    Task {
                        await loadTables(for: database)
                    }
                } else {
                    print("🔴 [ConnectionsDatabasesSidebar] No database selected, stopping loading")
                    appState.isLoadingTables = false
                }
            }
        )) {
            Section("Connection") {
                ConnectionPickerView()
            }

            Section("Databases") {
                if appState.databases.isEmpty {
                    Text("No databases")
                        .foregroundColor(.secondary)
                        .italic()
                } else {
                    ForEach(appState.databases) { database in
                        DatabaseRowView(database: database)
                    }
                }
            }
        }
        .navigationTitle("Databases")
        .onChange(of: appState.isConnected) { oldValue, newValue in
            if newValue {
                refreshDatabases()
            }
        }
    }
    
    private func refreshDatabases() {
        Task {
            await refreshDatabasesAsync()
        }
    }
    
    private func refreshDatabasesAsync() async {
        do {
            appState.databases = try await appState.databaseService.fetchDatabases()
        } catch {
            print("Failed to refresh databases: \(error)")
        }
    }
    
    private func loadTables(for database: DatabaseInfo) async {
        print("📍 [loadTables] START for database: \(database.name)")

        defer {
            print("📍 [loadTables] END - setting isLoadingTables=false")
            appState.isLoadingTables = false
        }

        do {
            // Reconnect to the selected database
            guard let connection = appState.currentConnection else {
                print("❌ [loadTables] ERROR: No current connection")
                return
            }
            print("✅ [loadTables] Current connection: \(connection.name)")

            // Get password from Keychain
            print("🔑 [loadTables] Getting password from Keychain for connection: \(connection.id)")
            let password = try KeychainService.getPassword(for: connection.id) ?? ""
            print("✅ [loadTables] Password retrieved (length: \(password.count))")

            // Reconnect to the selected database
            print("🔌 [loadTables] Connecting to database: \(database.name) at \(connection.host):\(connection.port)")
            try await appState.databaseService.connect(
                host: connection.host,
                port: connection.port,
                username: connection.username,
                password: password,
                database: database.name
            )
            print("✅ [loadTables] Connected successfully to \(database.name)")

            // Now fetch tables from the newly connected database
            print("📊 [loadTables] Fetching tables from database: \(database.name)")
            appState.tables = try await appState.databaseService.fetchTables(database: database.name)
            print("✅ [loadTables] Fetched \(appState.tables.count) tables")
            for (index, table) in appState.tables.enumerated() {
                print("   Table \(index + 1): \(table.schema).\(table.name)")
            }
        } catch {
            print("❌ [loadTables] ERROR: \(error)")
            print("❌ [loadTables] Error details: \(String(describing: error))")
            appState.tables = []
        }
    }
}

private struct DatabaseRowView: View {
    let database: DatabaseInfo
    @Environment(AppState.self) private var appState
    @State private var isHovered = false
    @State private var isButtonHovered = false
    @State private var showDeleteConfirmation = false
    @State private var deleteError: String?

    var body: some View {
        NavigationLink(value: database.id) {
            HStack {
                Label(database.name, systemImage: "externaldrive")
                Spacer()
                if isHovered {
                    Menu {
                        Button(role: .destructive) {
                            showDeleteConfirmation = true
                        } label: {
                            Text("Delete...")
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .foregroundColor(isButtonHovered ? .primary : .secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 6)
                            .background(isButtonHovered ? Color.secondary.opacity(0.2) : Color.clear)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                    .buttonStyle(.plain)
                    .onHover { hovering in
                        isButtonHovered = hovering
                    }
                }
            }
        }
        .contextMenu {
            Button(role: .destructive) {
                showDeleteConfirmation = true
            } label: {
                Label("Delete...", systemImage: "trash")
            }
        }
        .onHover { hovering in
            isHovered = hovering
        }
        .confirmationDialog(
            "Delete Database?",
            isPresented: $showDeleteConfirmation,
            presenting: database
        ) { database in
            Button(role: .destructive) {
                Task {
                    await deleteDatabase(database)
                }
            } label: {
                Text("Delete")
            }
            Button("Cancel", role: .cancel) {
                showDeleteConfirmation = false
            }
        } message: { database in
            Text("Are you sure you want to delete '\(database.name)'? This action cannot be undone.")
        }
        .alert("Error Deleting Database", isPresented: Binding(
            get: { deleteError != nil },
            set: { if !$0 { deleteError = nil } }
        )) {
            Button("OK", role: .cancel) {
                deleteError = nil
            }
        } message: {
            if let error = deleteError {
                Text(error)
            }
        }
    }
    
    private func deleteDatabase(_ database: DatabaseInfo) async {
        print("🗑️  [DatabaseRowView] Deleting database: \(database.name)")
        
        do {
            // Get connection details
            guard appState.currentConnection != nil else {
                print("❌ [DatabaseRowView] No current connection")
                return
            }
            
            // Delete the database (DatabaseService uses stored connection details)
            try await appState.databaseService.deleteDatabase(name: database.name)
            
            // Remove from databases list
            appState.databases.removeAll { $0.id == database.id }
            
            // Clear selection if this was the selected database
            if appState.selectedDatabase?.id == database.id {
                appState.selectedDatabase = nil
                appState.tables = []
                appState.isLoadingTables = false
            }
            
            // Refresh databases list
            await refreshDatabases()
            
            print("✅ [DatabaseRowView] Database deleted successfully")
        } catch {
            print("❌ [DatabaseRowView] Error deleting database: \(error)")
            // Display error message to user
            if let connectionError = error as? ConnectionError {
                deleteError = connectionError.errorDescription ?? "Failed to delete database."
            } else {
                deleteError = error.localizedDescription
            }
        }
    }
    
    private func refreshDatabases() async {
        do {
            appState.databases = try await appState.databaseService.fetchDatabases()
        } catch {
            print("Failed to refresh databases: \(error)")
        }
    }
}
