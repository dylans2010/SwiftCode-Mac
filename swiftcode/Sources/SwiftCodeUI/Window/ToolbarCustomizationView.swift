// Ported from Legacy `SwiftCode/Views/Toolbar/ToolbarCustomizationView.swift` (main ab03f681; Dylan's own code, direct port authorised under MIT).
// Staged only — not yet merged into swiftcode/Sources. See staging-wire/missing/DISPOSITIONS.md.
// Verbatim except `.liquidGlass(...)` -> thinMaterial (see Adaptive notes).
// BLOCKED references (left intact):
// - ToolbarManager / ToolbarTool (Legacy `SwiftCode/Models/ToolbarItem.swift` —
//   not in the audit, no owner yet).
// - ToolbarSettings (Legacy settings type; batch 2's port is not on main).
// - SwiftCodeToolbarDelegate.presentCustomizationPalette() (the audit notes the
//   CommandTable menu item exists with no handler anywhere).
// - ExtensionsView (Legacy `Views/ExtensionsView.swift`, PARTIAL, another scope).
// Wiring: the "Customize Toolbar..." command (CommandTable) should present this
// view; it is the UI half of the toolbar-customization feature whose model half
// (ToolbarItem.swift) has no owner yet.

import SwiftUI

struct ToolbarCustomizationView: View {
    @StateObject private var toolbarManager = ToolbarManager.shared
    @EnvironmentObject private var toolbarSettings: ToolbarSettings
    @Environment(\.dismiss) private var dismiss
    @State private var showExtensions = false

    var body: some View {
        NavigationStack {
            List {
                // Native macOS NSToolbar Palette Quick Trigger
                Section {
                    Button {
                        dismiss()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                            SwiftCodeToolbarDelegate.presentCustomizationPalette()
                        }
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "macwindow.badge.plus")
                                .foregroundStyle(.blue)
                                .frame(width: 24)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Open Native macOS Toolbar Palette")
                                    .font(.subheadline.bold())
                                    .foregroundStyle(.primary)
                                Text("Drag & drop items directly using the macOS native sheet")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "arrow.up.right.square")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                } header: {
                    Text("Native Customizer")
                }

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
                                    .foregroundStyle(.primary)
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
                                    .foregroundStyle(.primary)
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
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 0, style: .continuous))
            .navigationTitle("Customize Toolbar")
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
                .foregroundStyle(.primary)
            Spacer()
            Image(systemName: "line.3.horizontal")
                .foregroundStyle(.secondary)
        }
    }
}
