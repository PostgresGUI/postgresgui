//
//  RootView.swift
//  PostgresGUI
//
//  Created by ghazi on 11/28/25.
//

import SwiftUI
import SwiftData

struct RootView: View {
    @Environment(AppState.self) private var appState
    @Query private var connections: [ConnectionProfile]
    
    var body: some View {
        Group {
            if appState.isShowingWelcomeScreen && connections.isEmpty {
                WelcomeView()
            } else {
                MainSplitView()
            }
        }
        .sheet(isPresented: Binding(
            get: { appState.isShowingConnectionForm },
            set: { newValue in
                appState.isShowingConnectionForm = newValue
                if !newValue {
                    // Clear edit state when sheet is dismissed
                    appState.connectionToEdit = nil
                }
            }
        )) {
            ConnectionFormView(connectionToEdit: appState.connectionToEdit)
        }
        .sheet(isPresented: Binding(
            get: { appState.isShowingConnectionsList },
            set: { appState.isShowingConnectionsList = $0 }
        )) {
            ConnectionsListView()
        }
    }
}
