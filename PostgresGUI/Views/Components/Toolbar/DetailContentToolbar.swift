//
//  DetailContentToolbar.swift
//  PostgresGUI
//
//  Created by ghazi on 12/17/25.
//

import SwiftUI

/// Reusable toolbar for DetailContentView
/// Provides JSON viewer, edit, delete, and refresh buttons
struct DetailContentToolbar: ToolbarContent {
    @Environment(AppState.self) private var appState
    let viewModel: DetailContentViewModel

    var body: some ToolbarContent {
        ToolbarItemGroup(placement: .automatic) {
            // JSON Viewer button
            ToolbarIconButton(
                systemName: "square.and.arrow.down",
                action: { viewModel.openJSONView() },
                isDisabled: appState.query.selectedRowIDs.isEmpty,
                helpText: String(localized: "View selected rows as JSON"),
                useHoverPopover: false
            )

            // Edit button
            ToolbarIconButton(
                systemName: "square.and.pencil",
                action: { viewModel.editSelectedRows() },
                isDisabled: appState.query.selectedRowIDs.isEmpty || viewModel.isEditingDisabledDueToContextMismatch,
                helpText: viewModel.isEditingDisabledDueToContextMismatch
                    ? DetailContentViewModel.contextMismatchHelpText
                    : String(localized: "Edit selected row"),
                useHoverPopover: viewModel.isEditingDisabledDueToContextMismatch
            )

            // Delete button
            ToolbarIconButton(
                systemName: "trash",
                action: { viewModel.deleteSelectedRows() },
                isDisabled: appState.query.selectedRowIDs.isEmpty || viewModel.isEditingDisabledDueToContextMismatch,
                helpText: viewModel.isEditingDisabledDueToContextMismatch
                    ? DetailContentViewModel.contextMismatchHelpText
                    : String(localized: "Delete selected rows"),
                useHoverPopover: viewModel.isEditingDisabledDueToContextMismatch
            )
        }
    }
}

private struct ToolbarIconButton: View {
    let systemName: String
    let action: () -> Void
    let isDisabled: Bool
    let helpText: String
    let useHoverPopover: Bool

    @State private var isHovered = false

    var body: some View {
        ZStack {
            Button(action: action) {
                Image(systemName: systemName)
            }
            .disabled(isDisabled)
        }
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .help(useHoverPopover ? "" : helpText)
        .popover(
            isPresented: Binding(
                get: { useHoverPopover && isHovered },
                set: { newValue in
                    if !newValue {
                        isHovered = false
                    }
                }
            ),
            arrowEdge: .bottom
        ) {
            Text(helpText)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 280, alignment: .center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(8)
        }
    }
}
