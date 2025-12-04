//
//  ConnectionStringParser.swift
//  PostgresGUI
//
//  Created by Claude Code
//

import Foundation

/// SSL mode options for PostgreSQL connections
enum SSLMode: String, Sendable {
    case disable = "disable"
    case allow = "allow"
    case prefer = "prefer"
    case require = "require"
    case verifyCA = "verify-ca"
    case verifyFull = "verify-full"

    /// Default SSL mode when not specified
    nonisolated static let `default` = SSLMode.prefer
}

/// Represents a parsed PostgreSQL connection string
struct PostgresConnectionString {
    let scheme: String
    let username: String?
    let password: String?
    let host: String
    let port: Int
    let database: String?
    let queryParameters: [String: String]
    let sslMode: SSLMode

    /// Returns a list of query parameters that are not currently supported by the application
    var unsupportedParameters: [String] {
        let unsupported = [
            "connect_timeout", "application_name",
            "client_encoding", "options", "fallback_application_name",
            "keepalives", "keepalives_idle", "keepalives_interval",
            "keepalives_count", "tcp_user_timeout", "replication",
            "gssencmode", "sslcert", "sslkey", "sslrootcert",
            "sslcrl", "requirepeer", "ssl_min_protocol_version",
            "ssl_max_protocol_version", "krbsrvname", "gsslib",
            "service", "target_session_attrs"
        ]

        return queryParameters.keys.filter { unsupported.contains($0) }
    }
}

/// Utility for parsing and building PostgreSQL connection strings
enum ConnectionStringParser {

    /// Errors that can occur during connection string parsing
    enum ParseError: LocalizedError {
        case invalidFormat
        case invalidScheme
        case invalidPort
        case emptyHost
        case malformedURL
        case invalidPercentEncoding

        var errorDescription: String? {
            switch self {
            case .invalidFormat:
                return "Invalid connection string format"
            case .invalidScheme:
                return "Invalid scheme. Use 'postgres://' or 'postgresql://'"
            case .invalidPort:
                return "Invalid port number in connection string"
            case .emptyHost:
                return "Host cannot be empty in connection string"
            case .malformedURL:
                return "Malformed connection string URL"
            case .invalidPercentEncoding:
                return "Invalid percent-encoding in connection string"
            }
        }

        var recoverySuggestion: String? {
            switch self {
            case .invalidFormat:
                return "Format: postgresql://[user[:password]@][host][:port][/database][?param=value]"
            case .invalidScheme:
                return "Use 'postgres://' or 'postgresql://' at the start"
            case .invalidPort:
                return "Port must be between 1 and 65535"
            case .emptyHost:
                return "Provide a valid hostname or IP address"
            case .malformedURL:
                return "Check the connection string syntax"
            case .invalidPercentEncoding:
                return "Check special characters are properly percent-encoded"
            }
        }
    }

    /// Parse a PostgreSQL connection string into its components
    /// - Parameter connectionString: The connection string to parse (e.g., "postgresql://user:pass@localhost:5432/mydb")
    /// - Returns: A PostgresConnectionString struct containing the parsed components
    /// - Throws: ParseError if the connection string is invalid
    static func parse(_ connectionString: String) throws -> PostgresConnectionString {
        // Trim whitespace
        let trimmed = connectionString.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmed.isEmpty else {
            throw ParseError.invalidFormat
        }

        // Parse using URLComponents for robust URL handling
        guard let components = URLComponents(string: trimmed) else {
            throw ParseError.malformedURL
        }

        // Validate scheme
        guard let scheme = components.scheme,
              scheme == "postgres" || scheme == "postgresql" else {
            throw ParseError.invalidScheme
        }

        // Extract host (required)
        guard let host = components.host, !host.isEmpty else {
            throw ParseError.emptyHost
        }

        // Extract port (default to 5432)
        let port: Int
        if let portValue = components.port {
            guard portValue > 0 && portValue <= 65535 else {
                throw ParseError.invalidPort
            }
            port = portValue
        } else {
            port = Constants.PostgreSQL.defaultPort
        }

        // Extract username and password (optional)
        let username = components.user
        let password = components.password

        // Extract database from path (optional)
        let database: String?
        let path = components.path
        if !path.isEmpty {
            // Remove leading slash
            let dbName = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            database = dbName.isEmpty ? nil : dbName
        } else {
            database = nil
        }

        // Parse query parameters
        var queryParams: [String: String] = [:]
        if let queryItems = components.queryItems {
            for item in queryItems {
                if let value = item.value {
                    queryParams[item.name] = value
                } else {
                    // Parameter without value (e.g., ?sslmode=)
                    queryParams[item.name] = ""
                }
            }
        }

        // Extract SSL mode from query parameters
        let sslMode: SSLMode
        if let sslModeString = queryParams["sslmode"] {
            sslMode = SSLMode(rawValue: sslModeString) ?? .default
        } else {
            sslMode = .default
        }

        return PostgresConnectionString(
            scheme: scheme,
            username: username,
            password: password,
            host: host,
            port: port,
            database: database,
            queryParameters: queryParams,
            sslMode: sslMode
        )
    }

    /// Build a PostgreSQL connection string from individual components
    /// - Parameters:
    ///   - username: Optional username
    ///   - password: Optional password
    ///   - host: Host address (required)
    ///   - port: Port number (optional, defaults to 5432)
    ///   - database: Database name (optional)
    ///   - sslMode: SSL mode (optional, defaults to prefer)
    /// - Returns: A PostgreSQL connection string
    static func build(
        username: String?,
        password: String?,
        host: String,
        port: Int,
        database: String?,
        sslMode: SSLMode = .default
    ) -> String {
        var components = URLComponents()
        components.scheme = "postgresql"

        // Set username and password if provided
        if let username = username, !username.isEmpty {
            components.user = username
        }
        if let password = password, !password.isEmpty {
            components.password = password
        }

        // Set host
        components.host = host

        // Only set port if it's not the default
        if port != Constants.PostgreSQL.defaultPort {
            components.port = port
        }

        // Set database if provided
        if let database = database, !database.isEmpty {
            components.path = "/\(database)"
        }

        // Add SSL mode as query parameter if not default
        if sslMode != .default {
            components.queryItems = [URLQueryItem(name: "sslmode", value: sslMode.rawValue)]
        }

        return components.string ?? ""
    }
}
