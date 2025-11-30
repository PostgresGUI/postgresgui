//
//  TableRowView.swift
//  PostgresMac
//
//  Created by ghazi on 11/28/25.
//

import SwiftUI
import AppKit

struct TableRowView: View {
    let table: TableInfo
    @Environment(AppState.self) private var appState
    @State private var showDeleteConfirmation = false
    @State private var deleteError: String?

    var body: some View {
        NavigationLink(value: table.id) {
            HStack(spacing: 8) {
                Image(systemName: "tablecells")
                    .foregroundColor(.secondary)

                Text(table.name)
                    .font(.headline)
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 6)
        }
        .contextMenu {
            Button(role: .destructive) {
                showDeleteConfirmation = true
            } label: {
                Label("Delete", systemImage: "trash")
            }
            
            Button {
                Task {
                    await showSchema()
                }
            } label: {
                Label("View Schema", systemImage: "info.circle")
            }
            
            Button {
                copyTableName()
            } label: {
                Label("Copy Name", systemImage: "doc.on.doc")
            }
        }
        .confirmationDialog(
            "Delete Table?",
            isPresented: $showDeleteConfirmation,
            presenting: table
        ) { table in
            Button(role: .destructive) {
                Task {
                    await deleteTable(table)
                }
            } label: {
                Text("Delete")
            }
            Button("Cancel", role: .cancel) {
                showDeleteConfirmation = false
            }
        } message: { table in
            Text("Are you sure you want to delete '\(table.schema).\(table.name)'? This action cannot be undone.")
        }
        .alert("Error Deleting Table", isPresented: Binding(
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
    
    private func deleteTable(_ table: TableInfo) async {
        print("🗑️  [TableRowView] Deleting table: \(table.schema).\(table.name)")
        
        do {
            guard appState.databaseService.isConnected else {
                deleteError = "Not connected to database"
                return
            }
            
            try await appState.databaseService.deleteTable(schema: table.schema, table: table.name)
            
            // Remove from tables list
            appState.tables.removeAll { $0.id == table.id }
            
            // Clear selection if this was the selected table
            if appState.selectedTable?.id == table.id {
                appState.selectedTable = nil
                appState.showQueryResults = false
                appState.queryText = ""
                appState.queryResults = []
            }
            
            print("✅ [TableRowView] Table deleted successfully")
        } catch {
            print("❌ [TableRowView] Error deleting table: \(error)")
            if let connectionError = error as? ConnectionError {
                deleteError = connectionError.errorDescription ?? "Failed to delete table."
            } else {
                deleteError = error.localizedDescription
            }
        }
    }
    
    private func showSchema() async {
        print("📋 [TableRowView] Showing schema for: \(table.schema).\(table.name)")
        
        do {
            // Fetch columns for the table
            appState.columns = try await appState.databaseService.fetchColumns(schema: table.schema, table: table.name)
            appState.schemaTable = table
            appState.showTableSchema = true
            print("✅ [TableRowView] Schema fetched successfully")
        } catch {
            print("❌ [TableRowView] Error fetching schema: \(error)")
            // Could show an error alert here if needed
        }
    }
    
    private func copyTableName() {
        let tableName = "\(table.schema).\(table.name)"
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(tableName, forType: .string)
        print("📋 [TableRowView] Copied table name to clipboard: \(tableName)")
    }
}
