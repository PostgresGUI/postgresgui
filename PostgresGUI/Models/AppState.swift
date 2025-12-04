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
    // Navigation
    var navigationPath: NavigationPath = NavigationPath()
    
    // Connection state
    var currentConnection: ConnectionProfile?
    var isConnected: Bool = false
    var databaseService = DatabaseService()
    
    // Current selections
    var selectedDatabase: DatabaseInfo?
    var selectedTable: TableInfo?
    
    // Data caches (populated by DatabaseService)
    var databases: [DatabaseInfo] = []
    var tables: [TableInfo] = []

    // UI state
    var isShowingConnectionForm: Bool = false
    var isShowingConnectionsList: Bool = false
    var connectionToEdit: ConnectionProfile? = nil
    var isShowingWelcomeScreen: Bool = true
    var currentPage: Int = 0
    var rowsPerPage: Int = Constants.Pagination.defaultRowsPerPage
    var isLoadingTables: Bool = false

    // Query editor state
    var queryText: String = ""
    var queryResults: [TableRow] = []
    var queryColumnNames: [String]? = nil
    var isExecutingQuery: Bool = false
    var queryError: String? = nil
    var showQueryResults: Bool = false
    var queryExecutionTime: TimeInterval? = nil
    
    // Sheet management helpers - ensure only one sheet is shown at a time
    func showConnectionForm() {
        isShowingConnectionsList = false
        isShowingConnectionForm = true
    }
    
    func showConnectionsList() {
        isShowingConnectionForm = false
        isShowingConnectionsList = true
    }
}
