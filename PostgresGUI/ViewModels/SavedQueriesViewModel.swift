//
//  SavedQueriesViewModel.swift
//  PostgresGUI
//
//  Created by ghazi on 12/21/25.
//

import Foundation
import SwiftData
import SwiftUI

/// Sort options for saved queries
enum QuerySortOption: String, CaseIterable {
    case nameAsc
    case nameDesc
    case updatedDesc
    case updatedAsc
    case createdDesc
    case createdAsc

    var icon: String {
        switch self {
        case .nameAsc, .nameDesc: return "textformat"
        case .updatedDesc, .updatedAsc: return "clock"
        case .createdDesc, .createdAsc: return "calendar"
        }
    }

    var localizedKey: LocalizedStringKey {
        switch self {
        case .nameAsc:      "query_sort.name_asc"
        case .nameDesc:     "query_sort.name_desc"
        case .updatedDesc:  "query_sort.updated_desc"
        case .updatedAsc:   "query_sort.updated_asc"
        case .createdDesc:  "query_sort.created_desc"
        case .createdAsc:   "query_sort.created_asc"
        }
    }
}

/// ViewModel for SavedQueriesSidebarSection
@Observable
@MainActor
class SavedQueriesViewModel {
    private let appState: AppState

    // UI State
    var queryToEdit: SavedQuery?
    var folderToEdit: QueryFolder?
    var queriesToDelete: [SavedQuery] = []
    var folderToDelete: QueryFolder?
    var searchText: String = ""
    var sortOption: QuerySortOption = .createdAsc
    var expandedFolders: Set<UUID> = []
    var queriesToMove: [SavedQuery] = []

    init(appState: AppState) {
        self.appState = appState
    }

    // MARK: - Computed Properties

    /// Queries not in any folder
    func unfolderedQueries(from savedQueries: [SavedQuery]) -> [SavedQuery] {
        savedQueries.filter { $0.folder == nil }
    }

    /// Check if there's any content
    func hasAnyContent(savedQueries: [SavedQuery], folders: [QueryFolder]) -> Bool {
        !savedQueries.isEmpty || !folders.isEmpty
    }

    /// Check if there's matching content after filtering
    func hasMatchingContent(savedQueries: [SavedQuery], folders: [QueryFolder]) -> Bool {
        !filteredAndSorted(unfolderedQueries(from: savedQueries)).isEmpty ||
        !filteredFolders(from: folders, savedQueries: savedQueries).isEmpty
    }

    // MARK: - Filtering and Sorting

    /// Apply filtering and sorting to queries
    func filteredAndSorted(_ queries: [SavedQuery]) -> [SavedQuery] {
        let filtered = queries.filter { query in
            guard !searchText.isEmpty else { return true }
            let search = searchText.lowercased()
            return query.name.lowercased().contains(search) ||
                   query.queryText.lowercased().contains(search)
        }

        return filtered.sorted { lhs, rhs in
            switch sortOption {
            case .nameAsc:
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            case .nameDesc:
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedDescending
            case .updatedDesc:
                return lhs.updatedAt > rhs.updatedAt
            case .updatedAsc:
                return lhs.updatedAt < rhs.updatedAt
            case .createdDesc:
                return lhs.createdAt > rhs.createdAt
            case .createdAsc:
                return lhs.createdAt < rhs.createdAt
            }
        }
    }

