//
//  AppState.swift
//  PostgresGUI
//
//  Created by ghazi on 11/28/25.
//

import SwiftUI

@Observable
@MainActor
class AppState {
    // MARK: - Composed State Managers

    let navigation: NavigationState
    let connection: ConnectionState
    let query: QueryState

    // MARK: - Services

    private let tableMetadataService: TableMetadataServiceProtocol

    // MARK: - Tab Manager (for caching query results)

    weak var tabManager: TabManager?

    // MARK: - Debounce State

    private var schemaSearchPathTask: Task<Void, Never>?
    private var tableQueryTask: Task<Void, Never>?
    private var tableMetadataTask: Task<Void, Never>?
    private var tableQueryRequestId: Int = 0
    private let tableQueryDispatchDebounceNanoseconds: UInt64 = 120_000_000

    // MARK: - Initialization

    init(
        navigation: NavigationState? = nil,
        connection: ConnectionState? = nil,
        query: QueryState? = nil,
        tableMetadataService: TableMetadataServiceProtocol? = nil
    ) {
        self.navigation = navigation ?? NavigationState()
        self.connection = connection ?? ConnectionState()
        self.query = query ?? QueryState()
        self.tableMetadataService = tableMetadataService ?? TableMetadataService()
    }

    // MARK: - Convenience Methods

    func showConnectionForm() {
        navigation.showConnectionForm()
    }

    func showConnectionForm(connectionToEdit: ConnectionProfile?) {
        navigation.showConnectionForm(connectionToEdit: connectionToEdit)
    }

    func showCreateDatabase() {
        navigation.showCreateDatabase()
    }

    func showKeyboardShortcuts() {
        navigation.showKeyboardShortcuts()
    }

    func showHelp() {
        navigation.showHelp()
    }

    // MARK: - Query Execution

    /// Request a table query and cancel any in-flight table query task.
    @MainActor
    func requestTableQuery(for table: TableInfo, limit: Int? = nil) {
        let shouldInterruptSupersededInFlightLoad = hasInFlightTableBrowseLoadToSupersede()
        tableQueryTask?.cancel()
        tableMetadataTask?.cancel()
        query.cancelCurrentQuerySilentlyForSupersession()
        tableQueryRequestId += 1
        let requestId = tableQueryRequestId
        startTableQueryLoading(for: table)
        connection.selectedTable = table

        tableQueryTask = Task { @MainActor in
            if shouldInterruptSupersededInFlightLoad {
                await connection.databaseService.interruptInFlightTableBrowseLoadForSupersession()
            }
            guard isTableQueryRequestCurrent(requestId: requestId) else { return }
            try? await Task.sleep(nanoseconds: tableQueryDispatchDebounceNanoseconds)
            guard isTableQueryRequestCurrent(requestId: requestId) else { return }
            await executeTableQueryInternal(
                for: table,
                limit: limit,
                requestId: requestId,
                applyTableBrowseCompaction: true,
                targetPage: nil
            )
        }
    }

    /// Request a paginated table query for a specific target page.
    /// Uses cached pages when available and latest-wins cancellation when not.
    @MainActor
    func requestPaginatedTableQuery(for table: TableInfo, targetPage: Int) {
        guard targetPage >= 0 else { return }

        let shouldInterruptSupersededInFlightLoad = hasInFlightTableBrowseLoadToSupersede()
        tableQueryTask?.cancel()
        tableMetadataTask?.cancel()
        query.cancelCurrentQuerySilentlyForSupersession()
        tableQueryRequestId += 1
        let requestId = tableQueryRequestId
        connection.selectedTable = table

        let paginationContext = makeTableBrowsePageCacheContext(for: table)
        if let cachedPage = query.cachedTableBrowsePage(for: targetPage, context: paginationContext) {
            if shouldInterruptSupersededInFlightLoad {
                tableQueryTask = Task { @MainActor in
                    guard isTableQueryRequestCurrent(requestId: requestId) else { return }
                    await connection.databaseService.interruptInFlightTableBrowseLoadForSupersession()
                }
            } else {
                tableQueryTask = nil
            }
            applyCachedPaginatedTableBrowsePage(
                cachedPage,
                table: table,
                targetPage: targetPage
            )
            return
        }

        startTableQueryLoading(for: table)
        tableQueryTask = Task { @MainActor in
            if shouldInterruptSupersededInFlightLoad {
                await connection.databaseService.interruptInFlightTableBrowseLoadForSupersession()
            }
            guard isTableQueryRequestCurrent(requestId: requestId) else { return }
            await executeTableQueryInternal(
                for: table,
                limit: nil,
                requestId: requestId,
                applyTableBrowseCompaction: true,
                targetPage: targetPage
            )
        }
    }

