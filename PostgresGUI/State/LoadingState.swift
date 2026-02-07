//
//  LoadingState.swift
//  PostgresGUI
//
//  Created by ghazi on 12/20/25.
//

import SwiftUI

enum LoadingPhase {
    case initializingApp
    case restoringTabs
    case connectingToDatabase
    case loadingDatabases
    case loadingTables
    case ready

    var localizedText: LocalizedStringKey {
        switch self {
        case .initializingApp:      "loading.initializing"
        case .restoringTabs:        "loading.restoring_tabs"
        case .connectingToDatabase: "loading.connecting"
        case .loadingDatabases:     "loading.loading_databases"
        case .loadingTables:        "loading.loading_tables"
        case .ready:                ""
        }
    }
}

@Observable
@MainActor
class LoadingState {
    var phase: LoadingPhase = .initializingApp

    /// Set to true once initial app loading is complete
    var hasCompletedInitialLoad: Bool = false

    var isLoading: Bool {
        phase != .ready
    }

    var message: LocalizedStringKey {
        phase.localizedText
    }

    func setPhase(_ phase: LoadingPhase) {
        self.phase = phase
    }

    func setReady() {
        self.phase = .ready
        self.hasCompletedInitialLoad = true
    }
}
