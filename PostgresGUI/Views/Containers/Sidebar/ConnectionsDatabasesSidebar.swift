//
//  ConnectionsDatabasesSidebar.swift
//  PostgresGUI
//
//  Sidebar for connection and database selection. Delegates business logic to ConnectionSidebarViewModel.
//

import SwiftData
import SwiftUI

struct ConnectionsDatabasesSidebar: View {
    @Environment(AppState.self) private var appState
    @Environment(TabManager.self) private var tabManager
    @Environment(LoadingState.self) private var loadingState
    @Environment(\.modelContext) private var modelContext
    @Environment(\.keychainService) private var keychainService

    @Query private var connections: [ConnectionProfile]

    @State private var viewModel: ConnectionSidebarViewModel?

    // Connection dropdown state
    @State private var showConnectionDropdown = false

    // Database dropdown state
    @State private var showDatabaseDropdown = false
    @State private var isRefreshButtonHovered = false

    var body: some View {
        contentWithChangeHandlers
            .onAppear {
                _ = ensureViewModel()
            }
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    Button {
                        DebugLog.print("🔄 [ConnectionsDatabasesSidebar] Refresh toolbar button clicked")
                        Task { @MainActor in
                            await ensureViewModel().refreshOnDemandFromToolbar()
                        }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .contentShape(Rectangle())
                    .onHover { isRefreshButtonHovered = $0 }
                    .help("")
                    .popover(
                        isPresented: Binding(
                            get: { isRefreshButtonHovered },
                            set: { newValue in
                                if !newValue {
                                    isRefreshButtonHovered = false
                                }
                            }
                        ),
                        arrowEdge: .bottom
                    ) {
                        Text("Refreshes database list and table list.")
                            .lineLimit(2)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: 280, alignment: .center)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(8)
                    }
                }
            }
            .modifier(DatabaseAlertsModifier(
                showConnectionError: Binding(
                    get: { viewModel?.showConnectionError ?? false },
                    set: { viewModel?.showConnectionError = $0 }
                ),
                connectionError: Binding(
                    get: { viewModel?.connectionError },
                    set: { viewModel?.connectionError = $0 }
                ),
                databaseToDelete: Binding(
                    get: { viewModel?.databaseToDelete },
                    set: { viewModel?.databaseToDelete = $0 }
                ),
                deleteError: Binding(
                    get: { viewModel?.deleteError },
                    set: { viewModel?.deleteError = $0 }
                ),
                deleteDatabase: { database in
                    await viewModel?.deleteDatabase(database)
                }
            ))
            .modifier(ConnectionAlertsModifier(
                connectionToDelete: Binding(
                    get: { viewModel?.connectionToDelete },
                    set: { viewModel?.connectionToDelete = $0 }
                ),
                deleteConnection: { connection in
                    await viewModel?.deleteConnection(connection)
                }
            ))
            .modifier(TableLoadingTimeoutAlertModifier(
                appState: appState,
                retryAction: {
                    Task {
                        await viewModel?.retryTableLoading()
                    }
                }
            ))
            .alert("Schema Error", isPresented: Binding(
                get: { appState.connection.schemaError != nil },
                set: { if !$0 { appState.connection.schemaError = nil } }
            )) {
                Button("OK", role: .cancel) {
                    appState.connection.schemaError = nil
                }
            } message: {
                if let error = appState.connection.schemaError {
                    Text(error)
                }
            }
    }

    private var contentWithChangeHandlers: some View {
        mainContent
            .onChange(of: appState.connection.currentConnection) { oldValue, newValue in
                viewModel?.handleConnectionChange(oldValue: oldValue, newValue: newValue)
            }
            .task {
                await viewModel?.waitForInitialLoad()
                await viewModel?.restoreLastConnection(connections: connections)
            }
            .onChange(of: appState.connection.currentConnection) { _, newConnection in
                viewModel?.updateTabForConnectionChange(newConnection)
            }
            .onChange(of: appState.connection.selectedDatabase) { _, newDatabase in
                viewModel?.updateTabForDatabaseChange(newDatabase)
            }
    }

    // MARK: - Main Content

    private var mainContent: some View {
        VStack(spacing: 0) {
            makeConnectionDatabasePicker()
            if appState.connection.selectedDatabase != nil && appState.connection.schemas.count > 1 {
                SchemaPicker(
                    schemas: appState.connection.schemas,
                    selectedSchema: appState.connection.selectedSchema,
                    onSelect: handleSelectSchema
                )
            }
            makeTablesList()
        }
    }

    private func handleSelectSchema(_ schema: String?) {
        appState.connection.selectedSchema = schema
        // Clear selected table if it's not in the new schema
        if let selected = appState.connection.selectedTable,
           let schema = schema,
           selected.schema != schema {
            appState.connection.selectedTable = nil
        }
        // Set search_path for query context (debounced to handle rapid changes)
        appState.setSchemaSearchPathDebounced(schema)
        // Save to tab state
        tabManager.updateActiveTabSchemaFilter(schema)
    }

    @ViewBuilder
    private func makeTablesList() -> some View {
        @Bindable var appState = appState

        TablesListIsolated(
            tables: appState.connection.filteredTables,
            groupedTables: appState.connection.groupedTables,
            selectedSchema: appState.connection.selectedSchema,
            selectedTable: Binding(
                get: { appState.connection.selectedTable },
                set: { appState.connection.selectedTable = $0 }
            ),
            expandedSchemas: Binding(
                get: { appState.connection.expandedSchemas },
                set: { appState.connection.expandedSchemas = $0 }
            ),
            isLoadingTables: appState.connection.isLoadingTables,
            isExecutingQuery: appState.query.isExecutingQuery,
            selectedDatabase: appState.connection.selectedDatabase,
            refreshQueryAction: { table in
                appState.requestTableQuery(for: table)
            }
        )
    }

    // MARK: - Connection/Database Picker

    @ViewBuilder
    private func makeConnectionDatabasePicker() -> some View {
        ConnectionDatabasePicker(
            showConnectionDropdown: $showConnectionDropdown,
            connections: connections,
            onSelectConnection: handleSelectConnection,
            onEditConnection: handleEditConnection,
            onDeleteConnection: handleDeleteConnection,
            onCreateConnection: handleCreateConnection,
            showDatabaseDropdown: $showDatabaseDropdown,
            onSelectDatabase: handleSelectDatabase,
            onDeleteDatabase: handleDeleteDatabase,
            onCreateDatabase: handleCreateDatabase
        )
    }

    private func handleSelectConnection(_ connection: ConnectionProfile) {
        Task {
            await viewModel?.selectConnection(connection)
        }
    }

    private func handleEditConnection(_ connection: ConnectionProfile) {
        appState.showConnectionForm(connectionToEdit: connection)
    }

    private func handleDeleteConnection(_ connection: ConnectionProfile) {
        viewModel?.connectionToDelete = connection
    }

    private func handleCreateConnection() {
        appState.showConnectionForm()
    }

    private func handleSelectDatabase(_ database: DatabaseInfo) {
        viewModel?.selectDatabase(database)
    }

    private func handleDeleteDatabase(_ database: DatabaseInfo) {
        viewModel?.databaseToDelete = database
    }

    private func handleCreateDatabase() {
        appState.showCreateDatabase()
    }

    @MainActor
    private func ensureViewModel() -> ConnectionSidebarViewModel {
        if let viewModel {
            return viewModel
        }

        let newViewModel = ConnectionSidebarViewModel(
            appState: appState,
            tabManager: tabManager,
            loadingState: loadingState,
            modelContext: modelContext,
            keychainService: keychainService
        )
        viewModel = newViewModel
        return newViewModel
    }
}

