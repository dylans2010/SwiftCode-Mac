import SwiftUI

struct ToolbarCustomizationView: View {
    @StateObject private var toolbarManager = ToolbarManager.shared
    @EnvironmentObject private var toolbarSettings: ToolbarSettings
    @Environment(\.dismiss) private var dismiss
    @State private var showExtensions = false

    var body: some View {
        NavigationStack {
            List {
                // Extensions quick access
                Section {
                    Button {
                        showExtensions = true
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "puzzlepiece.extension.fill")
                                .foregroundStyle(.orange)
                                .frame(width: 24)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Manage Extensions")
                                    .font(.subheadline)
                                    .foregroundStyle(.white)
                                Text("Install, enable, or create extensions")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .buttonStyle(.plain)
                } header: {
                    Text("Extensions")
                }


                Section("Display") {
                    Toggle("Show Tool Name", isOn: $toolbarSettings.showToolNames)
                        .tint(.orange)
                    Toggle(
                        "Show Assist View",
                        isOn: Binding(
                            get: {
                                toolbarManager.tools.first(where: { $0.id == "assist_view" })?.isEnabled ?? false
                            },
                            set: { _ in
                                toolbarManager.toggleTool(id: "assist_view")
                            }
                        )
                    )
                    .tint(.orange)
                }

                Section("Enabled Tools") {
                    ForEach(toolbarManager.enabledTools) { tool in
                        toolRow(tool)
                    }
                    .onMove { from, to in
                        toolbarManager.moveTool(from: from, to: to)
                    }
                }

                Section("All Tools") {
                    ForEach(toolbarManager.tools) { tool in
                        HStack {
                            Image(systemName: tool.icon)
                                .foregroundStyle(tool.isEnabled ? .orange : .secondary)
                                .frame(width: 24)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(tool.name)
                                    .font(.subheadline)
                                    .foregroundStyle(.white)
                                Text(tool.category)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            Toggle("", isOn: Binding(
                                get: { tool.isEnabled },
                                set: { _ in toolbarManager.toggleTool(id: tool.id) }
                            ))
                            .labelsHidden()
                        }
                    }
                }

                Section {
                    Button("Reset To Defaults") {
                        toolbarManager.resetToDefaults()
                    }
                    .foregroundStyle(.red)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color(red: 0.10, green: 0.10, blue: 0.14))
            .navigationTitle("Customize Toolbar")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $showExtensions) {
                ExtensionsView()
            }
        }
    }

    private func toolRow(_ tool: ToolbarTool) -> some View {
        HStack {
            Image(systemName: tool.icon)
                .foregroundStyle(.orange)
                .frame(width: 24)
            Text(tool.name)
                .font(.subheadline)
                .foregroundStyle(.white)
            Spacer()
            Image(systemName: "line.3.horizontal")
                .foregroundStyle(.secondary)
        }
    }
}
