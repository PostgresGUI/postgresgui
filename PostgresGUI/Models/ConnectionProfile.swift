//
//  ConnectionProfile.swift
//  PostgresGUI
//
//  Created by ghazi on 11/28/25.
//

import Foundation
import SwiftData

@Model
final class ConnectionProfile: Identifiable {
    var id: UUID
    var name: String
    var host: String
    var port: Int
    var username: String
    var database: String
    var isFavorite: Bool
    
    init(
        id: UUID = UUID(),
        name: String,
        host: String,
        port: Int = Constants.PostgreSQL.defaultPort,
        username: String,
        database: String = Constants.PostgreSQL.defaultDatabase,
        isFavorite: Bool = false
    ) {
        self.id = id
        self.name = name
        self.host = host
        self.port = port
        self.username = username
        self.database = database
        self.isFavorite = isFavorite
    }
}

extension ConnectionProfile {
    /// Creates a default localhost connection profile
    static func localhost() -> ConnectionProfile {
        ConnectionProfile(
            name: "localhost",
            host: "localhost",
            port: Constants.PostgreSQL.defaultPort,
            username: Constants.PostgreSQL.defaultUsername,
            database: Constants.PostgreSQL.defaultDatabase
        )
    }

    /// Generate a connection string from this profile
    /// - Parameter includePassword: Whether to include the password from Keychain in the connection string
    /// - Returns: A PostgreSQL connection string
    func toConnectionString(includePassword: Bool = false) -> String {
        let password = includePassword ? (try? KeychainService.getPassword(for: id)) : nil
        return ConnectionStringParser.build(
            username: username,
            password: password,
            host: host,
            port: port,
            database: database
        )
    }

    /// Create a ConnectionProfile from a connection string
    /// - Parameters:
    ///   - connectionString: The PostgreSQL connection string to parse
    ///   - name: The name to assign to this connection profile
    ///   - id: Optional UUID for the profile (defaults to a new UUID)
    /// - Returns: A tuple containing the ConnectionProfile and the password (if present in the connection string)
    /// - Throws: ConnectionStringParser.ParseError if the connection string is invalid
    static func from(
        connectionString: String,
        name: String,
        id: UUID = UUID()
    ) throws -> (profile: ConnectionProfile, password: String?) {
        let parsed = try ConnectionStringParser.parse(connectionString)

        let profile = ConnectionProfile(
            id: id,
            name: name,
            host: parsed.host,
            port: parsed.port,
            username: parsed.username ?? Constants.PostgreSQL.defaultUsername,
            database: parsed.database ?? Constants.PostgreSQL.defaultDatabase
        )

        return (profile: profile, password: parsed.password)
    }
}
