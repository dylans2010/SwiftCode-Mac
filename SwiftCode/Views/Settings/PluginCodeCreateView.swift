import SwiftUI

struct PluginCodeCreateView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var manager = PluginManager.shared

    @State private var pluginName = ""
    @State private var pluginVersion = "1.0.0"
    @State private var minimumVersion = "1.0.0"
    @State private var pluginDescription = ""
    @State private var pluginAuthor = ""
    @State private var tagsText = ""
    @State private var selectedCapabilities: Set<PluginManifest.Capability> = []
    @State private var selectedToolNames: Set<String> = []
    @State private var automationSteps: [PluginAutomationStep] = []
    @State private var configFields: [PluginConfigField] = []
    @State private var mainCode = """
import Foundation
import SwiftUI

struct AdvancedPlugin {
    func run(context: [String: Any]) {
        print("Running advanced plugin with context: \\(context)")
    }
}
"""

    private var availableTools: [any AgentTool] { Array(ListTools.shared.tools.values) }

    // Desktop Tab Selection
    enum CreateTab: String, CaseIterable, Identifiable {
        case metadata = "Metadata"
        case capabilities = "Capabilities"
        case steps = "Steps & Config"
        case code = "main.swift"

        var id: String { rawValue }

        var icon: String {
            switch self {
            case .metadata: return "doc.text.fill"
            case .capabilities: return "wrench.and.screwdriver.fill"
            case .steps: return "list.bullet.indent"
            case .code: return "curlybraces"
            }
        }
    }
    @State private var activeTab: CreateTab = .metadata

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Compact Segmented Picker for fast navigation without tall scrolling
                Picker("Section", selection: $activeTab) {
                    ForEach(CreateTab.allCases) { tab in
                        Label(tab.rawValue, systemImage: tab.icon).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .background(.ultraThinMaterial)

                Divider()

                ScrollView {
                    VStack(spacing: 16) {
                        switch activeTab {
                        case .metadata:
                            GroupBox(label: Label("Plugin Metadata", systemImage: "doc.text")) {
                                metadataSection
                            }
                            .groupBoxStyle(ModernGroupBoxStyle())

                        case .capabilities:
                            HStack(alignment: .top, spacing: 16) {
                                GroupBox(label: Label("Capabilities", systemImage: "bolt.fill")) {
                                    capabilitiesSection
                                }
                                .groupBoxStyle(ModernGroupBoxStyle())

                                GroupBox(label: Label("Tool Interop", systemImage: "wrench.and.screwdriver")) {
                                    toolInteropSection
                                }
                                .groupBoxStyle(ModernGroupBoxStyle())
                            }

                        case .steps:
                            VStack(spacing: 16) {
                                GroupBox(label: Label("Automation Steps", systemImage: "play.circle")) {
                                    automationSection
                                }
                                .groupBoxStyle(ModernGroupBoxStyle())

                                GroupBox(label: Label("Config Schema", systemImage: "slider.horizontal.3")) {
                                    configSchemaSection
                                }
                                .groupBoxStyle(ModernGroupBoxStyle())
                            }

                        case .code:
                            GroupBox(label: Label("Implementation (main.swift)", systemImage: "curlybraces")) {
                                implementationSection
                            }
                            .groupBoxStyle(ModernGroupBoxStyle())
                        }
                    }
                    .padding(24)
                }
            }
            .background(Color(NSColor.windowBackgroundColor))
            .navigationTitle("Create Plugin")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") { savePlugin() }
                        .disabled(pluginName.isEmpty || pluginAuthor.isEmpty)
                }
            }
        }
        .frame(width: 700, height: 490) // Medium-sized desktop dialog frame
    }

    private var metadataSection: some View {
        VStack(spacing: 10) {
            labeledField("Plugin Name", text: $pluginName)
            labeledField("Version", text: $pluginVersion)
            labeledField("Minimum SwiftCode Version", text: $minimumVersion)
            labeledField("Author", text: $pluginAuthor)
            labeledField("Tags (Comma Separated)", text: $tagsText)

            VStack(alignment: .leading, spacing: 4) {
                Text("Description").font(.caption).foregroundStyle(.secondary)
                TextEditor(text: $pluginDescription)
                    .frame(height: 50)
                    .cornerRadius(6)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.15)))
            }
        }
        .padding(.vertical, 6)
    }

    private var capabilitiesSection: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(PluginManifest.Capability.allCases, id: \.self) { capability in
                    Toggle(capability.rawValue, isOn: Binding(
                        get: { selectedCapabilities.contains(capability) },
                        set: { isSelected in
                            if isSelected { selectedCapabilities.insert(capability) }
                            else { selectedCapabilities.remove(capability) }
                        }
                    ))
                    .toggleStyle(.checkbox)
                }
            }
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxHeight: 180)
    }

    private var toolInteropSection: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(availableTools, id: \.name) { tool in
                    Toggle(tool.name, isOn: Binding(
                        get: { selectedToolNames.contains(tool.name) },
                        set: { isSelected in
                            if isSelected { selectedToolNames.insert(tool.name) }
                            else { selectedToolNames.remove(tool.name) }
                        }
                    ))
                    .toggleStyle(.checkbox)
                }
            }
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxHeight: 180)
    }

    private var automationSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            if automationSteps.isEmpty {
                Text("No Steps Added Yet")
                    .foregroundStyle(.secondary)
                    .font(.subheadline)
            } else {
                ForEach(automationSteps) { step in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(step.title).font(.subheadline.bold())
                        Text(step.instruction).font(.caption).foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 2)
                }
            }

            Button {
                automationSteps.append(
                    PluginAutomationStep(
                        title: "Step \(automationSteps.count + 1)",
                        instruction: "Describe what the plugin should do.",
                        expectedOutput: "Expected Result"
                    )
                )
            } label: {
                Label("Add Step", systemImage: "plus.circle.fill")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var configSchemaSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            if configFields.isEmpty {
                Text("No Config Fields Yet")
                    .foregroundStyle(.secondary)
                    .font(.subheadline)
            } else {
                ForEach(configFields) { field in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(field.title).font(.subheadline)
                            Text("\(field.key) • \(field.type.rawValue)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(field.isRequired ? "Required" : "Optional")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 2)
                }
            }

            Button {
                configFields.append(
                    PluginConfigField(
                        key: "new_field_\(configFields.count + 1)",
                        title: "New Field",
                        type: .string,
                        defaultValue: "",
                        isRequired: false
                    )
                )
            } label: {
                Label("Add Config Field", systemImage: "slider.horizontal.3")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var implementationSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            TextEditor(text: $mainCode)
                .font(.system(.body, design: .monospaced))
                .frame(height: 200)
                .cornerRadius(6)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.15)))
                .autocorrectionDisabled()
        }
        .padding(.vertical, 4)
    }

    private func labeledField(_ label: String, text: Binding<String>) -> some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(width: 180, alignment: .leading)
            TextField(label, text: text)
                .textFieldStyle(.roundedBorder)
                .autocorrectionDisabled()
        }
    }

    private func savePlugin() {
        let pluginID = pluginName.lowercased().replacingOccurrences(of: " ", with: "")
        let manifest = PluginManifest(
            id: pluginID,
            name: pluginName,
            version: pluginVersion,
            description: pluginDescription,
            author: pluginAuthor,
            entryPoint: "main.swift",
            capabilities: Array(selectedCapabilities),
            isEnabled: true,
            tags: tagsText
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty },
            minimumSwiftCodeVersion: minimumVersion,
            toolBindings: Array(selectedToolNames).map {
                PluginToolBinding(toolID: $0, usageDescription: "Linked in Create Plugin flow", isRequired: false)
            },
            automationSteps: automationSteps,
            configurationSchema: configFields
        )

        do {
            try manager.createPlugin(manifest: manifest, mainCode: mainCode)
            dismiss()
        } catch {
            print("Error saving plugin: \(error)")
        }
    }
}
