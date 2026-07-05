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
    @State private var selectedToolIDs: Set<String> = []
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

    private var availableTools: [AgentTool] { AgentTool.all }

    var body: some View {
        NavigationStack {
            Form {
                metadataSection
                capabilitiesSection
                toolInteropSection
                automationSection
                configSchemaSection
                implementationSection
            }
            .navigationTitle("Create Plugin")
            .navigationBarTitleDisplayMode(.inline)
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
    }

    private var metadataSection: some View {
        Section("Plugin Metadata") {
            TextField("Plugin Name", text: $pluginName)
            TextField("Version", text: $pluginVersion)
            TextField("Minimum SwiftCode Version", text: $minimumVersion)
            TextField("Author", text: $pluginAuthor)
            TextField("Tags (Comma Separated)", text: $tagsText)
            TextField("Description", text: $pluginDescription, axis: .vertical)
                .lineLimit(3...5)
        }
    }

    private var capabilitiesSection: some View {
        Section("Capabilities") {
            ForEach(PluginManifest.Capability.allCases, id: \.self) { capability in
                Toggle(capability.rawValue, isOn: Binding(
                    get: { selectedCapabilities.contains(capability) },
                    set: { isSelected in
                        if isSelected { selectedCapabilities.insert(capability) }
                        else { selectedCapabilities.remove(capability) }
                    }
                ))
            }
        }
    }

    private var toolInteropSection: some View {
        Section("Tool Interop") {
            ForEach(availableTools, id: \.id) { tool in
                Toggle(tool.displayName, isOn: Binding(
                    get: { selectedToolIDs.contains(tool.id) },
                    set: { isSelected in
                        if isSelected { selectedToolIDs.insert(tool.id) }
                        else { selectedToolIDs.remove(tool.id) }
                    }
                ))
            }
        }
    }

    private var automationSection: some View {
        Section("Automation Steps") {
            if automationSteps.isEmpty {
                Text("No Steps Added Yet")
                    .foregroundStyle(.secondary)
            }
            ForEach(automationSteps) { step in
                VStack(alignment: .leading, spacing: 4) {
                    Text(step.title).font(.subheadline.weight(.semibold))
                    Text(step.instruction).font(.caption).foregroundStyle(.secondary)
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
        }
    }

    private var configSchemaSection: some View {
        Section("Config Schema") {
            if configFields.isEmpty {
                Text("No Config Fields Yet")
                    .foregroundStyle(.secondary)
            }
            ForEach(configFields) { field in
                HStack {
                    VStack(alignment: .leading) {
                        Text(field.title)
                        Text("\(field.key) • \(field.type.rawValue)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(field.isRequired ? "Required" : "Optional")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
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
        }
    }

    private var implementationSection: some View {
        Section("Implementation (main.swift)") {
            TextEditor(text: $mainCode)
                .font(.system(.body, design: .monospaced))
                .frame(minHeight: 280)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.none)
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
            toolBindings: selectedToolIDs.map {
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