    /// Centralized query execution to prevent race conditions when rapidly switching tables
    /// - Parameters:
    ///   - table: The table to query
    ///   - limit: Optional row limit. If nil, uses pagination (rowsPerPage). If specified, uses that exact limit with no pagination.
    @MainActor
    func executeTableQuery(for table: TableInfo, limit: Int? = nil) async {
        tableQueryTask?.cancel()
        tableQueryTask = nil
        tableMetadataTask?.cancel()
        query.cancelCurrentQuerySilentlyForSupersession()
        tableQueryRequestId += 1
        let requestId = tableQueryRequestId
        startTableQueryLoading(for: table)
        await executeTableQueryInternal(
            for: table,
            limit: limit,
            requestId: requestId,
            applyTableBrowseCompaction: limit == nil,
            targetPage: nil
        )
    }

    @MainActor
    private func executeTableQueryInternal(
        for table: TableInfo,
        limit: Int?,
        requestId: Int,
        applyTableBrowseCompaction: Bool,
        targetPage: Int?
    ) async {
        defer {
            finishTableQueryLoadingIfCurrent(requestId: requestId)
        }

        guard isTableQueryRequestCurrent(requestId: requestId) else {
            return
        }

        // Capture context to verify nothing changed after async operations
        // This prevents stale query results when user switches table, database, or connection
        let tableId = table.id
        let databaseId = connection.selectedDatabase?.id
        let connectionId = connection.currentConnection?.id

        let queryService = QueryService(
            databaseService: connection.databaseService,
            queryState: query
        )

        guard isTableQueryRequestCurrent(requestId: requestId) else {
            return
        }

        // Set loading state
        query.startQueryExecution()

        // Determine the limit and pagination mode
        let effectiveLimit: Int
        let isPaginated: Bool
        if let customLimit = limit {
            // Custom limit specified - no pagination
            effectiveLimit = customLimit
            isPaginated = false
        } else {
            // Use pagination - fetch +1 to detect if more pages exist
            effectiveLimit = query.rowsPerPage + 1
            isPaginated = true
        }
        let requestedPage = isPaginated ? max(targetPage ?? query.currentPage, 0) : 0

        // Determine preferred column order (table order) from cache only.
        // Avoiding an extra metadata round-trip here keeps rapid table switching responsive.
        let preferredColumnOrder = cachedPreferredColumnOrder(for: table)

        guard isTableQueryRequestCurrent(requestId: requestId) else {
            return
        }

        // Execute query
        let result = await queryService.executeTableQuery(
            for: table,
            limit: effectiveLimit,
            offset: isPaginated ? calculateOffset(page: requestedPage, pageSize: query.rowsPerPage) : 0,
            preferredColumnOrder: preferredColumnOrder
        )

        guard isTableQueryRequestCurrent(requestId: requestId) else {
            DebugLog.print("⚠️ [AppState] Query for \(table.name) superseded/cancelled, skipping state update")
            return
        }

        guard requestId == tableQueryRequestId else {
            DebugLog.print("⚠️ [AppState] Query for \(table.name) superseded (newer request), skipping state update")
            return
        }

        // Only update state if context hasn't changed (table, database, AND connection)
        // Prevents stale results when same table name exists in different databases
        guard connection.isQueryContextValid(
            tableId: tableId,
            databaseId: databaseId,
            connectionId: connectionId
        ) else {
            DebugLog.print("⚠️ [AppState] Query for \(table.name) superseded (context changed), skipping state update")
            query.isExecutingQuery = false
            return
        }

        // Update state based on result
        if result.isSuccess {
            var resultRows = result.rows
            if applyTableBrowseCompaction {
                resultRows = await TableBrowseResultCompactor.compactRowsOffMain(
                    rows: result.rows,
                    maxCellCharacters: Constants.tableBrowseMaxCellCharacters,
                    truncationSuffix: Constants.tableBrowseTruncationSuffix
                )

                guard isTableQueryRequestCurrent(requestId: requestId) else {
                    return
                }

                guard connection.isQueryContextValid(
                    tableId: tableId,
                    databaseId: databaseId,
                    connectionId: connectionId
                ) else {
                    DebugLog.print("⚠️ [AppState] Query for \(table.name) superseded after compaction, skipping state update")
                    query.isExecutingQuery = false
                    return
                }
            }

            if isPaginated {
                // Check if we got more rows than requested (indicates next page exists)
                let hasNextPage = hasMorePages(fetchedRowCount: result.rows.count, pageSize: query.rowsPerPage)
                // Trim to actual page size
                let trimmedRows = hasNextPage ? Array(resultRows.prefix(query.rowsPerPage)) : resultRows
                query.hasNextPage = hasNextPage
                query.currentPage = requestedPage
                let trimmedResult = QueryResult.success(
                    rows: trimmedRows,
                    columnNames: result.columnNames,
                    executionTime: result.executionTime
                )
                query.finishQueryExecution(with: trimmedResult)

                query.cacheTableBrowsePage(
                    page: requestedPage,
                    rows: trimmedRows,
                    columnNames: result.columnNames,
                    hasNextPage: hasNextPage,
                    context: makeTableBrowsePageCacheContext(
                        tableId: tableId,
                        databaseId: databaseId,
                        connectionId: connectionId
                    ),
                    maxCachedPages: Constants.tableBrowseMaxCachedPages
                )
            } else {
                // Non-paginated: use result as-is
                query.hasNextPage = false
                query.currentPage = 0
                let compactedResult = QueryResult.success(
                    rows: resultRows,
                    columnNames: result.columnNames,
                    executionTime: result.executionTime
                )
                query.finishQueryExecution(with: compactedResult)
            }
            query.isResultsReadOnlyDueToContextMismatch = false

            // Cache results to active tab for restoration on tab switch
            query.cachedResultsTableId = table.id
            tabManager?.updateActiveTabResults(
                results: query.queryResults,
                columnNames: query.queryColumnNames
            )

            // Fetch table metadata (primary keys, column info) only when missing.
            if shouldFetchTableMetadata(for: table) {
                startTableMetadataFetch(
                    for: table,
                    tableId: tableId,
                    databaseId: databaseId,
                    connectionId: connectionId
                )
            }
        } else {
            query.finishQueryExecution(with: result)
        }
    }