// MARK: - View Modifiers

private struct DatabaseAlertsModifier: ViewModifier {
    @Binding var showConnectionError: Bool
    @Binding var connectionError: String?
    @Binding var databaseToDelete: DatabaseInfo?
    @Binding var deleteError: String?
    let deleteDatabase: (DatabaseInfo) async -> Void

    func body(content: Content) -> some View {
        content
            .alert("Connection Failed", isPresented: $showConnectionError) {
                Button("OK", role: .cancel) {
                    connectionError = nil
                }
            } message: {
                if let error = connectionError {
                    Text(error)
                }
            }
            .confirmationDialog(
                "Delete Database?",
                isPresented: Binding(
                    get: { databaseToDelete != nil },
                    set: { if !$0 { databaseToDelete = nil } }
                ),
                presenting: databaseToDelete
            ) { database in
                Button("Delete", role: .destructive) {
                    Task {
                        await deleteDatabase(database)
                    }
                }
                Button("Cancel", role: .cancel) {
                    databaseToDelete = nil
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
}

private struct ConnectionAlertsModifier: ViewModifier {
    @Binding var connectionToDelete: ConnectionProfile?
    let deleteConnection: (ConnectionProfile) async -> Void

    func body(content: Content) -> some View {
        content
            .confirmationDialog(
                "Delete Connection?",
                isPresented: Binding(
                    get: { connectionToDelete != nil },
                    set: { if !$0 { connectionToDelete = nil } }
                ),
                presenting: connectionToDelete
            ) { connection in
                Button("Delete", role: .destructive) {
                    Task {
                        await deleteConnection(connection)
                    }
                }
                Button("Cancel", role: .cancel) {
                    connectionToDelete = nil
                }
            } message: { connection in
                Text("Are you sure you want to delete '\(connection.displayName)'? This action cannot be undone.")
            }
    }
}

private struct TableLoadingTimeoutAlertModifier: ViewModifier {
    let appState: AppState
    let retryAction: () -> Void

    func body(content: Content) -> some View {
        content
            .alert("Loading Tables Timed Out", isPresented: Binding(
                get: { appState.connection.showTableLoadingTimeoutAlert },
                set: { appState.connection.showTableLoadingTimeoutAlert = $0 }
            )) {
                Button("Try Again") {
                    appState.connection.showTableLoadingTimeoutAlert = false
                    appState.connection.tableLoadingError = nil
                    retryAction()
                }
                Button("Cancel", role: .cancel) {
                    appState.connection.showTableLoadingTimeoutAlert = false
                }
            } message: {
                Text("Loading tables took longer than \(Int(Constants.Timeout.databaseOperation)) seconds. The database may be slow or unresponsive.")
            }
    }
}
