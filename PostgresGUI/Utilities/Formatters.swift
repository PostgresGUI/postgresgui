//
//  Formatters.swift
//  PostgresGUI
//
//  Created by ghazi on 11/28/25.
//

import Foundation

enum Formatters {
    /// Format bytes to human-readable string
    static func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB, .useTB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }

    /// Format number with thousand separators
    static func formatNumber(_ number: Int64) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: number)) ?? "\(number)"
    }

    /// Format PostgreSQL timestamp values
    static func formatTimestamp(_ value: String) -> String {
        // Try to parse ISO8601 timestamp (e.g., "2024-11-30T12:34:56Z")
        let iso8601Formatter = ISO8601DateFormatter()
        iso8601Formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        if let date = iso8601Formatter.date(from: value) {
            let dateFormatter = DateFormatter()
            dateFormatter.dateStyle = .medium
            dateFormatter.timeStyle = .medium
            return dateFormatter.string(from: date)
        }

        // Try without fractional seconds
        iso8601Formatter.formatOptions = [.withInternetDateTime]
        if let date = iso8601Formatter.date(from: value) {
            let dateFormatter = DateFormatter()
            dateFormatter.dateStyle = .medium
            dateFormatter.timeStyle = .medium
            return dateFormatter.string(from: date)
        }

        // Try PostgreSQL timestamp format (e.g., "2024-11-30 12:34:56")
        let postgresFormatter = DateFormatter()
        postgresFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        postgresFormatter.locale = Locale(identifier: "en_US_POSIX")

        if let date = postgresFormatter.date(from: value) {
            let displayFormatter = DateFormatter()
            displayFormatter.dateStyle = .medium
            displayFormatter.timeStyle = .medium
            return displayFormatter.string(from: date)
        }

        // Try date-only format (e.g., "2024-11-30")
        let dateOnlyFormatter = DateFormatter()
        dateOnlyFormatter.dateFormat = "yyyy-MM-dd"
        dateOnlyFormatter.locale = Locale(identifier: "en_US_POSIX")

        if let date = dateOnlyFormatter.date(from: value) {
            let displayFormatter = DateFormatter()
            displayFormatter.dateStyle = .medium
            displayFormatter.timeStyle = .none
            return displayFormatter.string(from: date)
        }

        // If no format matches, return original value
        return value
    }
}
