//
//  RootView.swift
//  PostgresGUI
//
//  App entry point. Delegates business logic to RootViewModel.
//

import SwiftUI
import SwiftData

struct RootView: View {
    @State private var appState = AppState()
    @State private var loadingState = LoadingState()
    @State private var tabManager = TabManager()
    @State private var viewModel: RootViewModel?
    @State private var tabChangeTask: Task<Void, Never>?
    @Query private var connections: [ConnectionProfile]
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.keychainService) private var keychainService

    var body: some View {
        ZStack {
            Group {
                if shouldShowWelcomeScreen(
                    connectionCount: connections.count,
                    isShowingConnectionForm: appState.navigation.isShowingConnectionForm
                ) {
                    WelcomeView()
                        .environment(appState)
                } else {
                    MainSplitView()
                        .environment(appState)
                }
            }

            if loadingState.isLoading {
                LoadingOverlayView(phase: loadingState.phase)
            }
        }
        .environment(tabManager)
        .environment(loadingState)
        .sheet(
            item: Binding(
                get: { appState.navigation.activeSheet },
                set: { appState.navigation.activeSheet = $0 }
            )
        ) { sheet in
            switch sheet {
            case let .connectionForm(connectionToEdit):
                ConnectionFormView(connectionToEdit: connectionToEdit)
                    .environment(appState)
            case .createDatabase:
                CreateDatabaseView { database in
                    Task {
                        await viewModel?.selectDatabase(database)
                    }
                }
                .environment(appState)
            case .keyboardShortcuts:
                KeyboardShortcutsView()
            case .help:
                HelpView()
            }
        }
        .task {
            guard viewModel == nil else { return }

            // Wire up tabManager to appState for result caching
            appState.tabManager = tabManager

            // Create ViewModel with dependencies
            let vm = RootViewModel(
                appState: appState,
                tabManager: tabManager,
                loadingState: loadingState,
                modelContext: modelContext,
                keychainService: keychainService
            )
            viewModel = vm
            await vm.initializeApp(connections: connections)
        }
        .onReceive(NotificationCenter.default.publisher(for: .tabDidChange)) { notification in
            tabChangeTask?.cancel()
            tabChangeTask = Task {
                // Now expects TabViewModel instead of TabState
                await viewModel?.handleTabChange(
                    notification.object as? TabViewModel,
                    connections: connections
                )
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .createNewTab)) { _ in
            viewModel?.saveCurrentStateToTab()
            tabManager.createNewTab(inheritingFrom: tabManager.activeTab)
            if let newTab = tabManager.activeTab {
                tabChangeTask?.cancel()
                tabChangeTask = Task {
                    await viewModel?.handleTabChange(newTab, connections: connections)
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .closeCurrentTab)) { _ in
            viewModel?.closeCurrentTab()
            if let newActiveTab = tabManager.activeTab {
                tabChangeTask?.cancel()
                tabChangeTask = Task {
                    await viewModel?.handleTabChange(newActiveTab, connections: connections)
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .showKeyboardShortcuts)) { _ in
            appState.showKeyboardShortcuts()
        }
        .onReceive(NotificationCenter.default.publisher(for: .showHelp)) { _ in
            appState.showHelp()
        }
        .onChange(of: scenePhase) { oldPhase, newPhase in
            if newPhase == .background {
                Task { @MainActor in
                    viewModel?.saveCurrentStateToTab()
                    await appState.cleanupOnWindowClose()
                }
            }
        }
        .alert("Connection Error", isPresented: .init(
            get: { viewModel?.initializationError != nil },
            set: { if !$0 { viewModel?.initializationError = nil } }
        )) {
            Button("OK", role: .cancel) { viewModel?.initializationError = nil }
        } message: {
            if let error = viewModel?.initializationError { Text(error) }
        }
    }
}
