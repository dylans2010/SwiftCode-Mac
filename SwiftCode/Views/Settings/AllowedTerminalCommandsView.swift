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

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Full Access card
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
                                Text("Full Access is ON. Every use_terminal call runs immediately.")
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

                // Allow-list card
                GroupBox {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            Label("Allowed Commands", systemImage: "terminal.fill")
                                .font(.headline)
                                .foregroundColor(.blue)
                            Spacer()
                            Text("\(approvalSettings.allowedCommands.count)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Text("Commands on this list always run without an approval prompt. Remove a command to require approval again.")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        // Add row
                        HStack(spacing: 8) {
                            TextField("e.g. git status  —  or  git  (allows all git commands)", text: $newCommand)
                                .textFieldStyle(.roundedBorder)
                                .onSubmit(addCommand)
                            Button("Add") { addCommand() }
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
                            List {
                                ForEach(approvalSettings.allowedCommands, id: \.self) { command in
                                    HStack {
                                        Image(systemName: "chevron.right")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                        Text(command)
                                            .font(.system(.body, design: .monospaced))
                                        Spacer()
                                    }
                                }
                                .onDelete(perform: deleteCommands)
                                .onMove(perform: approvalSettings.moveCommand)
                            }
                            .frame(minHeight: 120, maxHeight: 320)
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
