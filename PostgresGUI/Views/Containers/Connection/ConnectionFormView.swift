//
//  ConnectionFormView.swift
//  PostgresGUI
//
//  Created by ghazi on 11/28/25.
//

import SwiftUI
import SwiftData

struct ConnectionFormView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(AppState.self) private var appState
    @Environment(\.keychainService) private var keychainService

    @State private var viewModel: ConnectionFormViewModel
    @FocusState private var isNameFieldFocused: Bool

    init(connectionToEdit: ConnectionProfile? = nil) {
        // Note: appState will be injected via onAppear since we can't access @Environment in init
        _viewModel = State(initialValue: ConnectionFormViewModel(
            appState: AppState(), // Placeholder, will be replaced in onAppear
            connectionToEdit: connectionToEdit
        ))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        if viewModel.inputMode == .individual {
                            individualFieldsView
                        } else {
                            connectionStringView
                        }

                        // Connection status banner
                        if viewModel.connectionTestStatus != .idle {
                            VStack(spacing: 0) {
                                Spacer()
                                    .frame(height: 16)

                                ConnectionStatusBanner(status: viewModel.connectionTestStatus) {
                                    viewModel.connectionTestStatus = .idle
                                }
                                .padding(.leading, 132)
                            }
                        }
                    }
                    .padding(20)
                }
                .background(Color(nsColor: .controlBackgroundColor))
            }
            .onAppear {
                // Re-initialize with proper dependencies from Environment
                viewModel = ConnectionFormViewModel(
                    appState: appState,
                    keychainService: keychainService,
                    connectionToEdit: viewModel.connectionToEdit
                )
                viewModel.loadConnectionIfNeeded()
                viewModel.initializeSSLModeIfNeeded()
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .automatic) {
                    Toggle(viewModel.toggleLabel, isOn: Binding(
                        get: { viewModel.inputMode == .connectionString },
                        set: { newValue in
                            viewModel.handleInputModeChange(to: newValue ? .connectionString : .individual)
                        }
                    ))
                }

                ToolbarItem(placement: .confirmationAction) {
                    HStack {
                        Button("Test") {
                            Task {
                                await viewModel.testConnection()
                            }
                        }
                        .disabled(viewModel.isConnecting)

                        Button("Save") {
                            Task {
                                let success = await viewModel.saveConnection(modelContext: modelContext)
                                if success {
                                    dismiss()
                                }
                            }
                        }
                        .disabled(viewModel.isConnecting)
                    }
                }
            }
            .navigationTitle(viewModel.navigationTitle)
        }
        .frame(width: 500, height: 440)
        .alert("Keychain Access Denied", isPresented: $viewModel.showKeychainAlert) {
            Button("OK") {
                viewModel.showKeychainAlert = false
            }
        } message: {
            Text(viewModel.keychainAlertMessage)
        }
        .alert(
            "Connection Created",
            isPresented: $viewModel.showConnectionSavedAlert
        ) {
            Button("Not Now", role: .cancel) {
                viewModel.dismissSavedConnectionAlert()
                dismiss()
            }
            Button("Connect") {
                Task {
                    await viewModel.connectToSavedConnection()
                    dismiss()
                }
            }
        } message: {
            Text("Connect now?")
        }
    }

    // MARK: - Individual Fields View

    private var individualFieldsView: some View {
        VStack(alignment: .leading, spacing: 0) {
            nameFieldRow(
                showField: $viewModel.showIndividualNameField,
                name: $viewModel.individualName,
                focused: $isNameFieldFocused
            )

            formRow(label: "Host", alignment: .top) {
                TextEditor(text: $viewModel.host)
                    .font(.body)
                    .frame(height: 40)
                    .padding(4)
                    .background(Color(nsColor: viewModel.isEditing ? .controlBackgroundColor : .textBackgroundColor))
                    .cornerRadius(4)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
                    )
                    .onChange(of: viewModel.host) { _, newValue in
                        viewModel.handleHostChange(newValue)
                    }
            }

            formRow(label: "Port") {
                TextField("5432", text: $viewModel.port)
                    .textFieldStyle(.roundedBorder)
            }

            formRow(label: "SSL Mode") {
                HStack(spacing: 8) {
                    Picker("", selection: Binding(
                        get: { viewModel.sslModeSelection },
                        set: { viewModel.setSSLModeSelection($0) }
                    )) {
                        ForEach(SSLMode.allCases, id: \.self) { mode in
                            Text(mode.localizedKey)
                                .tag(mode)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()

                    HoverTooltipIcon(
                        systemName: "info.circle",
                        helpText: "Some servers do not support SSL/TLS. Use Disable only on trusted networks."
                    )
                }
            }

            formRow(label: "Database") {
                TextField("postgres", text: $viewModel.database)
                    .textFieldStyle(.roundedBorder)
            }

            formRow(label: "Username") {
                TextField("postgres", text: $viewModel.username)
                    .textFieldStyle(.roundedBorder)
            }

            formRow(label: "Password") {
                passwordField
            }
        }
    }

    // MARK: - Password Field

    private var passwordField: some View {
        HStack(spacing: 8) {
            Group {
                if viewModel.showPassword {
                    TextField("", text: Binding(
                        get: {
                            if viewModel.hasStoredPassword && !viewModel.passwordModified {
                                return viewModel.actualStoredPassword
                            }
                            return viewModel.password
                        },
                        set: { viewModel.handlePasswordChange($0) }
                    ))
                } else {
                    SecureField("", text: Binding(
                        get: {
                            if viewModel.hasStoredPassword && !viewModel.passwordModified {
                                return String(repeating: "•", count: 8)
                            }
                            return viewModel.password
                        },
                        set: { viewModel.handlePasswordChange($0) }
                    ))
                }
            }
            .textFieldStyle(.roundedBorder)

            Button(action: {
                if !viewModel.showPassword && viewModel.hasStoredPassword && viewModel.actualStoredPassword.isEmpty {
                    guard viewModel.loadPasswordFromKeychain() else { return }
                }
                viewModel.showPassword.toggle()
            }) {
                Image(systemName: viewModel.showPassword ? "eye.fill" : "eye.slash.fill")
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .help(viewModel.showPassword ? "Hide password" : "Show password")
        }
    }

    // MARK: - Connection String View

    private var connectionStringView: some View {
        VStack(alignment: .leading, spacing: 0) {
            nameFieldRow(
                showField: $viewModel.showConnectionStringNameField,
                name: $viewModel.connectionStringName,
                focused: $isNameFieldFocused
            )

            formRow(label: "Connection String", alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    TextEditor(text: $viewModel.connectionString)
                        .font(.system(.body, design: .monospaced))
                        .frame(height: 80)
                        .padding(4)
                        .background(Color(nsColor: viewModel.isEditing ? .controlBackgroundColor : .textBackgroundColor).opacity(viewModel.isEditing ? 0.6 : 1.0))
                        .cornerRadius(4)
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
                        )
                        .disabled(viewModel.isEditing)
                        .foregroundColor(viewModel.isEditing ? .secondary : .primary)

                    if viewModel.isEditing {
                        HStack(spacing: 6) {
                            Text("Connection string is read-only when editing")
                                .font(.caption)
                                .foregroundColor(.secondary)

                            Spacer()

                            Button(action: {
                                viewModel.copyConnectionStringToClipboard()
                            }) {
                                Label {
                                    Text(viewModel.copyButtonLabel)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                } icon: {
                                    Image(systemName: "doc.on.doc")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                            .buttonStyle(.plain)
                            .help("Copy connection string")
                        }
                    }

                }
            }
        }
    }

    // MARK: - Tooltip

    private struct HoverTooltipIcon: View {
        let systemName: String
        let helpText: LocalizedStringKey

        @State private var isHovered: Bool = false

        var body: some View {
            Image(systemName: systemName)
                .foregroundColor(.secondary)
                .contentShape(Rectangle())
                .onHover { isHovered = $0 }
                .help("")
                .popover(
                    isPresented: Binding(
                        get: { isHovered },
                        set: { newValue in
                            if !newValue {
                                isHovered = false
                            }
                        }
                    ),
                    arrowEdge: .bottom
                ) {
                    Text(helpText)
                        .lineLimit(3)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 280, alignment: .center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(8)
                }
        }
    }

    // MARK: - Helper Views

    private func nameFieldRow(showField: Binding<Bool>, name: Binding<String>, focused: FocusState<Bool>.Binding) -> some View {
        Group {
            if showField.wrappedValue {
                formRow(label: "Name") {
                    HStack(spacing: 8) {
                        TextField("", text: name)
                            .textFieldStyle(.roundedBorder)
                            .focused(focused)

                        Button(action: {
                            showField.wrappedValue = false
                            name.wrappedValue = ""
                        }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help("Remove custom name")
                    }
                }
            } else {
                formRow(label: "Name") {
                    Button(action: {
                        showField.wrappedValue = true
                        focused.wrappedValue = true
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "plus.circle.fill")
                                .foregroundColor(.secondary)
                            Text("Add Connection Name")
                                .foregroundColor(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func formRow<Content: View>(
        label: LocalizedStringKey,
        alignment: VerticalAlignment = .center,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(alignment: alignment, spacing: 12) {
            Text(label)
                .frame(width: 120, alignment: .trailing)
                .foregroundColor(.secondary)
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 6)
    }
}
