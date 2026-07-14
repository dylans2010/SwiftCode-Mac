import SwiftUI
import AppKit

@MainActor
public struct WorkflowBuilderView: View {
    @Binding var workflow: DeveloperWorkflow
    let project: Project
    let gitViewModel: GitViewModel
    let onRunTriggered: (DeveloperWorkflow) -> Void

    @State private var editorMode: EditorMode = .guided
    @State private var selectedCatalogCategory = "Git"
    @State private var editingStepID: UUID?
    @State private var manager = WorkflowManager.shared

    // Autocomplete list state for advanced CLI variables
    @State private var showingVariableAutocomplete = false
    @State private var cliCursorPosition = 0

    public enum EditorMode: String, CaseIterable, Identifiable {
        case guided = "Guided Builder"
        case cli = "Advanced CLI Canvas"

        public var id: String { rawValue }
    }

    public init(workflow: DeveloperWorkflow, project: Project, gitViewModel: GitViewModel, onRunTriggered: @escaping (DeveloperWorkflow) -> Void) {
        self.workflow = workflow
        self.project = project
        self.gitViewModel = gitViewModel
        self.onRunTriggered = onRunTriggered
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Editor Toolbar
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Image(systemName: workflow.icon)
                            .foregroundStyle(.blue)
                            .font(.title2)
                        Text(workflow.name)
                            .font(.title2).bold()
                    }
                    Text(workflow.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Picker("Editor Mode", selection: $editorMode) {
                    ForEach(EditorMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 280)
                .onChange(of: editorMode) { _, newValue in
                    workflow.useCLIOnly = (newValue == .cli)
                    manager.saveWorkflows()
                }

                Button(action: {
                    onRunTriggered(workflow)
                }) {
                    Label("Run Pipeline", systemImage: "play.fill")
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            // Main Editor Panels
            switch editorMode {
            case .guided:
                guidedBuilderSplitView
            case .cli:
                cliCanvasView
            }
        }
    }

    // MARK: - Guided Builder

    private var guidedBuilderSplitView: some View {
        HSplitView {
            // Catalog Preset Selection
            VStack(spacing: 0) {
                Text("Built-in Action Library")
                    .font(.headline)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Divider()

                Picker("Category", selection: $selectedCatalogCategory) {
                    Text("Git").tag("Git")
                    Text("Swift").tag("Swift")
                    Text("Xcode").tag("Xcode")
                    Text("System").tag("System")
                }
                .pickerStyle(.segmented)
                .padding(8)

                Divider()

                List {
                    let actions = catalogActions.filter { $0.category == selectedCatalogCategory }
                    ForEach(actions) { action in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Label(action.name, systemImage: action.icon)
                                    .bold()
                                Spacer()
                                Button {
                                    insertStep(action)
                                } label: {
                                    Image(systemName: "plus.circle")
                                        .font(.title3)
                                }
                                .buttonStyle(.plain)
                            }
                            Text(action.description)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .frame(minWidth: 220, idealWidth: 260, maxWidth: 320)
            .background(Color(NSColor.windowBackgroundColor))

            // Canvas Workspace Panel
            VStack(spacing: 0) {
                if workflow.steps.isEmpty {
                    ContentUnavailableView(
                        "No Pipeline Steps",
                        systemImage: "square.dashed",
                        description: Text("Choose preset actions from the library on the left to populate your visual automation flow.")
                    )
                } else {
                    List {
                        ForEach(workflow.steps.indices, id: \.self) { idx in
                            let step = workflow.steps[idx]
                            builderStepRow(at: idx, step: step)
                        }
                        .onMove(perform: moveSteps)
                        .onDelete(perform: removeSteps)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func builderStepRow(at index: Int, step: WorkflowStep) -> some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "line.3.horizontal")
                    .foregroundStyle(.secondary)
                    .padding(.trailing, 4)

                Image(systemName: step.icon)
                    .foregroundStyle(.blue)
                    .font(.title3)

                VStack(alignment: .leading, spacing: 2) {
                    Text(step.name)
                        .bold()
                    Text(step.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    if editingStepID == step.id {
                        editingStepID = nil
                    } else {
                        editingStepID = step.id
                    }
                } label: {
                    Image(systemName: "gear")
                }
                .buttonStyle(.plain)

                Button {
                    workflow.steps.remove(at: index)
                    manager.saveWorkflows()
                } label: {
                    Image(systemName: "trash")
                        .foregroundStyle(.red)
                }
                .buttonStyle(.plain)
                .padding(.leading, 8)
            }
            .padding()

            if editingStepID == step.id {
                Divider()
                stepEditorPanel(at: index)
                    .padding()
                    .background(Color(NSColor.windowBackgroundColor).opacity(0.3))
            }
        }
        .background(Color(NSColor.windowBackgroundColor))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
        )
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func stepEditorPanel(at idx: Int) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Step Details")
                .font(.subheadline).bold()

            Toggle("Is Optional (Continue workflow execution on failure)", isOn: Binding(
                get: { workflow.steps[idx].isOptional },
                set: {
                    workflow.steps[idx].isOptional = $0
                    manager.saveWorkflows()
                }
            ))

            Text("Parameters Configuration")
                .font(.caption).bold()
                .foregroundStyle(.secondary)

            let step = workflow.steps[idx]
            ForEach(step.inputs.keys.sorted(), id: \.self) { key in
                HStack {
                    Text(key.capitalized)
                        .bold()
                        .frame(width: 100, alignment: .leading)
                    TextField("Value", text: Binding(
                        get: { workflow.steps[idx].inputs[key] ?? "" },
                        set: {
                            workflow.steps[idx].inputs[key] = $0
                            manager.saveWorkflows()
                        }
                    ))
                    .textFieldStyle(.roundedBorder)
                }
            }

            if step.inputs.isEmpty {
                Text("No configurable parameters required for this action.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Advanced CLI Canvas View

    private var cliCanvasView: some View {
        VStack(spacing: 0) {
            // Header instructions & variable helper shortcuts
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Interactive Commands Workspace")
                        .font(.headline)
                    Text("Write or chain multi-line commands. Autocomplete dynamically suggests Smart Variables below.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()

                // Smart Variables Helper Button Menu
                Menu("Insert Smart Variable") {
                    Button("$(CURRENT_PROJECT)") { insertVariableText("$(CURRENT_PROJECT)") }
                    Button("$(REPOSITORY_ROOT)") { insertVariableText("$(REPOSITORY_ROOT)") }
                    Button("$(ACTIVE_BRANCH)") { insertVariableText("$(ACTIVE_BRANCH)") }
                    Button("$(BUILD_CONFIGURATION)") { insertVariableText("$(BUILD_CONFIGURATION)") }
                    Button("$(SELECTED_SIMULATOR)") { insertVariableText("$(SELECTED_SIMULATOR)") }
                }
            }
            .padding()
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            // Pseudo-Terminal Editor Area
            VStack(spacing: 0) {
                // Highlighting background container
                TextEditor(text: $workflow.customCommands)
                    .font(.system(.body, design: .monospaced))
                    .padding(10)
                    .background(Color.black.opacity(0.9))
                    .foregroundStyle(.green)
                    .scrollContentBackground(.hidden)
                    .onChange(of: workflow.customCommands) { _, _ in
                        manager.saveWorkflows()
                    }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            // Diagnostics & Variables preview footer
            VStack(alignment: .leading, spacing: 8) {
                Text("Expression Resolution Preview")
                    .font(.caption).bold()
                    .foregroundStyle(.secondary)

                let previewText = manager.resolveVariables(workflow.customCommands, project: project, gitViewModel: gitViewModel)
                ScrollView(.horizontal) {
                    Text(previewText.isEmpty ? "(Waiting for custom command inputs...)" : previewText)
                        .font(.system(.caption, design: .monospaced))
                        .padding(6)
                        .background(Color(NSColor.windowBackgroundColor).opacity(0.5))
                        .cornerRadius(4)
                }
            }
            .padding()
            .background(Color(NSColor.windowBackgroundColor))
        }
    }

    // MARK: - Step management actions

    private func insertStep(_ action: WorkflowStep) {
        var copy = action
        copy.id = UUID()
        workflow.steps.append(copy)
        manager.saveWorkflows()
    }

    private func removeSteps(at offsets: IndexSet) {
        workflow.steps.remove(atOffsets: offsets)
        manager.saveWorkflows()
    }

    private func moveSteps(from source: IndexSet, to destination: Int) {
        workflow.steps.move(fromOffsets: source, toOffset: destination)
        manager.saveWorkflows()
    }

    private func insertVariableText(_ text: String) {
        workflow.customCommands += text
        manager.saveWorkflows()
    }

    // MARK: - Preset catalog items

    private var catalogActions: [WorkflowStep] {
        [
            // Git
            WorkflowStep(name: "Pull Latest Changes", description: "git pull remote upstream updates", icon: "arrow.down.doc.fill", category: "Git", estimatedDuration: 2.0, inputs: ["rebase": "true"]),
            WorkflowStep(name: "Push Changes", description: "git push commits upstream", icon: "arrow.up.doc.fill", category: "Git", estimatedDuration: 2.0, inputs: ["force": "false"]),
            WorkflowStep(name: "Create Branch", description: "git checkout -b branch-name", icon: "arrow.triangle.branch", category: "Git", estimatedDuration: 1.0, inputs: ["branch": "feature/"]),
            WorkflowStep(name: "Checkout Branch", description: "git checkout existing-branch", icon: "arrow.triangle.branch", category: "Git", estimatedDuration: 1.0, inputs: ["branch": "main"]),
            WorkflowStep(name: "Fetch Remote", description: "git fetch tracking origin", icon: "arrow.clockwise", category: "Git", estimatedDuration: 1.5),

            // Swift
            WorkflowStep(name: "Build Project", description: "xcodebuild standard local compile", icon: "hammer.fill", category: "Swift", estimatedDuration: 10.0, inputs: ["configuration": "Debug"]),
            WorkflowStep(name: "Clean Build Folder", description: "xcodebuild clean build files", icon: "trash.fill", category: "Swift", estimatedDuration: 4.0),
            WorkflowStep(name: "Run Tests", description: "xcodebuild test runner command", icon: "play.square.fill", category: "Swift", estimatedDuration: 12.0, inputs: ["scheme": "SwiftCodeTests"]),
            WorkflowStep(name: "Resolve Packages", description: "xcodebuild -resolvePackageDependencies", icon: "shippingbox.fill", category: "Swift", estimatedDuration: 5.0),

            // Xcode
            WorkflowStep(name: "Launch Simulator", description: "Boot targeted iOS/macOS platform simulator", icon: "iphone", category: "Xcode", estimatedDuration: 3.0, inputs: ["device": "iPhone 16 Pro"]),
            WorkflowStep(name: "Select Simulator", description: "Bind project layout configuration", icon: "iphone", category: "Xcode", estimatedDuration: 1.0, inputs: ["device": "iPhone 16 Pro"]),

            // System
            WorkflowStep(name: "Open Folder", description: "Reveal files in Finder workspace", icon: "folder.fill", category: "System", estimatedDuration: 0.5, inputs: ["path": "$(REPOSITORY_ROOT)"]),
            WorkflowStep(name: "Execute Custom Script", description: "Run shell script pipeline", icon: "scroll.fill", category: "System", estimatedDuration: 2.0, inputs: ["script": "echo 'Done'"])
        ]
    }
}
