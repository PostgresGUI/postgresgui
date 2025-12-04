//
//  ConnectionsDatabasesSidebar.swift
//  PostgresGUI
//
//  Created by ghazi on 11/28/25.
//

import SwiftUI
import SwiftData

struct ConnectionsDatabasesSidebar: View {
    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ConnectionProfile.name) private var connections: [ConnectionProfile]
    @State private var selectedDatabaseID: DatabaseInfo.ID?
    @State private var connectionError: String?
    @State private var showConnectionError = false
    @State private var showCreateDatabaseForm = false
    @State private var newDatabaseName = ""
    @State private var createDatabaseError: String?
    @State private var hasRestoredConnection = false

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
                    // Save last selected database name
                    UserDefaults.standard.set(database.name, forKey: Constants.UserDefaultsKeys.lastDatabaseName)
                    
                    print("🟠 [ConnectionsDatabasesSidebar] Starting loadTables for: \(database.name)")
                    Task {
                        await loadTables(for: database)
                    }
                } else {
                    // Clear saved database when selection is cleared
                    UserDefaults.standard.removeObject(forKey: Constants.UserDefaultsKeys.lastDatabaseName)
                    print("🔴 [ConnectionsDatabasesSidebar] No database selected, stopping loading")
                    appState.isLoadingTables = false
                }
            }
        )) {
            Section("Connection") {
                HStack {
                    Picker("Connection", selection: Binding(
                        get: { appState.currentConnection },
                        set: { newConnection in
                            if let connection = newConnection {
                                Task {
                                    await connect(to: connection)
                                }
                            }
                        }
                    )) {
                        if appState.currentConnection == nil {
                            Text("Select Connection").tag(nil as ConnectionProfile?)
                        }
                        ForEach(connections) { connection in
                            Text(connection.name).tag(connection as ConnectionProfile?)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                                    
                    Button {
                        appState.showConnectionsList()
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .buttonStyle(.plain)

                    Button {
                        appState.connectionToEdit = nil
                        appState.showConnectionForm()
                    } label: {
                        Image(systemName: "plus.circle")
                    }
                    .buttonStyle(.plain)
                }
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
        .safeAreaInset(edge: .bottom) {
            if appState.isConnected {
                Button {
                    showCreateDatabaseForm = true
                } label: {
                    Label("Create Database", systemImage: "plus")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4) // increased y padding
                }
                .clipShape(RoundedRectangle(cornerRadius: 100, style: .continuous))
                .padding()
            }
        }
        .alert("Create Database", isPresented: $showCreateDatabaseForm) {
            TextField("Database Name", text: $newDatabaseName)
            Button("Create") {
                Task {
                    await createDatabase()
                }
            }
            Button("Cancel", role: .cancel) {
                newDatabaseName = ""
            }
        }
        .alert("Error Creating Database", isPresented: Binding(
            get: { createDatabaseError != nil },
            set: { if !$0 { createDatabaseError = nil } }
        )) {
            Button("OK", role: .cancel) {
                createDatabaseError = nil
            }
        } message: {
            if let error = createDatabaseError {
                Text(error)
            }
        }
        .onChange(of: appState.isConnected) { oldValue, newValue in
            if newValue {
                refreshDatabases()
            }
        }
        .onChange(of: appState.currentConnection) { oldValue, newValue in
            // Clear saved database when connection changes (databases are connection-specific)
            if oldValue != nil && newValue != oldValue {
                UserDefaults.standard.removeObject(forKey: Constants.UserDefaultsKeys.lastDatabaseName)
                selectedDatabaseID = nil
                appState.selectedDatabase = nil
            }
        }
        .task {
            // Restore last connection on app launch
            await restoreLastConnection()
        }
        .alert("Connection Failed", isPresented: $showConnectionError) {
            Button("OK", role: .cancel) {
                connectionError = nil
            }
        } message: {
            if let error = connectionError {
                Text(error)
            }
        }
    }
    
    private func restoreLastConnection() async {
        // Only restore once and if no connection is currently selected
        guard !hasRestoredConnection, appState.currentConnection == nil else { return }
        
        // Wait a bit for connections to load from SwiftData
        try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
        
        // Check again after waiting
        guard !connections.isEmpty else { return }
        
        hasRestoredConnection = true
        
        // Get last connection ID from UserDefaults
        guard let lastConnectionIdString = UserDefaults.standard.string(forKey: Constants.UserDefaultsKeys.lastConnectionId),
              let lastConnectionId = UUID(uuidString: lastConnectionIdString) else {
            return
        }
        
        // Find the connection in the list
        guard let lastConnection = connections.first(where: { $0.id == lastConnectionId }) else {
            // Connection not found, clear the stored ID
            UserDefaults.standard.removeObject(forKey: Constants.UserDefaultsKeys.lastConnectionId)
            return
        }
        
        // Set the connection and connect
        // Note: Setting currentConnection programmatically doesn't trigger the picker's setter
        appState.currentConnection = lastConnection
        await connect(to: lastConnection)
    }
    
    private func refreshDatabases() {
        Task {
            await refreshDatabasesAsync()
        }
    }
    
    private func refreshDatabasesAsync() async {
        do {
            appState.databases = try await appState.databaseService.fetchDatabases()
            
            // After refreshing databases, restore last selected database if available
            await restoreLastDatabase()
        } catch {
            print("Failed to refresh databases: \(error)")
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
                database: connection.database,
                sslMode: connection.sslModeEnum
            )
            
            try? modelContext.save()
            
            // Update app state
            appState.currentConnection = connection
            appState.isConnected = true
            appState.isShowingWelcomeScreen = false
            
            // Save last connection ID
            UserDefaults.standard.set(connection.id.uuidString, forKey: Constants.UserDefaultsKeys.lastConnectionId)
            
            // Load databases
            await loadDatabases()
            
        } catch {
            print("Failed to connect: \(error)")
            connectionError = error.localizedDescription
            showConnectionError = true
            // Reset connection state on error
            appState.currentConnection = nil
            appState.isConnected = false
        }
    }
    
    private func loadDatabases() async {
        do {
            appState.databases = try await appState.databaseService.fetchDatabases()
            
            // After loading databases, restore last selected database if available
            await restoreLastDatabase()
        } catch {
            print("Failed to load databases: \(error)")
        }
    }
    
    private func restoreLastDatabase() async {
        // Only restore if no database is currently selected and we have databases
        guard appState.selectedDatabase == nil, !appState.databases.isEmpty else { return }
        
        // Get last database name from UserDefaults
        guard let lastDatabaseName = UserDefaults.standard.string(forKey: Constants.UserDefaultsKeys.lastDatabaseName),
              !lastDatabaseName.isEmpty else {
            return
        }
        
        // Find the database in the list
        guard let lastDatabase = appState.databases.first(where: { $0.name == lastDatabaseName }) else {
            // Database not found, clear the stored name
            UserDefaults.standard.removeObject(forKey: Constants.UserDefaultsKeys.lastDatabaseName)
            return
        }
        
        // Set the database selection
        // Note: We set both the local state and appState to ensure consistency
        selectedDatabaseID = lastDatabase.id
        appState.selectedDatabase = lastDatabase
        
        // Clear tables immediately and show loading state
        appState.tables = []
        appState.isLoadingTables = true
        
        // Clear table selection and all query-related state
        appState.selectedTable = nil
        appState.queryText = ""
        appState.queryResults = []
        appState.queryColumnNames = nil
        appState.showQueryResults = false
        appState.queryError = nil
        appState.queryExecutionTime = nil
        
        // Load tables for the restored database
        await loadTables(for: lastDatabase)
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
                database: database.name,
                sslMode: connection.sslModeEnum
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
    
    private func createDatabase() async {
        guard !newDatabaseName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            createDatabaseError = "Database name cannot be empty"
            return
        }
        
        let databaseName = newDatabaseName.trimmingCharacters(in: .whitespacesAndNewlines)
        
        do {
            try await appState.databaseService.createDatabase(name: databaseName)
            newDatabaseName = ""
            await refreshDatabasesAsync()
        } catch {
            createDatabaseError = error.localizedDescription
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
