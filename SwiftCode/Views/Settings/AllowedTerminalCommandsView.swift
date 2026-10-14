import SwiftUI

/// Assist Settings > Terminal Command Approvals.
///
/// Lets the user maintain the allow-list of terminal commands that Assist's
/// `use_terminal` tool may run WITHOUT an approval prompt, plus the
/// "Full Access" master switch that bypasses approval for every command.
struct AllowedTerminalCommandsView: View {
    @ObservedObject private var approvalSettings = TerminalApprovalSettings.shared
    @State private var newCommand = ""
    @State private var showFullAccessConfirmation = false
    @State private var presetSearchText = ""
    @State private var selectedCategory = "All"

    private var categories: [String] {
        ["All"] + Array(Set(TerminalApprovalSettings.presetCommands.map { $0.category })).sorted()
    }

    private var filteredPresets: [TerminalPresetCommand] {
        TerminalApprovalSettings.presetCommands.filter { preset in
            let matchesCategory = (selectedCategory == "All" || preset.category == selectedCategory)
            let query = presetSearchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let matchesQuery = query.isEmpty ||
                preset.command.lowercased().contains(query) ||
                preset.description.lowercased().contains(query) ||
                preset.category.lowercased().contains(query)
            return matchesCategory && matchesQuery
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // 1. Full Access card
                GroupBox {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            Label("Full Access", systemImage: "key.fill")
                                .font(.headline)
                                .foregroundColor(.orange)
                            Spacer()
                            Toggle("", isOn: fullAccessBinding)
                                .toggleStyle(.switch)
                                .labelsHidden()
                        }

                        Text("When enabled, Assist may run ANY terminal command without asking for approval — in this session and every future session — until you turn it off.")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        if approvalSettings.fullAccess {
                            HStack(spacing: 8) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundColor(.orange)
                                Text("Full Access is ON. Every use_terminal call runs immediately without user prompt.")
                                    .font(.caption.bold())
                                    .foregroundColor(.orange)
                            }
                            .padding(8)
                            .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
                        }
                    }
                    .padding(14)
                }
                .groupBoxStyle(ModernGroupBoxStyle())

                // 2. Global Bulk Action Bar
                GroupBox {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Quick Actions")
                                    .font(.headline)
                                Text("Bulk add or clear terminal commands for Assist")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()

                            HStack(spacing: 10) {
                                Button {
                                    approvalSettings.addAllPresets()
                                } label: {
                                    Label("Add All (\(TerminalApprovalSettings.presetCommands.count) Presets)", systemImage: "plus.circle.fill")
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(.blue)
                                .controlSize(.small)

                                Button(role: .destructive) {
                                    approvalSettings.removeAllCommands()
                                } label: {
                                    Label("Remove All", systemImage: "trash.fill")
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                                .disabled(approvalSettings.allowedCommands.isEmpty)
                            }
                        }
                    }
                    .padding(14)
                }
                .groupBoxStyle(ModernGroupBoxStyle())

                // 3. Preset Terminal Commands card (AT LEAST 50 preset terminal commands)
                GroupBox {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            Label("Preset Terminal Commands", systemImage: "sparkles")
                                .font(.headline)
                                .foregroundColor(.purple)
                            Spacer()
                            Text("\(TerminalApprovalSettings.presetCommands.count) Presets Available")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Text("Select common developer commands to allow Assist execution without individual approval prompts.")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        // Search & Category Filters
                        HStack(spacing: 8) {
                            HStack {
                                Image(systemName: "magnifyingglass")
                                    .foregroundColor(.secondary)
                                TextField("Search presets...", text: $presetSearchText)
                                    .textFieldStyle(.plain)
                                if !presetSearchText.isEmpty {
                                    Button {
                                        presetSearchText = ""
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .foregroundColor(.secondary)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(6)
                            .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 6))

                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 6) {
                                    ForEach(categories, id: \.self) { cat in
                                        Button {
                                            selectedCategory = cat
                                        } label: {
                                            Text(cat)
                                                .font(.caption2.weight(selectedCategory == cat ? .bold : .regular))
                                                .padding(.horizontal, 8)
                                                .padding(.vertical, 4)
                                                .background(selectedCategory == cat ? Color.purple.opacity(0.18) : Color.primary.opacity(0.04), in: Capsule())
                                                .foregroundColor(selectedCategory == cat ? .purple : .primary)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                        }

                        // Presets List
                        VStack(spacing: 6) {
                            if filteredPresets.isEmpty {
                                HStack {
                                    Spacer()
                                    Text("No preset commands found matching \"\(presetSearchText)\"")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                }
                                .padding(.vertical, 12)
                            } else {
                                ScrollView {
                                    VStack(spacing: 6) {
                                        ForEach(filteredPresets) { preset in
                                            let isAdded = approvalSettings.isAllowed(command: preset.command)
                                            HStack(spacing: 12) {
                                                VStack(alignment: .leading, spacing: 2) {
                                                    HStack(spacing: 6) {
                                                        Text(preset.command)
                                                            .font(.system(.body, design: .monospaced))
                                                            .bold()

                                                        Text(preset.category)
                                                            .font(.system(size: 9, weight: .semibold))
                                                            .padding(.horizontal, 5)
                                                            .padding(.vertical, 1)
                                                            .background(Color.purple.opacity(0.12), in: Capsule())
                                                            .foregroundColor(.purple)
                                                    }

                                                    Text(preset.description)
                                                        .font(.caption2)
                                                        .foregroundStyle(.secondary)
                                                }

                                                Spacer()

                                                if isAdded {
                                                    HStack(spacing: 6) {
                                                        Label("Allowed", systemImage: "checkmark.circle.fill")
                                                            .font(.caption2.bold())
                                                            .foregroundColor(.green)

                                                        Button {
                                                            approvalSettings.removeCommand(preset.command)
                                                        } label: {
                                                            Image(systemName: "minus.circle.fill")
                                                                .foregroundColor(.red)
                                                                .font(.title3)
                                                        }
                                                        .buttonStyle(.plain)
                                                        .help("Remove \(preset.command) from allowed commands")
                                                    }
                                                } else {
                                                    Button {
                                                        approvalSettings.addCommand(preset.command)
                                                    } label: {
                                                        HStack(spacing: 4) {
                                                            Image(systemName: "plus.circle.fill")
                                                            Text("Add")
                                                        }
                                                        .font(.caption.bold())
                                                    }
                                                    .buttonStyle(.borderedProminent)
                                                    .tint(.blue)
                                                    .controlSize(.small)
                                                    .help("Add \(preset.command) to allowed commands")
                                                }
                                            }
                                            .padding(8)
                                            .background(isAdded ? Color.green.opacity(0.04) : Color.primary.opacity(0.02), in: RoundedRectangle(cornerRadius: 6))
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 6)
                                                    .stroke(isAdded ? Color.green.opacity(0.2) : Color.primary.opacity(0.05), lineWidth: 1)
                                            )
                                        }
                                    }
                                    .padding(.vertical, 2)
                                }
                                .frame(maxHeight: 260)
                            }
                        }
                    }
                    .padding(14)
                }
                .groupBoxStyle(ModernGroupBoxStyle())

                // 4. Allowed Commands card
                GroupBox {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            Label("Allowed Commands List", systemImage: "terminal.fill")
                                .font(.headline)
                                .foregroundColor(.blue)
                            Spacer()
                            Text("\(approvalSettings.allowedCommands.count) Allowed")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Text("Commands on this list always run without an approval prompt. Remove a command to require approval again.")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        // Add custom command row
                        HStack(spacing: 8) {
                            TextField("e.g. git status  —  or  git  (allows all git commands)", text: $newCommand)
                                .textFieldStyle(.roundedBorder)
                                .onSubmit(addCommand)
                            Button("Add Custom") { addCommand() }
                                .disabled(TerminalApprovalSettings.normalize(newCommand).isEmpty)
                        }

                        Divider()

                        if approvalSettings.allowedCommands.isEmpty {
                            HStack {
                                Spacer()
                                Text("No allowed commands yet. Every terminal command will ask for approval.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Spacer()
                            }
                            .padding(.vertical, 8)
                        } else {
                            VStack(spacing: 6) {
                                ScrollView {
                                    VStack(spacing: 6) {
                                        ForEach(approvalSettings.allowedCommands, id: \.self) { command in
                                            HStack {
                                                Image(systemName: "chevron.right")
                                                    .font(.caption2)
                                                    .foregroundStyle(.secondary)

                                                Text(command)
                                                    .font(.system(.body, design: .monospaced))

                                                Spacer()

                                                Button {
                                                    approvalSettings.removeCommand(command)
                                                } label: {
                                                    Image(systemName: "minus.circle.fill")
                                                        .foregroundColor(.red)
                                                        .font(.title3)
                                                }
                                                .buttonStyle(.plain)
                                                .help("Remove \(command)")
                                            }
                                            .padding(8)
                                            .background(Color.primary.opacity(0.02), in: RoundedRectangle(cornerRadius: 6))
                                        }
                                    }
                                }
                                .frame(maxHeight: 220)
                            }
                        }

                        // Matching rules footer
                        VStack(alignment: .leading, spacing: 4) {
                            Text("How matching works")
                                .font(.caption.bold())
                            Text("• A single word like git allows any command starting with that word (git status, git pull, …).")
                            Text("• A full command like git status must match exactly (ignoring extra whitespace).")
                            Text("• Build (xcodebuild) and project generation (xcodegen) tools never prompt by design and are not affected by this list.")
                        }
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    }
                    .padding(14)
                }
                .groupBoxStyle(ModernGroupBoxStyle())
            }
            .padding(24)
        }
        .navigationTitle("Terminal Command Approvals")
        .alert("Enable Full Access?", isPresented: $showFullAccessConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Enable", role: .destructive) {
                approvalSettings.fullAccess = true
            }
        } message: {
            Text("Assist will be able to run any terminal command on this Mac without asking you first, in every session until you disable this.")
        }
    }

    // MARK: - Private

    private var fullAccessBinding: Binding<Bool> {
        Binding(
            get: { approvalSettings.fullAccess },
            set: { newValue in
                if newValue {
                    showFullAccessConfirmation = true
                } else {
                    approvalSettings.fullAccess = false
                }
            }
        )
    }

    private func addCommand() {
        if approvalSettings.addCommand(newCommand) {
            newCommand = ""
        }
    }

    private func deleteCommands(at offsets: IndexSet) {
        let commands = offsets.map { approvalSettings.allowedCommands[$0] }
        for command in commands {
            approvalSettings.removeCommand(command)
        }
    }
}
