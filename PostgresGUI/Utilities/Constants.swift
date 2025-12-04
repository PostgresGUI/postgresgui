//
//  Constants.swift
//  PostgresGUI
//
//  Created by ghazi on 11/28/25.
//

import SwiftUI

/// Design system constants following Liquid Glass patterns
enum Constants {
    // Spacing
    enum Spacing {
        static let small: CGFloat = 8
        static let medium: CGFloat = 16
        static let large: CGFloat = 24
        static let extraLarge: CGFloat = 32
    }
    
    // Column widths
    enum ColumnWidth {
        static let sidebarMin: CGFloat = 200
        static let sidebarIdeal: CGFloat = 250
        static let sidebarMax: CGFloat = 300
        
        static let tablesMin: CGFloat = 250
        static let tablesIdeal: CGFloat = 300
        static let tablesMax: CGFloat = 400
        
        static let tableColumnMin: CGFloat = 120
    }
    
    // Pagination
    enum Pagination {
        static let defaultRowsPerPage: Int = 100
        static let minRowsPerPage: Int = 10
        static let maxRowsPerPage: Int = 1000
    }
    
    // PostgreSQL defaults
    enum PostgreSQL {
        static let defaultPort: Int = 5432
        static let defaultDatabase: String = "postgres"
        static let defaultUsername: String = "postgres"
    }
    
    // UserDefaults keys
    enum UserDefaultsKeys {
        static let lastConnectionId = "lastConnectionId"
        static let lastDatabaseName = "lastDatabaseName"
    }
}
