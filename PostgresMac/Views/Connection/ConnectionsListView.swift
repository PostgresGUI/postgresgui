//
//  ConnectionsListView.swift
//  PostgresMac
//
//  Created by ghazi on 11/28/25.
//

import SwiftUI
import SwiftData

struct ConnectionsListView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(AppState.self) private var appState
    @Query(sort: \ConnectionProfile.name) private var connections: [ConnectionProfile]
    
    @State private var connectionToDelete: ConnectionProfile?
    @State private var showDeleteConfirmation = false
    @State private var deleteError: String?
    @State private var connectionError: String?
    @State private var showConnectionError = false
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Header with title
                HStack {
                    Text("Connections")
                        .font(.title2)
                        .fontWeight(.semibold)
                    Spacer()
                }
                .padding()
                
                Divider()
                
                // Connections List
                if connections.isEmpty {
                    Spacer()
                    ContentUnavailableView {
                        Label("No Connections", systemImage: "server.rack")
                    } description: {
                        Text("Create your first connection to get started")
                    }
                    Spacer()
                } else {
                    List {
                        ForEach(connections) { connection in
                            ConnectionRowView(
                                connection: connection,
                                isActive: appState.currentConnection?.id == connection.id,
                                onConnect: {
                                    Task {
                                        await connect(to: connection)
                                    }
                                },
                                onEdit: {
                                    appState.connectionToEdit = connection
                                    appState.isShowingConnectionForm = true
                                },
                                onDelete: {
                                    connectionToDelete = connection
                                    showDeleteConfirmation = true
                                }
                            )
                        }
                    }
                    .listStyle(.inset)
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Text("Done")
                    }
                }
                
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        appState.connectionToEdit = nil
                        appState.isShowingConnectionForm = true
                    } label: {
                        Label("New Connection", systemImage: "plus")
                    }
                }
            }
            .confirmationDialog(
                "Delete Connection?",
                isPresented: $showDeleteConfirmation,
                presenting: connectionToDelete
            ) { connection in
                Button(role: .destructive) {
                    Task {
                        await deleteConnection(connection)
                    }
                } label: {
                    Text("Delete")
                }
                Button("Cancel", role: .cancel) {
                    connectionToDelete = nil
                }
            } message: { connection in
                Text("Are you sure you want to delete '\(connection.name)'? This action cannot be undone.")
            }
            .alert("Error Deleting Connection", isPresented: Binding(
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
        .frame(width: 600, height: 500)
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
            appState.currentConnection = connection
            appState.isConnected = true
            appState.isShowingWelcomeScreen = false
            
            // Load databases
            await loadDatabases()
            
        } catch {
            print("Failed to connect: \(error)")
            connectionError = error.localizedDescription
            showConnectionError = true
        }
    }
    
    private func loadDatabases() async {
        do {
            appState.databases = try await appState.databaseService.fetchDatabases()
        } catch {
            print("Failed to load databases: \(error)")
        }
    }
    
    private func deleteConnection(_ connection: ConnectionProfile) async {
        print("🗑️  [ConnectionsListView] Deleting connection: \(connection.name)")
        
        do {
            // Check if this is the currently active connection
            let isActiveConnection = appState.currentConnection?.id == connection.id
            
            // Delete password from Keychain
            try KeychainService.deletePassword(for: connection.id)
            
            // Disconnect if this is the active connection
            if isActiveConnection {
                await appState.databaseService.disconnect()
                appState.isConnected = false
                appState.currentConnection = nil
                appState.selectedDatabase = nil
                appState.tables = []
                appState.databases = []
            }
            
            // Delete from SwiftData
            modelContext.delete(connection)
            try modelContext.save()
            
            print("✅ [ConnectionsListView] Connection deleted successfully")
            connectionToDelete = nil
            
        } catch {
            print("❌ [ConnectionsListView] Error deleting connection: \(error)")
            if let keychainError = error as? KeychainError {
                deleteError = keychainError.errorDescription ?? "Failed to delete connection."
            } else {
                deleteError = error.localizedDescription
            }
        }
    }
}

private struct ConnectionRowView: View {
    let connection: ConnectionProfile
    let isActive: Bool
    let onConnect: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void
    
    @State private var isHovered = false
    @State private var isButtonHovered = false
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(connection.name)
                        .font(.headline)
                    if connection.isFavorite {
                        Image(systemName: "star.fill")
                            .foregroundColor(.yellow)
                            .font(.caption)
                    }
                    if isActive {
                        Badge(text: "Connected", color: .green)
                    }
                }
                
                HStack(spacing: 12) {
                    Label(connection.host, systemImage: "server.rack")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Label("\(connection.port)", systemImage: "network")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Label(connection.database, systemImage: "externaldrive")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            if isHovered {
                Button {
                    onConnect()
                } label: {
                    Label("Connect", systemImage: "powerplug")
                }
                .buttonStyle(.bordered)
                
                Menu {
                    Button {
                        onEdit()
                    } label: {
                        Label("Edit...", systemImage: "pencil")
                    }
                    
                    Button(role: .destructive) {
                        onDelete()
                    } label: {
                        Label("Delete...", systemImage: "trash")
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
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(isHovered ? Color.secondary.opacity(0.1) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .contentShape(Rectangle())
        .contextMenu {
            Button {
                onConnect()
            } label: {
                Label("Connect", systemImage: "powerplug")
            }
            
            Button {
                onEdit()
            } label: {
                Label("Edit...", systemImage: "pencil")
            }
            
            Button(role: .destructive) {
                onDelete()
            } label: {
                Label("Delete...", systemImage: "trash")
            }
        }
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

