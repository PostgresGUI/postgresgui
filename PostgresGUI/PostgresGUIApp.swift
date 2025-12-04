//
//  PostgresGUIApp.swift
//  PostgresGUI
//
//  Created by ghazi on 11/28/25.
//

import SwiftUI
import SwiftData

@main
struct PostgresGUIApp: App {
    @State private var appState = AppState()

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            ConnectionProfile.self,
        ])

        let modelConfiguration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false
        )

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            // If migration fails, try to delete the old database
            print("⚠️ Failed to create ModelContainer: \(error)")
            print("⚠️ Attempting to delete old database and create fresh...")

            // Get the default store URL
            let appSupportURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            let storeURL = appSupportURL.appendingPathComponent("default.store")

            do {
                // Remove all store files
                let storeFiles = [
                    storeURL,
                    storeURL.appendingPathExtension("wal"),
                    storeURL.appendingPathExtension("shm")
                ]

                for file in storeFiles {
                    if FileManager.default.fileExists(atPath: file.path) {
                        try FileManager.default.removeItem(at: file)
                        print("✅ Removed: \(file.lastPathComponent)")
                    }
                }

                return try ModelContainer(for: schema, configurations: [modelConfiguration])
            } catch {
                fatalError("Could not create ModelContainer even after cleanup: \(error)")
            }
        }
    }()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(appState)
        }
        .modelContainer(sharedModelContainer)
    }
}
