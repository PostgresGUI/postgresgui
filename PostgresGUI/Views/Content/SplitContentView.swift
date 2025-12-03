//
//  SplitContentView.swift
//  PostgresGUI
//
//  Created by Claude on 11/29/25.
//

import SwiftUI

struct SplitContentView: View {
    @Environment(AppState.self) private var appState
    @State private var bottomPaneHeight: CGFloat = 300

    var body: some View {
        GeometryReader { geometry in
            let topHeight = max(300, geometry.size.height - bottomPaneHeight)
            
            VSplitView {
                // Top pane: Table data or query results
                topPaneView
                    .frame(minHeight: 300)
                    .frame(height: topHeight)
                    .background(
                        GeometryReader { topGeometry in
                            Color.clear
                                .preference(key: TopPaneHeightKey.self, value: topGeometry.size.height)
                        }
                    )

                // Bottom pane: Query editor - starts at 300px, resizable via VSplitView divider
                QueryEditorView()
                    .frame(minHeight: 300)
                    .frame(height: bottomPaneHeight)
                    .background(
                        GeometryReader { bottomGeometry in
                            Color.clear
                                .preference(key: BottomPaneHeightKey.self, value: bottomGeometry.size.height)
                        }
                    )
            }
            .onPreferenceChange(BottomPaneHeightKey.self) { newHeight in
                // Update state when VSplitView resizes (if it can)
                if newHeight > 0 && abs(newHeight - bottomPaneHeight) > 1 {
                    bottomPaneHeight = newHeight
                }
            }
        }
    }

    @ViewBuilder
    private var topPaneView: some View {
        if appState.isExecutingQuery {
            ProgressView()
                .scaleEffect(0.8)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if appState.showQueryResults {
            QueryResultsView()
        } else {
            ContentUnavailableView {
                Label {
                    Text("No results found")
                        .font(.title3)
                        .fontWeight(.regular)
                } icon: { }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

// Preference keys to track pane heights
struct TopPaneHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

struct BottomPaneHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}
