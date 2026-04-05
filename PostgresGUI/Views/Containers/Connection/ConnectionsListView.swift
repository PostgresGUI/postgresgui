//
//  ConnectionsListView.swift
//  PostgresGUI
//
//  View for managing saved database connections.
//  Delegates business logic to ConnectionsListViewModel for testability
//  and separation of concerns.
//

import SwiftUI
import SwiftData

struct ConnectionsListView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(AppState.self) private var appState
    @Environment(\.keychainService) private var keychainService
    @Query private var connections: [ConnectionProfile]

    @State private var viewModel: ConnectionsListViewModel?

    private var sortedConnections: [ConnectionProfile] {
        connections.sorted { $0.displayName < $1.displayName }
    }

    /// Creates the ViewModel with proper dependencies
    private func createViewModel() -> ConnectionsListViewModel {
        let connectionService = ConnectionService(
            appState: appState,
            keychainService: keychainService
        )
        return ConnectionsListViewModel(
            appState: appState,
            connectionService: connectionService,
            keychainService: keychainService
        )
    }

    var body: some View {
        Group {
            if let vm = viewModel {
                mainContent(vm: vm)
            } else {
                Color.clear
            }
        }
        .frame(width: 600, height: 500)
        .onAppear {
            if viewModel == nil {
                viewModel = createViewModel()
            }
        }
    }

    @ViewBuilder
    private func mainContent(vm: ConnectionsListViewModel) -> some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Header
                HStack {
                    Text("Connections")
                        .font(.title2)
                        .fontWeight(.semibold)
                    Spacer()

                    Button {
                        appState.showConnectionForm()
                    } label: {
                        Label("New Connection", systemImage: "plus")
                    }
                    .buttonStyle(.borderless)
                }
                .padding()

                Divider()

                // List
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
                        ForEach(sortedConnections) { connection in
                            ConnectionRowView(
                                connection: connection,
                                isActive: appState.connection.currentConnection?.id == connection.id,
                                onConnect: {
                                    Task {
                                        await vm.connect(to: connection, modelContext: modelContext)
                                    }
                                },
                                onEdit: {
                                    appState.showConnectionForm(connectionToEdit: connection)
                                },
                                onDelete: {
                                    vm.connectionToDelete = connection
                                    vm.showDeleteConfirmation = true
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
            }
            .confirmationDialog(
                "Delete Connection?",
                isPresented: Binding(
                    get: { vm.showDeleteConfirmation },
                    set: { vm.showDeleteConfirmation = $0 }
                ),
                presenting: vm.connectionToDelete
            ) { connection in
                Button(role: .destructive) {
                    Task {
                        await vm.deleteConnection(connection, connections: connections, modelContext: modelContext)
                    }
                } label: {
                    Text("Delete")
                }
                Button("Cancel", role: .cancel) {
                    vm.connectionToDelete = nil
                }
            } message: { connection in
                Text("Are you sure you want to delete '\(connection.displayName)'? This action cannot be undone.")
            }
            .alert("Error Deleting Connection", isPresented: Binding(
                get: { vm.deleteError != nil },
                set: { if !$0 { vm.deleteError = nil } }
            )) {
                Button("OK", role: .cancel) {
                    vm.deleteError = nil
                }
            } message: {
                if let error = vm.deleteError {
                    Text(error)
                }
            }
            .alert("Connection Failed", isPresented: Binding(
                get: { vm.showConnectionError },
                set: { vm.showConnectionError = $0 }
            )) {
                Button("OK", role: .cancel) {
                    vm.connectionError = nil
                }
            } message: {
                if let error = vm.connectionError {
                    Text(error)
                }
            }
        }
    }
}

// MARK: - Connection Row

private struct ConnectionRowView: View {
    let connection: ConnectionProfile
    let isActive: Bool
    let onConnect: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    @State private var isButtonHovered = false

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(connection.displayName)
                        .font(.headline)
                    if connection.isFavorite {
                        Image(systemName: "star.fill")
                            .foregroundColor(.yellow)
                            .font(.caption)
                    }
                }

                HStack(spacing: 12) {
                    Label(connection.rootDomain, systemImage: "server.rack")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Label(formatPort(connection.port), systemImage: "network")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            Button {
                onConnect()
            } label: {
                if isActive {
                    Label("Connected", systemImage: "checkmark")
                } else {
                    Label("Connect", systemImage: "powerplug")
                }
            }
            .platformGlassProminentButtonStyle()
            .tint(isActive ? .green : nil)

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
                    .padding(.vertical, 8)
                    .background(isButtonHovered ? Color.secondary.opacity(0.2) : Color.clear)
                    .clipShape(RoundedRectangle(cornerRadius: 100))
            }
            .buttonStyle(.plain)
            .onHover { hovering in
                isButtonHovered = hovering
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
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
    }

    private func formatPort(_ port: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .none
        formatter.usesGroupingSeparator = false
        return formatter.string(from: NSNumber(value: port)) ?? String(port)
    }
}
