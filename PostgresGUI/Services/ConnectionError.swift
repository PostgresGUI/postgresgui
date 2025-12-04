//
//  ConnectionError.swift
//  PostgresGUI
//
//  Created by ghazi on 11/28/25.
//

import Foundation

enum ConnectionError: LocalizedError {
    case invalidHost(String)
    case invalidPort
    case authenticationFailed
    case databaseNotFound(String)
    case timeout
    case networkUnreachable
    case notConnected
    case unknownError(Error)
    case invalidConnectionString(ConnectionStringParser.ParseError)
    case unsupportedParameters([String])
    
    var errorDescription: String? {
        switch self {
        case .invalidHost(let host):
            return "Invalid host: \(host)"
        case .invalidPort:
            return "Invalid port number"
        case .authenticationFailed:
            return "Authentication failed. Please check your username and password."
        case .databaseNotFound(let database):
            return "Database '\(database)' not found."
        case .timeout:
            return "Connection timeout. Please check your network connection."
        case .networkUnreachable:
            return "Network unreachable. Please check your connection settings."
        case .notConnected:
            return "Not connected to database."
        case .unknownError(let error):
            return "An error occurred: \(error.localizedDescription)"
        case .invalidConnectionString(let parseError):
            return parseError.errorDescription
        case .unsupportedParameters(let params):
            return "Connection string contains unsupported parameters: \(params.joined(separator: ", "))"
        }
    }
    
    var recoverySuggestion: String? {
        switch self {
        case .invalidHost:
            return "Please enter a valid hostname or IP address."
        case .invalidPort:
            return "Port must be between 1 and 65535."
        case .authenticationFailed:
            return "Verify your username and password are correct. For localhost, try passwordless authentication first."
        case .databaseNotFound:
            return "Make sure the database exists and you have permission to access it."
        case .timeout:
            return "Check that PostgreSQL is running and the host/port are correct."
        case .networkUnreachable:
            return "Verify your network connection and firewall settings."
        case .notConnected:
            return "Please connect to a database first."
        case .unknownError:
            return "Please try again or check the server logs for more details."
        case .invalidConnectionString(let parseError):
            return parseError.recoverySuggestion
        case .unsupportedParameters:
            return "These parameters will be ignored. The connection will proceed with basic settings."
        }
    }
}
