//
//  QueryResultsView.swift
//  PostgresGUI
//
//  Created by Claude on 11/29/25.
//

import SwiftUI

// Custom comparator for sorting table rows by column value
struct TableRowComparator: SortComparator, Hashable {
    let columnName: String
    var order: SortOrder = .forward

    func compare(_ lhs: TableRow, _ rhs: TableRow) -> ComparisonResult {
        let value1 = lhs.values[columnName] ?? nil
        let value2 = rhs.values[columnName] ?? nil

        let result = compareValues(value1, value2)

        // Respect the order property
        if order == .reverse {
            switch result {
            case .orderedAscending: return .orderedDescending
            case .orderedDescending: return .orderedAscending
            case .orderedSame: return .orderedSame
            }
        }

        return result
    }

    private func compareValues(_ lhs: String?, _ rhs: String?) -> ComparisonResult {
        // Handle NULL values - NULL sorts last
        switch (lhs, rhs) {
        case (nil, nil):
            return .orderedSame
        case (nil, _):
            return .orderedDescending
        case (_, nil):
            return .orderedAscending
        case let (v1?, v2?):
            // Try to compare as numbers first
            if let num1 = Double(v1), let num2 = Double(v2) {
                return num1 < num2 ? .orderedAscending : (num1 > num2 ? .orderedDescending : .orderedSame)
            }

            // Try to compare as dates/timestamps
            if isTimestamp(v1) && isTimestamp(v2),
               let date1 = parseDate(v1),
               let date2 = parseDate(v2) {
                return date1 < date2 ? .orderedAscending : (date1 > date2 ? .orderedDescending : .orderedSame)
            }

            // Fall back to string comparison
            return v1.localizedStandardCompare(v2)
        }
    }

    private func isTimestamp(_ value: String) -> Bool {
        let timestampPatterns = [
            "^\\d{4}-\\d{2}-\\d{2}T\\d{2}:\\d{2}:\\d{2}",
            "^\\d{4}-\\d{2}-\\d{2} \\d{2}:\\d{2}:\\d{2}",
            "^\\d{4}-\\d{2}-\\d{2}$"
        ]
        return timestampPatterns.contains { value.range(of: $0, options: .regularExpression) != nil }
    }

    private func parseDate(_ value: String) -> Date? {
        let iso8601 = ISO8601DateFormatter()
        iso8601.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = iso8601.date(from: value) { return date }

        let formatters = [
            "yyyy-MM-dd HH:mm:ss.SSSSSS",
            "yyyy-MM-dd HH:mm:ss",
            "yyyy-MM-dd"
        ].map { format -> DateFormatter in
            let f = DateFormatter()
            f.dateFormat = format
            return f
        }

        for formatter in formatters {
            if let date = formatter.date(from: value) { return date }
        }
        return nil
    }
}

struct QueryResultsView: View {
    @Environment(AppState.self) private var appState
    @State private var selection = Set<TableRow.ID>()
    @State private var sortOrder: [TableRowComparator] = []

    var body: some View {
        VStack(spacing: 0) {
            // Results or error display
            if let error = appState.queryError {
                ContentUnavailableView {
                    Label {
                        Text("Query Failed")
                            .font(.title3)
                    } icon: {
                        Image(systemName: "exclamationmark.triangle")
                            .foregroundColor(.red)
                    }
                } description: {
                    Text(error)
                        .foregroundColor(.secondary)
                        .padding()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if appState.queryResults.isEmpty && !appState.isExecutingQuery {
                // Show empty table with headers if column names are available
                if let columnNames = getColumnNames(), !columnNames.isEmpty {
                    // Empty table with overlay empty state message
                    emptyTableWithHeaders(columnNames: columnNames)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .overlay(alignment: .center) {
                            ContentUnavailableView(
                                "Empty Table",
                                systemImage: "tablecells",
                                description: Text("Query returned no rows")
                            )
                        }
                } else {
                    ContentUnavailableView(
                        "Empty Table",
                        systemImage: "tablecells",
                        description: Text("Query returned no rows")
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else {
                // Display results using SwiftUI Table
                resultsTable
            }
        }
    }

    @ViewBuilder
    private var resultsTable: some View {
        if let columnNames = getColumnNames() {
            Table(sortedResults, selection: $selection, sortOrder: $sortOrder) {
                TableColumnForEach(columnNames, id: \.self) { columnName in
                    TableColumn(columnName, sortUsing: TableRowComparator(columnName: columnName)) { row in
                        Text(formatValue(row.values[columnName] ?? nil))
                            .font(.system(.body, design: .monospaced))
                            .textSelection(.enabled)
                    }
                    .width(min: Constants.ColumnWidth.tableColumnMin)
                }
            }
        }
    }

    @ViewBuilder
    private func emptyTableWithHeaders(columnNames: [String]) -> some View {
        // Create a Table with just headers, no rows
        Table([] as [TableRow], selection: .constant(Set<TableRow.ID>())) {
            TableColumnForEach(columnNames, id: \.self) { columnName in
                TableColumn(columnName) { row in
                    Text(formatValue(row.values[columnName] ?? nil))
                        .font(.system(.body, design: .monospaced))
                }
                .width(min: Constants.ColumnWidth.tableColumnMin)
            }
        }
    }

    private var sortedResults: [TableRow] {
        appState.queryResults.sorted(using: sortOrder)
    }

    private func getColumnNames() -> [String]? {
        // First try to get column names from stored queryColumnNames (works even for empty results)
        if let columnNames = appState.queryColumnNames, !columnNames.isEmpty {
            print("📋 [QueryResultsView] Using stored column names: \(columnNames.joined(separator: ", "))")
            return columnNames
        }
        
        // Fallback: Extract column names from the first row
        guard let firstRow = appState.queryResults.first else {
            print("⚠️  [QueryResultsView] No column names available")
            return nil
        }
        // Sort column names alphabetically for consistent ordering
        let columnNames = Array(firstRow.values.keys.sorted())
        print("📋 [QueryResultsView] Using column names from first row: \(columnNames.joined(separator: ", "))")
        return columnNames
    }

    private func formatValue(_ value: String?) -> String {
        guard let value = value else { return "NULL" }

        // Try to format as timestamp if it looks like a date/time
        if isLikelyTimestamp(value) {
            return Formatters.formatTimestamp(value)
        }

        return value
    }

    private func isLikelyTimestamp(_ value: String) -> Bool {
        // Check if value matches common timestamp patterns
        // ISO8601: "2024-11-30T12:34:56Z" or "2024-11-30T12:34:56.123Z"
        // PostgreSQL: "2024-11-30 12:34:56" or "2024-11-30 12:34:56.123456"
        // Date only: "2024-11-30"

        let timestampPatterns = [
            // ISO8601
            "^\\d{4}-\\d{2}-\\d{2}T\\d{2}:\\d{2}:\\d{2}",
            // PostgreSQL timestamp
            "^\\d{4}-\\d{2}-\\d{2} \\d{2}:\\d{2}:\\d{2}",
            // Date only
            "^\\d{4}-\\d{2}-\\d{2}$"
        ]

        for pattern in timestampPatterns {
            if value.range(of: pattern, options: .regularExpression) != nil {
                return true
            }
        }

        return false
    }
}
