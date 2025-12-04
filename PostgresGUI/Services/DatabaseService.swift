//
//  DatabaseService.swift
//  PostgresGUI
//
//  Created by ghazi on 11/28/25.
//

import Foundation
import PostgresNIO
import Logging
import NIOSSL

@MainActor
class DatabaseService {
    private var connection: PostgresConnection?
    private var eventLoopGroup: EventLoopGroup?
    private let logger = Logger(label: "com.postgresgui.database")
    
    // Store connection details for operations that require reconnection
    private var connectionHost: String?
    private var connectionPort: Int?
    private var connectionUsername: String?
    private var connectionPassword: String?
    private var connectionDatabase: String?
    private var connectionSSLMode: SSLMode?
    
    var isConnected: Bool {
        connection != nil
    }
    
    init() {}
    
    deinit {
        // Don't create async tasks in deinit - it causes retain cycles
        // The connection and eventLoopGroup will be cleaned up when they go out of scope
        // If we need cleanup, it should be done explicitly before deallocation
    }
    
    /// Connect to PostgreSQL database
    func connect(
        host: String,
        port: Int,
        username: String,
        password: String,
        database: String,
        sslMode: SSLMode = .default
    ) async throws {
        print("🔌 [DatabaseService.connect] START - Connecting to \(database) at \(host):\(port) as \(username)")

        // Validate inputs
        guard !host.isEmpty else {
            print("❌ [DatabaseService.connect] Invalid host: \(host)")
            throw ConnectionError.invalidHost(host)
        }

        guard port > 0 && port <= 65535 else {
            print("❌ [DatabaseService.connect] Invalid port: \(port)")
            throw ConnectionError.invalidPort
        }

        // Disconnect existing connection if any
        print("🔄 [DatabaseService.connect] Disconnecting existing connection...")
        await disconnect()
        print("✅ [DatabaseService.connect] Disconnected")

        // Create event loop group
        print("⚙️  [DatabaseService.connect] Creating event loop group...")
        let eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        self.eventLoopGroup = eventLoopGroup
        print("✅ [DatabaseService.connect] Event loop group created")

        // Store connection details for later use (e.g., reconnecting to drop databases)
        self.connectionHost = host
        self.connectionPort = port
        self.connectionUsername = username
        self.connectionPassword = password
        self.connectionDatabase = database
        self.connectionSSLMode = sslMode

        // Create connection configuration with appropriate TLS settings
        let tlsConfiguration: PostgresConnection.Configuration.TLS
        switch sslMode {
        case .disable:
            tlsConfiguration = .disable
        case .allow, .prefer:
            // Try TLS, fall back to plain if unavailable
            let sslContext = try! NIOSSLContext(configuration: .makeClientConfiguration())
            tlsConfiguration = .prefer(sslContext)
        case .require, .verifyCA, .verifyFull:
            // Require TLS
            let sslContext = try! NIOSSLContext(configuration: .makeClientConfiguration())
            tlsConfiguration = .require(sslContext)
        }

        let configuration = PostgresConnection.Configuration(
            host: host,
            port: port,
            username: username,
            password: password,
            database: database,
            tls: tlsConfiguration
        )
        print("⚙️  [DatabaseService.connect] Configuration created for \(database) with SSL mode: \(sslMode.rawValue)")

        do {
            // Connect to PostgreSQL
            print("🔌 [DatabaseService.connect] Attempting PostgreSQL connection...")
            let connection = try await PostgresConnection.connect(
                on: eventLoopGroup.next(),
                configuration: configuration,
                id: 1,
                logger: logger
            )

            self.connection = connection
            print("✅ [DatabaseService.connect] SUCCESS - Connected to \(database)")
        } catch {
            print("❌ [DatabaseService.connect] FAILED with error: \(error)")
            await disconnect()

            // Map PostgresNIO errors to ConnectionError
            if let postgresError = error as? PostgresError {
                print("❌ [DatabaseService.connect] PostgresError code: \(postgresError.code)")
                switch postgresError.code {
                case .invalidPassword, .invalidAuthorizationSpecification:
                    throw ConnectionError.authenticationFailed
                case .invalidCatalogName:
                    throw ConnectionError.databaseNotFound(database)
                default:
                    throw ConnectionError.unknownError(postgresError)
                }
            } else {
                // Check for network errors
                let nsError = error as NSError
                print("❌ [DatabaseService.connect] NSError domain: \(nsError.domain), code: \(nsError.code)")
                if nsError.domain == NSPOSIXErrorDomain {
                    switch nsError.code {
                    case 60: // ETIMEDOUT
                        throw ConnectionError.timeout
                    case 51, 50: // ENETUNREACH, EHOSTUNREACH
                        throw ConnectionError.networkUnreachable
                    default:
                        throw ConnectionError.unknownError(error)
                    }
                } else {
                    throw ConnectionError.unknownError(error)
                }
            }
        }
    }
    
