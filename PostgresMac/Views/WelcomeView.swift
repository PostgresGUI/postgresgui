//
//  WelcomeView.swift
//  PostgresMac
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
            Text("PostgresMac")
                .font(.system(size: 48, weight: .bold))
                .padding(.bottom, Constants.Spacing.extraLarge)
            
            VStack(spacing: Constants.Spacing.medium) {
                Button(action: connectToLocalhost) {
                    Text("Connect to localhost")
                        .frame(minWidth: 200)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                
                Button(action: showConnectionForm) {
                    Text("Connect to Server")
                        .frame(minWidth: 200)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
                database: localhostProfile.database
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
            appState.isShowingConnectionForm = true
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
        appState.isShowingConnectionForm = true
    }
}
