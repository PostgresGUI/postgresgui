//
//  TablesListView.swift
//  PostgresMac
//
//  Created by ghazi on 11/28/25.
//

import SwiftUI

struct TablesListView: View {
    @Environment(AppState.self) private var appState
    @State private var selectedTableID: TableInfo.ID?

    var body: some View {
        Group {
            if appState.isLoadingTables {
                ProgressView()
                    .scaleEffect(0.8)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if appState.tables.isEmpty {
                ContentUnavailableView {
                    Label {
                        Text("No tables found")
                            .font(.title3)
                            .fontWeight(.regular)
                    } icon: { }
                }
            } else {
                List(selection: Binding<TableInfo.ID?>(
                    get: { selectedTableID },
                    set: { newID in
                        guard let unwrappedID = newID else {
                            selectedTableID = nil
                            appState.selectedTable = nil
                            appState.showQueryResults = false
                            appState.queryText = ""
                            appState.queryResults = []
                            print("🔴 [TablesListView] Table selection cleared")
                            return
                        }
                        selectedTableID = unwrappedID
                        print("🟢 [TablesListView] selectedTableID changed to \(unwrappedID)")

                        // Find the table object from the ID
                        let table = appState.tables.first { $0.id == unwrappedID }

                        print("🔵 [TablesListView] Updating selectedTable to: \(table?.name ?? "nil")")
                        appState.selectedTable = table

                        if let table = table {
                            print("🟠 [TablesListView] Generating and executing query for: \(table.schema).\(table.name)")
                            Task {
                                await populateAndExecuteQuery(for: table)
                            }
                        }
                    }
                )) {
                    ForEach(appState.tables) { table in
                        TableRowView(table: table)
                    }
                }
            }
        }
        .navigationTitle("Tables")
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button(action: {
                    Task {
                        await refreshTables()
                    }
                }) {
                    Image(systemName: "arrow.clockwise")
                }
                .disabled(appState.isLoadingTables || appState.selectedDatabase == nil)
            }
        }
        .sheet(isPresented: Binding(
            get: { appState.showTableSchema },
            set: { appState.showTableSchema = $0 }
        )) {
            if let schemaTable = appState.schemaTable {
                NavigationStack {
                    TableSchemaView()
                        .navigationTitle("\(schemaTable.schema).\(schemaTable.name)")
                        .toolbar {
                            ToolbarItem(placement: .automatic) {
                                Button("Done") {
                                    appState.showTableSchema = false
                                    appState.schemaTable = nil
                                }
                            }
                        }
                }
            }
        }
    }

    private func generateTableQuery(for table: TableInfo) -> String {
        let escapedSchema = table.schema.replacingOccurrences(of: "\"", with: "\"\"")
        let escapedTable = table.name.replacingOccurrences(of: "\"", with: "\"\"")
        return "SELECT * FROM \"\(escapedSchema)\".\"\(escapedTable)\" LIMIT \(appState.rowsPerPage);"
    }

    @MainActor
    private func populateAndExecuteQuery(for table: TableInfo) async {
        print("🔍 [TablesListView] Auto-generating query for table: \(table.schema).\(table.name)")

        // Set loading state FIRST to prevent empty state flicker
        appState.isExecutingQuery = true
        appState.queryError = nil
        appState.queryExecutionTime = nil
        appState.showQueryResults = false // Hide results view during loading
        
        // Clear existing state to prevent rendering issues
        appState.columns = []
        appState.queryResults = []
        appState.queryColumnNames = nil

        // Fetch column metadata for the table first
        do {
            print("📋 [TablesListView] Fetching columns for table...")
            appState.columns = try await appState.databaseService.fetchColumns(schema: table.schema, table: table.name)
            print("✅ [TablesListView] Fetched \(appState.columns.count) columns")
        } catch {
            print("⚠️  [TablesListView] Failed to fetch columns: \(error)")
            appState.columns = []
        }

        // Generate SELECT query with pagination
        let query = generateTableQuery(for: table)
        print("📝 [TablesListView] Generated query: \(query)")

        // Update query text in editor
        appState.queryText = query

        // Ensure loading state is still set (in case it was cleared during column fetch)
        appState.isExecutingQuery = true
        appState.queryColumnNames = nil // Clear previous column names

        let startTime = Date()

        do {
            print("📊 [TablesListView] Executing query...")
            let (results, columnNames) = try await appState.databaseService.executeQuery(query)
            appState.queryResults = results
            appState.queryColumnNames = columnNames.isEmpty ? nil : columnNames
            appState.showQueryResults = true

            let endTime = Date()
            appState.queryExecutionTime = endTime.timeIntervalSince(startTime)

            print("✅ [TablesListView] Query executed successfully - \(appState.queryResults.count) rows")
        } catch {
            appState.queryError = error.localizedDescription
            appState.queryColumnNames = nil
            appState.showQueryResults = true

            let endTime = Date()
            appState.queryExecutionTime = endTime.timeIntervalSince(startTime)

            print("❌ [TablesListView] Query execution failed: \(error)")
        }

        appState.isExecutingQuery = false
    }
    
    @MainActor
    private func refreshTables() async {
        print("🔄 [TablesListView] Refresh tables START")
        
        guard let database = appState.selectedDatabase else {
            print("❌ [TablesListView] No database selected for refresh")
            return
        }
        
        defer {
            print("🔄 [TablesListView] Refresh tables END - setting isLoadingTables=false")
            appState.isLoadingTables = false
        }
        
        appState.isLoadingTables = true
        
        // Check if we're connected
        guard appState.databaseService.isConnected else {
            print("❌ [TablesListView] Not connected, cannot refresh")
            return
        }
        
        // Refresh databases list
        do {
            print("📊 [TablesListView] Fetching databases...")
            appState.databases = try await appState.databaseService.fetchDatabases()
            print("✅ [TablesListView] Refreshed \(appState.databases.count) databases")
        } catch {
            print("❌ [TablesListView] Error refreshing databases: \(error)")
            print("❌ [TablesListView] Error details: \(String(describing: error))")
            // Continue with table refresh even if database refresh fails
        }
        
        // Refresh tables list
        do {
            print("📊 [TablesListView] Fetching tables from database: \(database.name)")
            appState.tables = try await appState.databaseService.fetchTables(database: database.name)
            print("✅ [TablesListView] Refreshed \(appState.tables.count) tables")
        } catch {
            print("❌ [TablesListView] Error refreshing tables: \(error)")
            print("❌ [TablesListView] Error details: \(String(describing: error))")
            // Keep existing tables on error
        }
    }
}