    /// Disconnect from database
    func disconnect() async {
        if let connection = connection {
            try? await connection.close()
            self.connection = nil
        }
        
        if let eventLoopGroup = eventLoopGroup {
            try? await eventLoopGroup.shutdownGracefully()
            self.eventLoopGroup = nil
        }
        
        // Clear connection details
        connectionHost = nil
        connectionPort = nil
        connectionUsername = nil
        connectionPassword = nil
        connectionDatabase = nil
        connectionSSLMode = nil
    }
    
    /// Test connection without saving (static method - doesn't require instance)
    nonisolated static func testConnection(
        host: String,
        port: Int,
        username: String,
        password: String,
        database: String,
        sslMode: SSLMode = .default
    ) async throws -> Bool {
        // Run PostgresNIO operations off the main actor to avoid threading issues
        return try await Task.detached {
            // Create temporary connection for testing
            let eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: 1)
            let testLogger = Logger(label: "com.postgresgui.test")
            
            var testConnection: PostgresConnection?
            
            // Cleanup helper
            func cleanup() async {
                if let connection = testConnection {
                    try? await connection.close()
                    testConnection = nil
                }
                try? await eventLoopGroup.shutdownGracefully()
            }
            
            // Create TLS configuration based on SSL mode
            let tlsConfiguration: PostgresConnection.Configuration.TLS
            switch sslMode {
            case .disable:
                tlsConfiguration = .disable
            case .allow, .prefer:
                let sslContext = try! NIOSSLContext(configuration: .makeClientConfiguration())
                tlsConfiguration = .prefer(sslContext)
            case .require, .verifyCA, .verifyFull:
                let sslContext = try! NIOSSLContext(configuration: .makeClientConfiguration())
                tlsConfiguration = .require(sslContext)
            }

            let configuration = PostgresConnection.Configuration(
                host: host,
                port: port,
                username: username,
                password: password,
                database: database,
                tls: tlsConfiguration
            )
            
            do {
                testConnection = try await PostgresConnection.connect(
                    on: eventLoopGroup.next(),
                    configuration: configuration,
                    id: 1,
                    logger: testLogger
                )
                
                // Test successful - close connection and cleanup
                try await testConnection?.close()
                testConnection = nil
                try await eventLoopGroup.shutdownGracefully()
                return true
            } catch {
                // Error occurred - ensure cleanup happens
                await cleanup()
                
                // Map PostgresNIO errors to ConnectionError for better error messages
                if let postgresError = error as? PostgresError {
                    switch postgresError.code {
                    case .invalidPassword, .invalidAuthorizationSpecification:
                        throw ConnectionError.authenticationFailed
                    case .invalidCatalogName:
                        throw ConnectionError.databaseNotFound(database)
                    default:
                        throw ConnectionError.unknownError(postgresError)
                    }
                } else {
                    // Check for network errors
                    let nsError = error as NSError
                    if nsError.domain == NSPOSIXErrorDomain {
                        switch nsError.code {
                        case 1: // EPERM - Operation not permitted (sandbox issue)
                            throw ConnectionError.networkUnreachable
                        case 60: // ETIMEDOUT
                            throw ConnectionError.timeout
                        case 51, 50: // ENETUNREACH, EHOSTUNREACH
                            throw ConnectionError.networkUnreachable
                        case 61: // ECONNREFUSED - Connection refused
                            throw ConnectionError.networkUnreachable
                        default:
                            throw ConnectionError.unknownError(error)
                        }
                    } else {
                        throw ConnectionError.unknownError(error)
                    }
                }
            }
        }.value
    }
    
    /// Fetch list of databases
    func fetchDatabases() async throws -> [DatabaseInfo] {
        guard let connection = connection else {
            throw ConnectionError.notConnected
        }

        let query: PostgresQuery = """
            SELECT datname
            FROM pg_database
            WHERE datistemplate = false
            ORDER BY datname;
            """

        let rows = try await connection.query(query, logger: logger)

        var databases: [DatabaseInfo] = []
        for try await row in rows {
            let randomAccess = row.makeRandomAccess()
            let name = try randomAccess[0].decode(String.self)
            databases.append(DatabaseInfo(name: name))
        }

        return databases
    }
    
    /// Fetch list of tables in a database
    func fetchTables(database: String) async throws -> [TableInfo] {
        print("📊 [DatabaseService.fetchTables] START for database: \(database)")

        guard let connection = connection else {
            print("❌ [DatabaseService.fetchTables] ERROR: Not connected")
            throw ConnectionError.notConnected
        }
        print("✅ [DatabaseService.fetchTables] Connection exists")

        let query: PostgresQuery = """
            SELECT table_name, table_schema
            FROM information_schema.tables
            WHERE table_schema NOT IN ('pg_catalog', 'information_schema')
            AND table_type = 'BASE TABLE'
            ORDER BY table_schema, table_name;
            """
        print("📝 [DatabaseService.fetchTables] Executing query...")

        let rows = try await connection.query(query, logger: logger)
        print("✅ [DatabaseService.fetchTables] Query executed, processing rows...")

        var tables: [TableInfo] = []
        for try await row in rows {
            let randomAccess = row.makeRandomAccess()
            let name = try randomAccess[0].decode(String.self)
            let schema = try randomAccess[1].decode(String.self)
            tables.append(TableInfo(name: name, schema: schema))
            print("   ➕ Found table: \(schema).\(name)")
        }

        print("✅ [DatabaseService.fetchTables] SUCCESS - Fetched \(tables.count) tables")
        return tables
    }
    
    /// Fetch table data with pagination
    func fetchTableData(
        schema: String,
        table: String,
        offset: Int,
        limit: Int
    ) async throws -> [TableRow] {
        print("📊 [DatabaseService.fetchTableData] START for \(schema).\(table), offset=\(offset), limit=\(limit)")

        guard let connection = connection else {
            print("❌ [DatabaseService.fetchTableData] ERROR: Not connected")
            throw ConnectionError.notConnected
        }

        // Note: We can't use PostgresNIO's parameter binding for table names (identifiers)
        // They must be part of the SQL string, but LIMIT/OFFSET can be bound
        let querySQL = """
            SELECT * FROM \(table)
            LIMIT \(limit) OFFSET \(offset);
            """

        print("📝 [DatabaseService.fetchTableData] Query: \(querySQL)")
        let query = PostgresQuery(unsafeSQL: querySQL)

        let rows: PostgresRowSequence
        do {
            rows = try await connection.query(query, logger: logger)
            print("✅ [DatabaseService.fetchTableData] Query executed successfully")
        } catch {
            print("❌ [DatabaseService.fetchTableData] ERROR executing query: \(error)")
            print("❌ [DatabaseService.fetchTableData] Error details: \(String(reflecting: error))")
            throw error
        }

        // First, collect column names from the first row
        var columnNames: [String] = []
        var isFirstRow = true

        var tableRows: [TableRow] = []
        for try await row in rows {
            var values: [String: String?] = [:]
            let randomAccess = row.makeRandomAccess()

            // On first row, extract column names using reflection
            if isFirstRow {
                // Use Mirror to inspect the row structure and extract column names
                let mirror = Mirror(reflecting: randomAccess)
                if let lookupTable = mirror.children.first(where: { $0.label == "lookupTable" })?.value as? [String: Int] {
                    columnNames = lookupTable.sorted(by: { $0.value < $1.value }).map { $0.key }
                } else {
                    // Fallback: use index-based names if reflection fails
                    columnNames = (0..<randomAccess.count).map { "col_\($0)" }
                }
                isFirstRow = false
            }

            // Extract values for each column
            for (index, columnName) in columnNames.enumerated() {
                guard index < randomAccess.count else { break }
                let value: String?

                // Try to decode in order of specificity (most specific types first)
                // Try Bool first (most specific)
                if let boolValue = try? randomAccess[index].decode(Bool.self) {
                    value = String(boolValue)
                }
                // Try Int64 (integers)
                else if let intValue = try? randomAccess[index].decode(Int64.self) {
                    value = String(intValue)
                }
                // Try Double (floating point)
                else if let doubleValue = try? randomAccess[index].decode(Double.self) {
                    value = String(doubleValue)
                }
                // Try Date (for timestamp columns)
                else if let dateValue = try? randomAccess[index].decode(Date.self) {
                    let formatter = DateFormatter()
                    formatter.dateStyle = .medium
                    formatter.timeStyle = .medium
                    value = formatter.string(from: dateValue)
                }
                // Try String last (most general, catches everything else)
                else if let stringValue = try? randomAccess[index].decode(String.self) {
                    value = stringValue
                }
                else {
                    value = nil // NULL or unsupported type
                }

                values[columnName] = value
            }

            tableRows.append(TableRow(values: values))
        }

        return tableRows
    }
    

    /// Execute arbitrary SQL query and return results along with column names
    func executeQuery(_ sql: String) async throws -> ([TableRow], [String]) {
        print("🔍 [DatabaseService.executeQuery] START")
        print("📝 [DatabaseService.executeQuery] Query: \(sql)")

        guard let connection = connection else {
            print("❌ [DatabaseService.executeQuery] ERROR: Not connected")
            throw ConnectionError.notConnected
        }

        // Create query from raw SQL
        let query = PostgresQuery(unsafeSQL: sql)

        let rows: PostgresRowSequence
        do {
            rows = try await connection.query(query, logger: logger)
            print("✅ [DatabaseService.executeQuery] Query executed successfully")
        } catch {
            print("❌ [DatabaseService.executeQuery] ERROR executing query: \(error)")
            print("❌ [DatabaseService.executeQuery] Error details: \(String(reflecting: error))")
            throw error
        }

        // First, collect column names from the first row (or try to extract from empty result)
        var columnNames: [String] = []
        var isFirstRow = true

        var tableRows: [TableRow] = []
        for try await row in rows {
            var values: [String: String?] = [:]
            let randomAccess = row.makeRandomAccess()

            // On first row, extract column names using reflection
            if isFirstRow {
                // Use Mirror to inspect the row structure and extract column names
                let mirror = Mirror(reflecting: randomAccess)
                if let lookupTable = mirror.children.first(where: { $0.label == "lookupTable" })?.value as? [String: Int] {
                    columnNames = lookupTable.sorted(by: { $0.value < $1.value }).map { $0.key }
                    print("📋 [DatabaseService.executeQuery] Column names: \(columnNames.joined(separator: ", "))")
                } else {
                    // Fallback: use index-based names if reflection fails
                    columnNames = (0..<randomAccess.count).map { "col_\($0)" }
                    print("⚠️  [DatabaseService.executeQuery] Using fallback column names")
                }
                isFirstRow = false
            }

            // Extract values for each column
            for (index, columnName) in columnNames.enumerated() {
                guard index < randomAccess.count else { break }
                let value: String?

                // Try to decode in order of specificity (most specific types first)
                // Try Bool first (most specific)
                if let boolValue = try? randomAccess[index].decode(Bool.self) {
                    value = String(boolValue)
                }
                // Try Int64 (integers)
                else if let intValue = try? randomAccess[index].decode(Int64.self) {
                    value = String(intValue)
                }
                // Try Double (floating point)
                else if let doubleValue = try? randomAccess[index].decode(Double.self) {
                    value = String(doubleValue)
                }
                // Try Date (for timestamp columns)
                else if let dateValue = try? randomAccess[index].decode(Date.self) {
                    let formatter = DateFormatter()
                    formatter.dateStyle = .medium
                    formatter.timeStyle = .medium
                    value = formatter.string(from: dateValue)
                }
                // Try String last (most general, catches everything else)
                else if let stringValue = try? randomAccess[index].decode(String.self) {
                    value = stringValue
                }
                else {
                    value = nil // NULL or unsupported type
                }

                values[columnName] = value
            }

            tableRows.append(TableRow(values: values))
        }
        
        // If we have no rows but also no column names, try to extract from result metadata
        if columnNames.isEmpty && tableRows.isEmpty {
            print("🔍 [DatabaseService.executeQuery] Attempting to extract column metadata from empty result")
            // Try multiple approaches to get column metadata
            do {
                let trimmedSQL = sql.trimmingCharacters(in: .whitespacesAndNewlines)
                let upperSQL = trimmedSQL.uppercased()
                
                // Approach 1: Try wrapping SELECT queries in a CTE with LIMIT 0
                if upperSQL.hasPrefix("SELECT") {
                    // Use a CTE approach which is more reliable than subquery
                    let metadataQuerySQL = "WITH _metadata_cte AS (\(trimmedSQL)) SELECT * FROM _metadata_cte LIMIT 0"
                    print("📝 [DatabaseService.executeQuery] Trying CTE approach: \(metadataQuerySQL)")
                    
                    let metadataQuery = PostgresQuery(unsafeSQL: metadataQuerySQL)
                    let metadataRows = try await connection.query(metadataQuery, logger: logger)
                    
                    // Try to iterate and get metadata from the first row (even if empty)
                    var iterator = metadataRows.makeAsyncIterator()
                    if let row = try await iterator.next() {
                        let randomAccess = row.makeRandomAccess()
                        let mirror = Mirror(reflecting: randomAccess)
                        if let lookupTable = mirror.children.first(where: { $0.label == "lookupTable" })?.value as? [String: Int] {
                            columnNames = lookupTable.sorted(by: { $0.value < $1.value }).map { $0.key }
                            print("✅ [DatabaseService.executeQuery] Column names from CTE metadata: \(columnNames.joined(separator: ", "))")
                        }
                    }
                }
                
                // Approach 2: If CTE failed, try simple LIMIT 0
                if columnNames.isEmpty {
                    let metadataQuerySQL = trimmedSQL + " LIMIT 0"
                    print("📝 [DatabaseService.executeQuery] Trying LIMIT 0 approach: \(metadataQuerySQL)")
                    
                    let metadataQuery = PostgresQuery(unsafeSQL: metadataQuerySQL)
                    let metadataRows = try await connection.query(metadataQuery, logger: logger)
                    
                    var iterator = metadataRows.makeAsyncIterator()
                    if let row = try await iterator.next() {
                        let randomAccess = row.makeRandomAccess()
                        let mirror = Mirror(reflecting: randomAccess)
                        if let lookupTable = mirror.children.first(where: { $0.label == "lookupTable" })?.value as? [String: Int] {
                            columnNames = lookupTable.sorted(by: { $0.value < $1.value }).map { $0.key }
                            print("✅ [DatabaseService.executeQuery] Column names from LIMIT 0 metadata: \(columnNames.joined(separator: ", "))")
                        }
                    }
                }
                
                if columnNames.isEmpty {
                    print("⚠️  [DatabaseService.executeQuery] Could not extract column metadata from empty result")
                }
            } catch {
                // If metadata extraction fails, columnNames will remain empty
                print("⚠️  [DatabaseService.executeQuery] Failed to extract column metadata: \(error.localizedDescription)")
            }
        }

        print("✅ [DatabaseService.executeQuery] SUCCESS - Returned \(tableRows.count) rows, \(columnNames.count) columns")
        return (tableRows, columnNames)
    }
    
    /// Delete a database
    func deleteDatabase(name: String) async throws {
        print("🗑️  [DatabaseService.deleteDatabase] START for database: \(name)")
        
        guard connection != nil else {
            print("❌ [DatabaseService.deleteDatabase] ERROR: Not connected")
            throw ConnectionError.notConnected
        }
        
        // We need connection details to reconnect to 'postgres' database
        guard let host = connectionHost,
              let port = connectionPort,
              let username = connectionUsername,
              let password = connectionPassword else {
            print("❌ [DatabaseService.deleteDatabase] ERROR: Connection details not available")
            throw ConnectionError.notConnected
        }
        
        // Save original database name
        let originalDatabase = connectionDatabase
        
        // Disconnect from current database (can't drop database while connected to it)
        await disconnect()
        
        // Connect to 'postgres' database to drop the target database
        let eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        self.eventLoopGroup = eventLoopGroup

        // Use stored SSL mode or default
        let sslMode = connectionSSLMode ?? .default
        let tlsConfiguration: PostgresConnection.Configuration.TLS
        switch sslMode {
        case .disable:
            tlsConfiguration = .disable
        case .allow, .prefer:
            let sslContext = try! NIOSSLContext(configuration: .makeClientConfiguration())
            tlsConfiguration = .prefer(sslContext)
        case .require, .verifyCA, .verifyFull:
            let sslContext = try! NIOSSLContext(configuration: .makeClientConfiguration())
            tlsConfiguration = .require(sslContext)
        }

        let configuration = PostgresConnection.Configuration(
            host: host,
            port: port,
            username: username,
            password: password,
            database: "postgres", // Connect to postgres database
            tls: tlsConfiguration
        )
        
        do {
            let postgresConnection = try await PostgresConnection.connect(
                on: eventLoopGroup.next(),
                configuration: configuration,
                id: 1,
                logger: logger
            )
            
            self.connection = postgresConnection
            
            // Execute DROP DATABASE
            // Escape database name properly
            let escapedName = name.replacingOccurrences(of: "\"", with: "\"\"")
            let dropQuerySQL = "DROP DATABASE \"\(escapedName)\";"
            let dropQuery = PostgresQuery(unsafeSQL: dropQuerySQL)
            
            print("📝 [DatabaseService.deleteDatabase] Executing: \(dropQuerySQL)")
            _ = try await postgresConnection.query(dropQuery, logger: logger)
            
            print("✅ [DatabaseService.deleteDatabase] SUCCESS - Database '\(name)' deleted")
            
            // Close connection to postgres
            try? await postgresConnection.close()
            self.connection = nil
            try? await eventLoopGroup.shutdownGracefully()
            self.eventLoopGroup = nil
            
            // Optionally reconnect to original database if it wasn't the one we deleted
            if let originalDatabase = originalDatabase, originalDatabase != name {
                print("🔄 [DatabaseService.deleteDatabase] Reconnecting to original database: \(originalDatabase)")
                try await connect(
                    host: host,
                    port: port,
                    username: username,
                    password: password,
                    database: originalDatabase,
                    sslMode: sslMode
                )
            }
            
        } catch {
            print("❌ [DatabaseService.deleteDatabase] ERROR: \(error)")
            await disconnect()
            throw error
        }
    }
    
    /// Create a new database
    func createDatabase(name: String) async throws {
        print("➕ [DatabaseService.createDatabase] START for database: \(name)")
        
        guard connection != nil else {
            print("❌ [DatabaseService.createDatabase] ERROR: Not connected")
            throw ConnectionError.notConnected
        }
        
        // We need connection details to reconnect to 'postgres' database
        guard let host = connectionHost,
              let port = connectionPort,
              let username = connectionUsername,
              let password = connectionPassword else {
            print("❌ [DatabaseService.createDatabase] ERROR: Connection details not available")
            throw ConnectionError.notConnected
        }
        
        // Save original database name
        let originalDatabase = connectionDatabase
        
        // Disconnect from current database
        await disconnect()
        
        // Connect to 'postgres' database to create the new database
        let eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        self.eventLoopGroup = eventLoopGroup

        // Use stored SSL mode or default
        let sslMode = connectionSSLMode ?? .default
        let tlsConfiguration: PostgresConnection.Configuration.TLS
        switch sslMode {
        case .disable:
            tlsConfiguration = .disable
        case .allow, .prefer:
            let sslContext = try! NIOSSLContext(configuration: .makeClientConfiguration())
            tlsConfiguration = .prefer(sslContext)
        case .require, .verifyCA, .verifyFull:
            let sslContext = try! NIOSSLContext(configuration: .makeClientConfiguration())
            tlsConfiguration = .require(sslContext)
        }

        let configuration = PostgresConnection.Configuration(
            host: host,
            port: port,
            username: username,
            password: password,
            database: "postgres", // Connect to postgres database
            tls: tlsConfiguration
        )
        
        do {
            let postgresConnection = try await PostgresConnection.connect(
                on: eventLoopGroup.next(),
                configuration: configuration,
                id: 1,
                logger: logger
            )
            
            self.connection = postgresConnection
            
            // Execute CREATE DATABASE
            // Escape database name properly
            let escapedName = name.replacingOccurrences(of: "\"", with: "\"\"")
            let createQuerySQL = "CREATE DATABASE \"\(escapedName)\";"
            let createQuery = PostgresQuery(unsafeSQL: createQuerySQL)
            
            print("📝 [DatabaseService.createDatabase] Executing: \(createQuerySQL)")
            _ = try await postgresConnection.query(createQuery, logger: logger)
            
            print("✅ [DatabaseService.createDatabase] SUCCESS - Database '\(name)' created")
            
            // Close connection to postgres
            try? await postgresConnection.close()
            self.connection = nil
            try? await eventLoopGroup.shutdownGracefully()
            self.eventLoopGroup = nil
            
            // Reconnect to original database if it exists
            if let originalDatabase = originalDatabase {
                print("🔄 [DatabaseService.createDatabase] Reconnecting to original database: \(originalDatabase)")
                try await connect(
                    host: host,
                    port: port,
                    username: username,
                    password: password,
                    database: originalDatabase,
                    sslMode: sslMode
                )
            }
            
        } catch {
            print("❌ [DatabaseService.createDatabase] ERROR: \(error)")
            await disconnect()
            throw error
        }
    }
    
    /// Delete a table
    func deleteTable(schema: String, table: String) async throws {
        print("🗑️  [DatabaseService.deleteTable] START for \(schema).\(table)")
        
        guard let connection = connection else {
            print("❌ [DatabaseService.deleteTable] ERROR: Not connected")
            throw ConnectionError.notConnected
        }
        
        // Escape schema and table names properly
        let escapedSchema = schema.replacingOccurrences(of: "\"", with: "\"\"")
        let escapedTable = table.replacingOccurrences(of: "\"", with: "\"\"")
        
        // Execute DROP TABLE
        let dropQuerySQL = "DROP TABLE \"\(escapedSchema)\".\"\(escapedTable)\";"
        let dropQuery = PostgresQuery(unsafeSQL: dropQuerySQL)
        
        print("📝 [DatabaseService.deleteTable] Executing: \(dropQuerySQL)")
        
        do {
            _ = try await connection.query(dropQuery, logger: logger)
            print("✅ [DatabaseService.deleteTable] SUCCESS - Table '\(schema).\(table)' deleted")
        } catch {
            print("❌ [DatabaseService.deleteTable] ERROR: \(error)")
            throw error
        }
    }
}