    @MainActor
    private func startTableQueryLoading(for table: TableInfo) {
        query.isExecutingTableQuery = true
        query.executingTableQueryTableId = table.id
    }

    @MainActor
    private func finishTableQueryLoadingIfCurrent(requestId: Int) {
        guard requestId == tableQueryRequestId else { return }
        query.isExecutingTableQuery = false
        query.executingTableQueryTableId = nil
    }

    @MainActor
    private func isTableQueryRequestCurrent(requestId: Int) -> Bool {
        requestId == tableQueryRequestId && !Task.isCancelled
    }

    @MainActor
    private func hasInFlightTableBrowseLoadToSupersede() -> Bool {
        query.isExecutingTableQuery && (query.isExecutingQuery || query.currentQueryTask != nil)
    }

    @MainActor
    private func applyCachedPaginatedTableBrowsePage(
        _ page: TableBrowsePageSnapshot,
        table: TableInfo,
        targetPage: Int
    ) {
        query.queryError = nil
        query.showTimeoutAlert = false
        query.queryExecutionTime = nil
        query.isExecutingQuery = false
        query.isExecutingTableQuery = false
        query.executingTableQueryTableId = nil
        query.hasNextPage = page.hasNextPage
        query.currentPage = targetPage
        query.updateQueryResults(page.rows, columnNames: page.columnNames)
        query.isResultsReadOnlyDueToContextMismatch = false
        query.cachedResultsTableId = table.id

        tabManager?.updateActiveTabResults(
            results: query.queryResults,
            columnNames: query.queryColumnNames
        )
    }

