//
//  MainSplitView.swift
//  PostgresGUI
//
//  Created by ghazi on 11/28/25.
//

import SwiftUI

struct MainSplitView: View {
    var body: some View {
        NavigationSplitView {
            ConnectionsDatabasesSidebar()
                .navigationSplitViewColumnWidth(
                    min: Constants.ColumnWidth.sidebarMin,
                    ideal: Constants.ColumnWidth.sidebarIdeal,
                    max: Constants.ColumnWidth.sidebarMax
                )
        } content: {
            TablesListView()
                .navigationSplitViewColumnWidth(
                    min: Constants.ColumnWidth.tablesMin,
                    ideal: Constants.ColumnWidth.tablesIdeal,
                    max: Constants.ColumnWidth.tablesMax
                )
        } detail: {
            TableContentView()
        }
    }
}
