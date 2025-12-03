//
//  QueryEditorView.swift
//  PostgresGUI
//
//  Created by Claude on 11/29/25.
//

import SwiftUI
import CodeEditorView
import LanguageSupport

struct QueryEditorView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.colorScheme) private var colorScheme
    @State private var position: CodeEditor.Position = CodeEditor.Position()
    @State private var messages: Set<TextLocated<Message>> = Set()

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar with execute button and stats
            HStack {
                Button(action: executeQuery) {
                    HStack(spacing: 4) {
                        Image(systemName: "play.circle.fill")
                        Text("Run Query")
                            .font(.system(size: 11, weight: .medium))
                    }
                }
                .disabled(appState.isExecutingQuery || appState.queryText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .buttonStyle(.glass)
                .tint(.primary)
                .clipShape(Capsule())
                .keyboardShortcut(.return, modifiers: [.command])

                Spacer()

                // Stats on the right
                if appState.showQueryResults {
                    HStack(spacing: 8) {
                        if appState.queryError != nil {
                            Label("Error", systemImage: "exclamationmark.triangle")
                                .foregroundColor(.red)
                                .font(.subheadline)
                        } else {
                            Text("\(appState.queryResults.count) rows")
                                .foregroundColor(.secondary)
                                .font(.subheadline)
                            
                            if let executionTime = appState.queryExecutionTime {
                                Text("•")
                                    .foregroundColor(.secondary)
                                Text(formatExecutionTime(executionTime))
                                    .foregroundColor(.secondary)
                                    .font(.subheadline)
                            }
                        }
                    }
                }
            }
            .padding(Constants.Spacing.small)
            .background(Color(NSColor.controlBackgroundColor))

            // Code editor
            CodeEditor(
                text: Binding(
                    get: { appState.queryText },
                    set: { appState.queryText = $0 }
                ),
                position: $position,
                messages: $messages,
                language: .sqlite(),
            )
            .environment(\.codeEditorLayoutConfiguration,
                CodeEditor.LayoutConfiguration(showMinimap: false, wrapText: true)
            )
            .environment(\.codeEditorTheme,
                         colorScheme == .dark ? Theme.defaultDark : Theme.defaultLight)
            .frame(minHeight: 150)
        }
    }

    private func executeQuery() {
        print("🎬 [QueryEditorView] Execute button clicked")
        Task {
            // Set loading state FIRST to prevent empty state flicker
            appState.isExecutingQuery = true
            appState.queryError = nil
            appState.queryExecutionTime = nil
            appState.showQueryResults = false // Hide results view during loading
            appState.queryResults = [] // Clear previous results
            appState.queryColumnNames = nil // Clear previous column names

            let startTime = Date()

            do {
                print("📊 [QueryEditorView] Executing query...")
                let (results, columnNames) = try await appState.databaseService.executeQuery(appState.queryText)
                appState.queryResults = results
                appState.queryColumnNames = columnNames.isEmpty ? nil : columnNames
                appState.showQueryResults = true
                
                let endTime = Date()
                appState.queryExecutionTime = endTime.timeIntervalSince(startTime)
                
                print("✅ [QueryEditorView] Query executed successfully, showing results")
            } catch {
                appState.queryError = error.localizedDescription
                appState.queryColumnNames = nil
                appState.showQueryResults = true
                
                let endTime = Date()
                appState.queryExecutionTime = endTime.timeIntervalSince(startTime)
                
                print("❌ [QueryEditorView] Query execution failed: \(error)")
            }

            appState.isExecutingQuery = false
        }
    }
    
    private func formatExecutionTime(_ timeInterval: TimeInterval) -> String {
        if timeInterval >= 1.0 {
            return String(format: "%.1fs", timeInterval)
        } else {
            let milliseconds = timeInterval * 1000
            return String(format: "%.0fms", milliseconds)
        }
    }
}