    /// Filter and sort folders
    func filteredFolders(from folders: [QueryFolder], savedQueries: [SavedQuery]) -> [QueryFolder] {
        if searchText.isEmpty {
            return folders.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        }

        // When searching, only show folders that have matching queries
        return folders.filter { folder in
            guard let queries = folder.queries else { return false }
            return queries.contains { query in
                let search = searchText.lowercased()
                return query.name.lowercased().contains(search) ||
                       query.queryText.lowercased().contains(search)
            }
        }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    // MARK: - Query Actions

    func createNewQuery(savedQueries: [SavedQuery], modelContext: ModelContext) {
        // Generate query name with timestamp
        let formatter = DateFormatter()
        formatter.dateFormat = "yy-MM-dd H:mm:ss"
        let queryName = "Query \(formatter.string(from: Date()))"

        // Create new saved query entry
        let newQuery = SavedQuery(
            name: queryName,
            queryText: "",
            connectionId: appState.connection.currentConnection?.id,
            databaseName: appState.connection.selectedDatabase?.name
        )
        modelContext.insert(newQuery)

        do {
            try modelContext.save()

            // Set this query as active
            if !appState.query.queryText.isEmpty {
                DebugLog.print("🗑️ [SavedQueriesViewModel] Cleared queryText due to new saved query creation: \(newQuery.name)")
            }
            appState.query.queryText = ""
            appState.query.currentSavedQueryId = newQuery.id
            appState.query.lastSavedAt = newQuery.updatedAt
            appState.query.currentQueryName = newQuery.name
            appState.query.showQueryResults = false
            appState.query.queryResults = []
            appState.query.queryColumnNames = nil
            appState.query.queryError = nil
            appState.query.queryExecutionTime = nil
            appState.query.statusMessage = nil
            appState.query.lastExecutedAt = nil

            DebugLog.print("📝 [SavedQueriesViewModel] Created new query: \(newQuery.name)")
        } catch {
            DebugLog.print("❌ [SavedQueriesViewModel] Failed to create new query: \(error)")
        }
    }

    func loadQuery(_ query: SavedQuery) {
        appState.query.queryText = query.queryText
        appState.query.currentSavedQueryId = query.id
        appState.query.lastSavedAt = query.updatedAt
        appState.query.currentQueryName = query.name

        // Restore cached results from in-memory cache if available, otherwise clear results pane
        if let cached = appState.query.getCachedResults(for: query.id) {
            appState.query.updateQueryResults(cached.rows, columnNames: cached.columnNames)
            appState.query.lastExecutedAt = cached.executedAt
            appState.query.isResultsReadOnlyDueToContextMismatch = isCachedResultsContextMismatch(for: query)
            DebugLog.print("📂 [SavedQueriesViewModel] Restored \(cached.rows.count) cached results for: \(query.name)")
        } else {
            // Keep existing results when switching to a query with no cached results
            appState.query.lastExecutedAt = nil
            appState.query.isResultsReadOnlyDueToContextMismatch = false
            DebugLog.print("📂 [SavedQueriesViewModel] No cached results; preserving existing results for: \(query.name)")
        }

        appState.query.statusMessage = nil
        DebugLog.print("📂 [SavedQueriesViewModel] Loaded query: \(query.name)")
    }

    private func isCachedResultsContextMismatch(for query: SavedQuery) -> Bool {
        let savedConnectionId = query.connectionId
        let savedDatabaseName = query.databaseName
        let currentConnectionId = appState.connection.currentConnection?.id
        let currentDatabaseName = appState.connection.selectedDatabase?.name

        let connectionMismatch = savedConnectionId != nil && savedConnectionId != currentConnectionId
        let databaseMismatch = savedDatabaseName != nil && savedDatabaseName != currentDatabaseName

        return connectionMismatch || databaseMismatch
    }

    func duplicateQuery(_ query: SavedQuery, modelContext: ModelContext) {
        let newQuery = SavedQuery(
            name: "\(query.name) (Copy)",
            queryText: query.queryText,
            connectionId: query.connectionId,
            databaseName: query.databaseName,
            folder: query.folder
        )
        modelContext.insert(newQuery)

        do {
            try modelContext.save()
            DebugLog.print("📋 [SavedQueriesViewModel] Duplicated query: \(query.name)")
        } catch {
            DebugLog.print("❌ [SavedQueriesViewModel] Failed to duplicate query: \(error)")
        }
    }

    func deleteQueries(_ queries: [SavedQuery], modelContext: ModelContext) {
        for query in queries {
            if appState.query.currentSavedQueryId == query.id {
                appState.query.currentSavedQueryId = nil
                appState.query.lastSavedAt = nil
                appState.query.currentQueryName = nil
            }
            modelContext.delete(query)
        }

        do {
            try modelContext.save()
            DebugLog.print("🗑️ [SavedQueriesViewModel] Deleted \(queries.count) queries")
        } catch {
            DebugLog.print("❌ [SavedQueriesViewModel] Failed to delete queries: \(error)")
        }

        queriesToDelete = []
    }

    func deleteFolder(_ folder: QueryFolder, deleteQueries: Bool, modelContext: ModelContext) {
        deleteFolders([folder], deleteQueries: deleteQueries, modelContext: modelContext)
        folderToDelete = nil
    }

    // MARK: - Folder Expansion

    func toggleFolderExpansion(_ folder: QueryFolder) {
        if expandedFolders.contains(folder.id) {
            expandedFolders.remove(folder.id)
            DebugLog.print("📁 [SavedQueriesViewModel] Collapsed folder: \(folder.name)")
        } else {
            expandedFolders.insert(folder.id)
            DebugLog.print("📂 [SavedQueriesViewModel] Expanded folder: \(folder.name)")
        }
    }

    func expandFolderContaining(_ query: SavedQuery) {
        if let folder = query.folder {
            expandedFolders.insert(folder.id)
        }
    }

    // MARK: - Selection Handling

    func handleSelectionChange(
        oldIDs: Set<SavedQuery.ID>,
        newIDs: Set<SavedQuery.ID>,
        savedQueries: [SavedQuery],
        folders: [QueryFolder] = []
    ) {
        // Debug: Log selection changes
        let oldNames = oldIDs.compactMap { id in savedQueries.first(where: { $0.id == id })?.name }
        let newNames = newIDs.compactMap { id in savedQueries.first(where: { $0.id == id })?.name }
        let expandedFolderNames = expandedFolders.compactMap { id in folders.first(where: { $0.id == id })?.name }
        DebugLog.print("🔵 [Selection] Query selection changed:")
        DebugLog.print("   Old: \(oldNames.isEmpty ? "none" : oldNames.joined(separator: ", ")) (\(oldIDs.count) items)")
        DebugLog.print("   New: \(newNames.isEmpty ? "none" : newNames.joined(separator: ", ")) (\(newIDs.count) items)")
        DebugLog.print("📁 [Selection] Expanded folders: \(expandedFolderNames.isEmpty ? "none" : expandedFolderNames.joined(separator: ", "))")

        // Handle deselection (clicked outside)
        if newIDs.isEmpty && !oldIDs.isEmpty {
            appState.query.currentSavedQueryId = nil
            appState.query.lastSavedAt = nil
            appState.query.currentQueryName = nil
            DebugLog.print("📂 [SavedQueriesViewModel] Deselected query (clicked outside)")
            return
        }

        // Load query when a single item is clicked (not added to existing selection)
        if newIDs.count == 1, let newID = newIDs.first,
           !oldIDs.contains(newID),
           let query = savedQueries.first(where: { $0.id == newID }) {
            loadQuery(query)
        }
    }

    func handleCurrentQueryIdChange(
        newID: UUID?,
        savedQueries: [SavedQuery]
    ) -> Set<SavedQuery.ID> {
        if let newID = newID {
            // Auto-expand folder containing this query
            if let query = savedQueries.first(where: { $0.id == newID }) {
                expandFolderContaining(query)
            }
            return [newID]
        } else {
            return []
        }
    }

    // MARK: - Move to Folder

    func prepareToMoveQueries(
        query: SavedQuery,
        selectedQueryIDs: Set<SavedQuery.ID>,
        savedQueries: [SavedQuery]
    ) {
        if selectedQueryIDs.count > 1 && selectedQueryIDs.contains(query.id) {
            queriesToMove = savedQueries.filter { selectedQueryIDs.contains($0.id) }
        } else {
            queriesToMove = [query]
        }
    }

    func prepareToDeleteSelected(
        selectedQueryIDs: Set<SavedQuery.ID>,
        savedQueries: [SavedQuery]
    ) {
        let queries = savedQueries.filter { selectedQueryIDs.contains($0.id) }
        queriesToDelete = queries
    }

    // MARK: - Folder Deletion

    var foldersToDelete: [QueryFolder] = []

    func prepareToDeleteSelectedFolders(
        selectedFolders: [QueryFolder]
    ) {
        foldersToDelete = selectedFolders
        DebugLog.print("🗑️ [SavedQueriesViewModel] Preparing to delete \(selectedFolders.count) folders: \(selectedFolders.map { $0.name }.joined(separator: ", "))")
    }

    func deleteFolders(_ folders: [QueryFolder], deleteQueries: Bool, modelContext: ModelContext) {
        for folder in folders {
            if deleteQueries {
                // Delete all queries in the folder
                for query in folder.queries ?? [] {
                    if appState.query.currentSavedQueryId == query.id {
                        appState.query.currentSavedQueryId = nil
                        appState.query.lastSavedAt = nil
                        appState.query.currentQueryName = nil
                    }
                    modelContext.delete(query)
                }
            } else {
                // Move queries out of the folder
                for query in folder.queries ?? [] {
                    query.folder = nil
                }
            }
            modelContext.delete(folder)
        }

        do {
            try modelContext.save()
            DebugLog.print("🗑️ [SavedQueriesViewModel] Deleted \(folders.count) folders")
        } catch {
            DebugLog.print("❌ [SavedQueriesViewModel] Failed to delete folders: \(error)")
        }

        foldersToDelete = []
    }
}
