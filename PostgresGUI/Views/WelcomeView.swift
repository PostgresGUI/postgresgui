//
//  WelcomeView.swift
//  PostgresGUI
//
//  Created by ghazi on 11/28/25.
//

import SwiftUI
import SwiftData

struct WelcomeView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var modelContext
    
    var body: some View {
        VStack(spacing: Constants.Spacing.large) {
            Image("Logo")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 200, height: 200)

            Text("Hello, and welcome!")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
            
            VStack(spacing: Constants.Spacing.small) {
                Button(action: connectToLocalhost) {
                    HStack {
                        Text("Connect to localhost")
                        Spacer()
                        Image(systemName: "desktopcomputer")
                    }
                    .frame(minWidth: 160, maxWidth: 200)
                    .padding(.vertical, 6)
                }
                .buttonStyle(.glassProminent)
                .controlSize(.large)
                
                Button(action: showConnectionForm) {
                    HStack {
                        Text("Connect to Server")
                        Spacer()
                        Image(systemName: "server.rack")
                    }
                    .frame(minWidth: 160, maxWidth: 200)
                    .padding(.vertical, 6)
                }
                .buttonStyle(.glassProminent)
                .tint(.secondary)
                .controlSize(.large)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal)
        .padding(.vertical)
    }
    
    private func connectToLocalhost() {
        Task {
            await connectToLocalhostAsync()
        }
    }
    
    private func connectToLocalhostAsync() async {
        let localhostProfile = ConnectionProfile.localhost()
        
        do {
            // First attempt: try without password (trust mode)
            try await appState.databaseService.connect(
                host: localhostProfile.host,
                port: localhostProfile.port,
                username: localhostProfile.username,
                password: "", // Empty password for trust mode
                database: localhostProfile.database,
                sslMode: localhostProfile.sslModeEnum
            )
            
            // Success - save profile and connect
            modelContext.insert(localhostProfile)
            try? modelContext.save()
            
            appState.currentConnection = localhostProfile
            appState.isConnected = true
            appState.isShowingWelcomeScreen = false
            
            // Load databases
            await loadDatabases()
            
        } catch {
            // If passwordless fails, prompt for password
            // For now, show connection form with localhost pre-filled
            appState.showConnectionForm()
        }
    }
    
    private func loadDatabases() async {
        do {
            appState.databases = try await appState.databaseService.fetchDatabases()
        } catch {
            // Handle error
            print("Failed to load databases: \(error)")
        }
    }
    
    private func showConnectionForm() {
        appState.showConnectionForm()
    }
}