    @MainActor
    private func makeTableBrowsePageCacheContext(for table: TableInfo) -> TableBrowsePageCacheContext {
        makeTableBrowsePageCacheContext(
            tableId: table.id,
            databaseId: connection.selectedDatabase?.id,
            connectionId: connection.currentConnection?.id
        )
    }

    @MainActor
    private func makeTableBrowsePageCacheContext(
        tableId: String,
        databaseId: String?,
        connectionId: UUID?
    ) -> TableBrowsePageCacheContext {
        TableBrowsePageCacheContext(
            connectionId: connectionId,
            databaseId: databaseId,
            tableId: tableId,
            rowsPerPage: query.rowsPerPage
        )
    }

    @MainActor
    private func shouldFetchTableMetadata(for table: TableInfo) -> Bool {
        guard let cached = connection.tableMetadataCache[table.id] else {
            return true
        }
        return cached.primaryKeys == nil || cached.columns == nil
    }

    @MainActor
    private func cachedPreferredColumnOrder(for table: TableInfo) -> [String]? {
        guard let cachedColumns = connection.getColumnInfo(for: table),
              !cachedColumns.isEmpty else {
            return nil
        }
        return cachedColumns.map { $0.name }
    }

    @MainActor
    private func startTableMetadataFetch(
        for table: TableInfo,
        tableId: String,
        databaseId: String?,
        connectionId: UUID?
    ) {
        tableMetadataTask?.cancel()
        tableMetadataTask = Task { @MainActor in
            guard !Task.isCancelled else { return }
            guard connection.isQueryContextValid(
                tableId: tableId,
                databaseId: databaseId,
                connectionId: connectionId
            ) else {
                return
            }
            await fetchTableMetadata(for: table)
        }
    }

    /// Fetch and cache table metadata (primary keys, column info)
    @MainActor
    private func fetchTableMetadata(for table: TableInfo) async {
        _ = await tableMetadataService.fetchAndCacheMetadata(
            for: table,
            connectionState: connection,
            databaseService: connection.databaseService
        )
    }

    /// Resolve column order for a table using cached or freshly fetched metadata
    @MainActor
    func preferredColumnOrder(for table: TableInfo) async -> [String]? {
        if let cachedColumns = connection.getColumnInfo(for: table),
           !cachedColumns.isEmpty {
            return cachedColumns.map { $0.name }
        }

        // Capture context so stale async completions do not poison metadata cache
        // after the user changes connection/database.
        let expectedConnectionId = connection.currentConnection?.id
        let expectedDatabaseId = connection.selectedDatabase?.id

        do {
            let columns = try await connection.databaseService.fetchColumnInfo(
                schema: table.schema,
                table: table.name
            )

            guard connection.currentConnection?.id == expectedConnectionId,
                  connection.selectedDatabase?.id == expectedDatabaseId else {
                DebugLog.print("⚠️ [AppState] Skipping preferred column order cache for \(table.id) due to context change")
                return nil
            }

            let existingCache = connection.tableMetadataCache[table.id]
            connection.tableMetadataCache[table.id] = (
                primaryKeys: existingCache?.primaryKeys,
                columns: columns
            )

            return columns.map { $0.name }
        } catch {
            DebugLog.print("⚠️ [AppState] Failed to fetch column order for \(table.name): \(error)")
            return nil
        }
    }

