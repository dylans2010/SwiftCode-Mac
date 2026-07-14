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
    @State private var catalogSearchText = ""
    @State private var editingStepID: UUID?
    @State private var manager = WorkflowManager.shared

    // Apple Shortcuts category colors
    private func categoryColor(for cat: String) -> Color {
        switch cat {
        case "Git": return .orange
        case "Swift": return .blue
        case "Xcode": return .cyan
        case "System": return .indigo
        default: return .gray
        }
    }

    public enum EditorMode: String, CaseIterable, Identifiable {
        case guided = "Guided Shortcut Builder"
        case cli = "Advanced CLI Console"

        public var id: String { rawValue }
    }

    public init(workflow: Binding<DeveloperWorkflow>, project: Project, gitViewModel: GitViewModel, onRunTriggered: @escaping (DeveloperWorkflow) -> Void) {
        self._workflow = workflow
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
                .frame(width: 320)
                .onChange(of: editorMode) { _, newValue in
                    workflow.useCLIOnly = (newValue == .cli)
                    manager.saveWorkflows()
                }

                Button(action: {
                    onRunTriggered(workflow)
                }) {
                    Label("Run Shortcut", systemImage: "play.fill")
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
            // Catalog Preset Selection (Apple Shortcuts style library)
            VStack(spacing: 0) {
                Text("Shortcuts Action Library")
                    .font(.headline)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Divider()

                // Category Selector
                HStack(spacing: 4) {
                    ForEach(["Git", "Swift", "Xcode", "System"], id: \.self) { cat in
                        Button {
                            selectedCatalogCategory = cat
                        } label: {
                            Text(cat)
                                .font(.caption.bold())
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(selectedCatalogCategory == cat ? categoryColor(for: cat).opacity(0.15) : Color.clear)
                                .foregroundStyle(selectedCatalogCategory == cat ? categoryColor(for: cat) : .secondary)
                                .cornerRadius(6)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(8)

                Divider()

                // Library Search Bar
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Search actions...", text: $catalogSearchText)
                        .textFieldStyle(.plain)
                }
                .padding(6)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(6)
                .padding(8)

                Divider()

                List {
                    let actions = catalogActions.filter {
                        $0.category == selectedCatalogCategory &&
                        (catalogSearchText.isEmpty || $0.name.localizedCaseInsensitiveContains(catalogSearchText) || $0.description.localizedCaseInsensitiveContains(catalogSearchText))
                    }
                    if actions.isEmpty {
                        Text("No matching actions")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding()
                    } else {
                        ForEach(actions) { action in
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    HStack(spacing: 6) {
                                        Image(systemName: action.icon)
                                            .foregroundStyle(categoryColor(for: action.category))
                                        Text(action.name)
                                            .font(.subheadline.bold())
                                    }
                                    Spacer()
                                    Button {
                                        insertStep(action)
                                    } label: {
                                        Image(systemName: "plus.circle.fill")
                                            .font(.title3)
                                            .foregroundStyle(categoryColor(for: action.category))
                                    }
                                    .buttonStyle(.plain)
                                }
                                Text(action.description)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                            .padding(8)
                            .background(Color(NSColor.controlBackgroundColor).opacity(0.4))
                            .cornerRadius(8)
                            .padding(.vertical, 2)
                        }
                    }
                }
            }
            .frame(minWidth: 260, idealWidth: 280, maxWidth: 340)
            .background(Color(NSColor.windowBackgroundColor))

            // Apple Shortcuts style Visual Canvas Panel
            VStack(spacing: 0) {
                // Info HUD explaining data passing
                HStack {
                    Image(systemName: "info.circle.fill")
                        .foregroundStyle(.blue)
                    Text("Apple Shortcuts Engine: Pass outputs seamlessly using **$(PREVIOUS_OUTPUT)** inside steps.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(10)
                .background(Color.blue.opacity(0.05))

                Divider()

                if workflow.steps.isEmpty {
                    ContentUnavailableView(
                        "Build Your Automation Shortcut",
                        systemImage: "wand.and.stars",
                        description: Text("Choose actions from the library on the left. Click + to stack them into an Apple Shortcuts-like workflow pipeline.")
                    )
                } else {
                    List {
                        ForEach(workflow.steps.indices, id: \.self) { idx in
                            let step = workflow.steps[idx]
                            shortcutStepBlock(at: idx, step: step)
                        }
                        .onMove(perform: moveSteps)
                        .onDelete(perform: removeSteps)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func shortcutStepBlock(at index: Int, step: WorkflowStep) -> some View {
        let catColor = categoryColor(for: step.category)

        return VStack(spacing: 0) {
            // Block Header
            HStack(spacing: 12) {
                Image(systemName: "line.3.horizontal")
                    .foregroundStyle(.secondary)
                    .cursor(.openHand)

                Image(systemName: step.icon)
                    .font(.title3)
                    .foregroundStyle(.white)
                    .frame(width: 30, height: 30)
                    .background(catColor)
                    .cornerRadius(8)

                VStack(alignment: .leading, spacing: 2) {
                    Text(step.name)
                        .font(.subheadline.bold())
                    Text(step.description)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                // Shortcuts quick config indicators
                HStack(spacing: 8) {
                    if step.isOptional {
                        Text("Ignore Failure")
                            .font(.system(size: 9, weight: .semibold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.secondary.opacity(0.1))
                            .cornerRadius(4)
                    }
                    if !step.outputVariableName.isEmpty {
                        Text("Saving output: $(\(step.outputVariableName))")
                            .font(.system(size: 9, weight: .bold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.blue.opacity(0.12))
                            .foregroundStyle(.blue)
                            .cornerRadius(4)
                    }
                }

                Button {
                    withAnimation {
                        if editingStepID == step.id {
                            editingStepID = nil
                        } else {
                            editingStepID = step.id
                        }
                    }
                } label: {
                    Image(systemName: "chevron.down")
                        .rotationEffect(.degrees(editingStepID == step.id ? 180 : 0))
                }
                .buttonStyle(.plain)

                Button {
                    workflow.steps.remove(at: index)
                    manager.saveWorkflows()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .padding(.leading, 4)
            }
            .padding(12)
            .background(Color(NSColor.controlBackgroundColor))

            // Expandable Apple Shortcuts-like editor panel
            if editingStepID == step.id {
                Divider()
                VStack(alignment: .leading, spacing: 12) {
                    Text("Parameter Bindings")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)

                    // Step specific form inputs (if any)
                    if !step.inputs.isEmpty {
                        Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 8) {
                            ForEach(step.inputs.keys.sorted(), id: \.self) { key in
                                GridRow {
                                    Text(key.capitalized)
                                        .font(.caption.bold())
                                        .frame(width: 100, alignment: .leading)

                                    TextField("Value", text: Binding(
                                        get: { workflow.steps[index].inputs[key] ?? "" },
                                        set: {
                                            workflow.steps[index].inputs[key] = $0
                                            manager.saveWorkflows()
                                        }
                                    ))
                                    .textFieldStyle(.roundedBorder)
                                }
                            }
                        }
                    }

                    Divider()

                    // Asynchronous Terminal Commands Config
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Terminal Script & Controls")
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Background Terminal Command")
                                .font(.system(size: 10, weight: .bold))
                            TextEditor(text: Binding(
                                get: { workflow.steps[index].command },
                                set: {
                                    workflow.steps[index].command = $0
                                    manager.saveWorkflows()
                                }
                            ))
                            .font(.system(.caption, design: .monospaced))
                            .frame(height: 60)
                            .cornerRadius(4)
                            .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.secondary.opacity(0.2), lineWidth: 1))
                        }

                        Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 8) {
                            GridRow {
                                Text("Working Dir")
                                    .font(.system(size: 10, weight: .bold))
                                TextField("Default to project root directory", text: Binding(
                                    get: { workflow.steps[index].workingDirectory },
                                    set: {
                                        workflow.steps[index].workingDirectory = $0
                                        manager.saveWorkflows()
                                    }
                                ))
                                .textFieldStyle(.roundedBorder)
                            }

                            GridRow {
                                Text("Env Variables")
                                    .font(.system(size: 10, weight: .bold))
                                TextField("DEBUG=1 KEY=VALUE", text: Binding(
                                    get: { workflow.steps[index].environmentVariables },
                                    set: {
                                        workflow.steps[index].environmentVariables = $0
                                        manager.saveWorkflows()
                                    }
                                ))
                                .textFieldStyle(.roundedBorder)
                            }

                            GridRow {
                                Text("Save Output As")
                                    .font(.system(size: 10, weight: .bold))
                                TextField("Save STDOUT into a custom variable name", text: Binding(
                                    get: { workflow.steps[index].outputVariableName },
                                    set: {
                                        workflow.steps[index].outputVariableName = $0
                                        manager.saveWorkflows()
                                    }
                                ))
                                .textFieldStyle(.roundedBorder)
                            }
                        }

                        HStack(spacing: 20) {
                            Toggle("Optional step (Continue on failure)", isOn: Binding(
                                get: { workflow.steps[index].isOptional },
                                set: {
                                    workflow.steps[index].isOptional = $0
                                    manager.saveWorkflows()
                                }
                            ))
                            .font(.caption)

                            HStack {
                                Text("Timeout (s):")
                                    .font(.caption)
                                TextField("", value: Binding(
                                    get: { workflow.steps[index].timeout },
                                    set: {
                                        workflow.steps[index].timeout = $0
                                        manager.saveWorkflows()
                                    }
                                ), format: .number)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 60)
                            }
                        }
                    }
                }
                .padding()
                .background(Color(NSColor.windowBackgroundColor).opacity(0.6))
            }
        }
        .background(Color(NSColor.windowBackgroundColor))
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.secondary.opacity(0.15), lineWidth: 1)
        )
        .padding(.vertical, 4)
    }

    // MARK: - Advanced CLI Canvas View

    private var cliCanvasView: some View {
        VStack(spacing: 0) {
            // Header instructions & variable helper shortcuts
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Interactive Commands Console")
                        .font(.headline)
                    Text("Write custom background shell command blocks. Use smart variable mappings below.")
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
                TextEditor(text: $workflow.customCommands)
                    .font(.system(.body, design: .monospaced))
                    .padding(10)
                    .background(Color.black.opacity(0.95))
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
            WorkflowStep(name: "Pull Latest Changes", description: "git pull remote upstream updates", icon: "arrow.down.doc.fill", category: "Git", estimatedDuration: 2.0, inputs: ["rebase": "true"], command: "git pull origin $(ACTIVE_BRANCH)"),
            WorkflowStep(name: "Push Changes", description: "git push commits upstream", icon: "arrow.up.doc.fill", category: "Git", estimatedDuration: 2.0, inputs: ["force": "false"], command: "git push origin $(ACTIVE_BRANCH)"),
            WorkflowStep(name: "Create Branch", description: "git checkout -b branch-name", icon: "arrow.triangle.branch", category: "Git", estimatedDuration: 1.0, inputs: ["branch": "feature/"], command: "git checkout -b feature-branch"),
            WorkflowStep(name: "Checkout Branch", description: "git checkout existing-branch", icon: "arrow.triangle.branch", category: "Git", estimatedDuration: 1.0, inputs: ["branch": "main"], command: "git checkout main"),
            WorkflowStep(name: "Fetch Remote", description: "git fetch tracking origin", icon: "arrow.clockwise", category: "Git", estimatedDuration: 1.5, command: "git fetch origin"),

            // Swift
            WorkflowStep(name: "Build Project", description: "swift build standard local compile", icon: "hammer.fill", category: "Swift", estimatedDuration: 10.0, inputs: ["configuration": "Debug"], command: "swift build"),
            WorkflowStep(name: "Clean Build Folder", description: "swift package clean build files", icon: "trash.fill", category: "Swift", estimatedDuration: 4.0, command: "swift package clean"),
            WorkflowStep(name: "Run Tests", description: "swift test runner command", icon: "play.square.fill", category: "Swift", estimatedDuration: 12.0, inputs: ["scheme": "SwiftCodeTests"], command: "swift test"),
            WorkflowStep(name: "Resolve Packages", description: "swift package resolve SPM dependencies", icon: "shippingbox.fill", category: "Swift", estimatedDuration: 5.0, command: "swift package resolve"),

            // Xcode
            WorkflowStep(name: "Launch Simulator", description: "Boot targeted iOS/macOS platform simulator", icon: "iphone", category: "Xcode", estimatedDuration: 3.0, inputs: ["device": "iPhone 16 Pro"], command: "xcrun simctl list devices"),
            WorkflowStep(name: "Select Simulator", description: "Bind project layout configuration", icon: "iphone", category: "Xcode", estimatedDuration: 1.0, inputs: ["device": "iPhone 16 Pro"], command: "echo 'Selecting iPhone 16 Pro'"),

            // System
            WorkflowStep(name: "Open Folder", description: "Reveal files in Finder workspace", icon: "folder.fill", category: "System", estimatedDuration: 0.5, inputs: ["path": "$(REPOSITORY_ROOT)"], command: "open ."),
            WorkflowStep(name: "Execute Custom Script", description: "Run shell script pipeline", icon: "scroll.fill", category: "System", estimatedDuration: 2.0, inputs: ["script": "echo 'Done'"], command: "echo 'Executing script...'")
        ]
    }
}