    /// Resolve column order based on a table name and current selection
    func preferredColumnOrder(forTableName tableName: String?) async -> [String]? {
        guard let tableName else {
            DebugLog.print("🧭 [AppState] preferredColumnOrder: missing tableName")
            return nil
        }

        if let selectedTable = connection.selectedTable,
           selectedTable.name.caseInsensitiveCompare(tableName) == .orderedSame {
            DebugLog.print("🧭 [AppState] preferredColumnOrder: using selected table \(selectedTable.name)")
            return await preferredColumnOrder(for: selectedTable)
        }

        let matchesByName = connection.tables.filter {
            $0.name.caseInsensitiveCompare(tableName) == .orderedSame
        }

        if matchesByName.isEmpty {
            DebugLog.print("🧭 [AppState] preferredColumnOrder: no table match for \(tableName)")
            return nil
        }

        let scopedMatches: [TableInfo]
        if let selectedSchema = connection.selectedSchema {
            let schemaScopedMatches = matchesByName.filter { $0.schema == selectedSchema }
            scopedMatches = schemaScopedMatches.isEmpty ? matchesByName : schemaScopedMatches
        } else {
            scopedMatches = matchesByName
        }

        let resolvedTable: TableInfo?
        if scopedMatches.count == 1 {
            resolvedTable = scopedMatches[0]
        } else if let publicMatch = scopedMatches.first(where: { $0.schema == "public" }) {
            resolvedTable = publicMatch
        } else {
            resolvedTable = scopedMatches.first
        }

        guard let table = resolvedTable else {
            DebugLog.print("🧭 [AppState] preferredColumnOrder: could not resolve table for \(tableName)")
            return nil
        }

        DebugLog.print("🧭 [AppState] preferredColumnOrder: using resolved table \(table.schema).\(table.name)")
        return await preferredColumnOrder(for: table)
    }

    // MARK: - Schema Context

    /// Set the search_path with debounce to prevent race conditions during rapid tab switching
    func setSchemaSearchPathDebounced(_ schema: String?) {
        schemaSearchPathTask?.cancel()
        schemaSearchPathTask = Task {
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled else { return }
            await setSchemaSearchPath(schema)
        }
    }

    /// Set the search_path for query context when a schema is selected
    /// Use `setSchemaSearchPathDebounced` for tab switches and user-initiated schema changes
    @MainActor
    func setSchemaSearchPath(_ schema: String?) async {
        guard connection.isConnected else { return }

        // Build search_path: selected schema first, then public as fallback
        let searchPath: String
        if let schema = schema {
            searchPath = schema == "public" ? "public" : "\"\(schema)\", public"
        } else {
            // "All Schemas" selected - reset to default
            searchPath = "public"
        }

        let sql = "SET search_path TO \(searchPath)"
        DebugLog.print("🔧 Setting schema: \(schema ?? "nil") → SQL: \(sql)")

        do {
            _ = try await connection.databaseService.executeQuery(sql)
            connection.schemaError = nil
        } catch {
            DebugLog.print("❌ Failed to set search_path: \(error)")
            connection.schemaError = "Failed to set schema context: \(error.localizedDescription)"
        }
    }

    // MARK: - Cleanup

    /// Clean up resources when window is closing
    func cleanupOnWindowClose() async {
        guard connection.isConnected else { return }

        DebugLog.print("🧹 Window closing, cleaning up...")

        // Cancel any pending queries
        query.cleanup()
        tableQueryTask?.cancel()
        tableMetadataTask?.cancel()

        // Disconnect and reset connection state
        await connection.cleanupOnWindowClose()

        DebugLog.print("✅ Cleanup completed")
    }
}
