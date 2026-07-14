import SwiftUI
import AppKit
import os.log

private let logger = Logger(subsystem: "com.swiftcode.SourceControl", category: "RepositoryAutomationBuilder")

// MARK: - Automation Builder Models

public enum AutomationCategory: String, CaseIterable, Identifiable, Sendable {
    case repo = "Repository Operations"
    case github = "GitHub Operations"
    case dev = "Development Operations"
    case system = "System Operations"

    public var id: String { rawValue }

    public var icon: String {
        switch self {
        case .repo: return "arrow.triangle.branch"
        case .github: return "square.grid.2x2.fill"
        case .dev: return "hammer.fill"
        case .system: return "terminal.fill"
        }
    }
}

public enum AutomationActionType: String, CaseIterable, Identifiable, Sendable {
    // Repo
    case fetch = "Fetch"
    case pull = "Pull"
    case push = "Push"
    case checkout = "Checkout Branch"
    case commit = "Commit"
    case stash = "Stash"

    // GitHub
    case createPR = "Create Pull Request"
    case mergePR = "Merge Pull Request"
    case triggerAction = "Trigger GitHub Action"
    case createIssue = "Create Issue"

    // Dev
    case build = "Build Project"
    case test = "Run Tests"
    case format = "Format Code"
    case genDocs = "Generate Documentation"

    // System
    case runCommand = "Run Terminal Command"
    case runScript = "Execute Shell Script"
    case sendNotification = "Send Notification"

    public var id: String { rawValue }

    public var category: AutomationCategory {
        switch self {
        case .fetch, .pull, .push, .checkout, .commit, .stash:
            return .repo
        case .createPR, .mergePR, .triggerAction, .createIssue:
            return .github
        case .build, .test, .format, .genDocs:
            return .dev
        case .runCommand, .runScript, .sendNotification:
            return .system
        }
    }

    public var icon: String {
        switch self {
        case .fetch: return "arrow.down.circle"
        case .pull: return "arrow.down.doc"
        case .push: return "arrow.up.doc"
        case .checkout: return "arrow.triangle.branch"
        case .commit: return "checkmark.circle"
        case .stash: return "tray"
        case .createPR: return "arrow.triangle.pull"
        case .mergePR: return "arrow.merge"
        case .triggerAction: return "play.circle"
        case .createIssue: return "exclamationmark.bubble"
        case .build: return "hammer"
        case .test: return "play.square"
        case .format: return "wand.and.stars"
        case .genDocs: return "doc.text"
        case .runCommand: return "terminal"
        case .runScript: return "scroll"
        case .sendNotification: return "bell"
        }
    }

    public var defaultDescription: String {
        switch self {
        case .fetch: return "Fetch latest changes from remote tracking repository."
        case .pull: return "Pull and integrate latest commits into active branch."
        case .push: return "Push committed local changes to remote repository."
        case .checkout: return "Switch working copy to the specified branch or commit."
        case .commit: return "Record current staged changes into project history."
        case .stash: return "Temporarily shelf local dirty changes for later recovery."
        case .createPR: return "Open a pull request on GitHub to request branch review."
        case .mergePR: return "Merge specified Pull Request into the primary branch."
        case .triggerAction: return "Trigger an on-demand GitHub actions CI workflow."
        case .createIssue: return "Create a trackable bug or feature issue on GitHub."
        case .build: return "Compile project and build binaries locally."
        case .test: return "Execute unit test cases in active package or workspace."
        case .format: return "Run automated code formatting rules to align style."
        case .genDocs: return "Parse and export API documentation into static HTML."
        case .runCommand: return "Execute a custom shell command in sandbox environment."
        case .runScript: return "Run a custom multi-line shell script or executable."
        case .sendNotification: return "Post a native system notification of execution state."
        }
    }
}

public struct AutomationStep: Identifiable, Sendable {
    public let id = UUID()
    public var name: String
    public var type: AutomationActionType
    public var isEnabled: Bool = true
    public var stopOnFailure: Bool = true
    public var parameters: [String: String] = [:]

    // Live Execution Context (transient state, updated during runs)
    public enum RunStatus: Sendable {
        case idle
        case running
        case succeeded
        case failed(String)
    }
}

@Observable
@MainActor
public final class AutomationWorkflowStore {
    public var steps: [AutomationStep] = []
    public var isRunning = false
    public var consoleOutput = ""
    public var activeStepIndex: Int?

    public init() {
        // Pre-populate with a useful starter automation: Pull, Format, Build, Test, Notify
        steps = [
            AutomationStep(name: "Fetch Tracking Branch", type: .fetch, parameters: ["remote": "origin"]),
            AutomationStep(name: "Pull Commits", type: .pull, parameters: ["rebase": "true"]),
            AutomationStep(name: "Format Swift Code", type: .format, parameters: ["rules": "standard"]),
            AutomationStep(name: "Build binaries", type: .build, parameters: ["configuration": "Debug"]),
            AutomationStep(name: "Execute Unit Tests", type: .test, parameters: ["scheme": "SwiftCodeTests"]),
            AutomationStep(name: "Notify Success", type: .sendNotification, parameters: ["title": "Automation Completed", "message": "Pull, Format, and Build passed!"])
        ]
    }

    public func executeAll(project: Project) async {
        isRunning = true
        consoleOutput = "--- Starting Repository Automation Workflow ---\n"
        activeStepIndex = nil

        for index in steps.indices {
            guard steps[index].isEnabled else {
                appendLog("Skipping step: \(steps[index].name)")
                continue
            }

            activeStepIndex = index
            let step = steps[index]
            appendLog("\n[STARTING] Step \(index + 1)/\(steps.count): \(step.name)")

            do {
                try await runStep(step, project: project)
                appendLog("[SUCCESS] Completed: \(step.name)")
            } catch {
                appendLog("[FAILED] Error in '\(step.name)': \(error.localizedDescription)")
                if step.stopOnFailure {
                    appendLog("\n--- Workflow Terminated: Stop on Failure is active ---")
                    break
                }
            }
        }

        activeStepIndex = nil
        isRunning = false
        appendLog("\n--- Workflow Finished ---")
    }

    private func runStep(_ step: AutomationStep, project: Project) async throws {
        // Simulate real step command delays or run actual light git actions where possible
        appendLog("Executing \(step.type.rawValue)...")
        for (key, val) in step.parameters {
            appendLog("  Parameter '\(key)': \(val)")
        }

        // Simulating the actual command execution
        try await Task.sleep(nanoseconds: 800_000_000) // 0.8s
    }

    private func appendLog(_ message: String) {
        consoleOutput += message + "\n"
    }

    public func removeStep(at offsets: IndexSet) {
        steps.remove(atOffsets: offsets)
    }

    public func moveSteps(from source: IndexSet, to destination: Int) {
        steps.move(fromOffsets: source, toOffset: destination)
    }

    public func addStep(_ type: AutomationActionType) {
        var params: [String: String] = [:]
        switch type {
        case .fetch: params = ["remote": "origin"]
        case .checkout: params = ["branch": "main"]
        case .commit: params = ["message": "Automated commit"]
        case .runCommand: params = ["command": "echo 'Hello SwiftCode'"]
        case .build: params = ["configuration": "Debug"]
        default: break
        }

        let newStep = AutomationStep(
            name: type.rawValue,
            type: type,
            parameters: params
        )
        steps.append(newStep)
    }
}

// MARK: - Repository Automation Builder View

@MainActor
struct RepositoryAutomationBuilderView: View {
    let project: Project
    @State private var store = AutomationWorkflowStore()
    @State private var selectedCategory: AutomationCategory = .repo
    @State private var editingStepID: UUID?

    var body: some View {
        HSplitView {
            // Left Panel: Preset library of Actions
            VStack(spacing: 0) {
                Text("Action Catalog")
                    .font(.headline)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Divider()

                // Categories Selector
                Picker("Category", selection: $selectedCategory) {
                    ForEach(AutomationCategory.allCases) { cat in
                        Label(cat.rawValue, systemImage: cat.icon).tag(cat)
                    }
                }
                .pickerStyle(.segmented)
                .padding(8)

                Divider()

                // List of actions in category
                List {
                    let filtered = AutomationActionType.allCases.filter { $0.category == selectedCategory }
                    ForEach(filtered) { type in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Image(systemName: type.icon)
                                    .foregroundStyle(.blue)
                                Text(type.rawValue)
                                    .bold()
                                Spacer()
                                Button {
                                    store.addStep(type)
                                } label: {
                                    Image(systemName: "plus.circle.fill")
                                        .font(.title3)
                                }
                                .buttonStyle(.plain)
                            }
                            Text(type.defaultDescription)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .frame(minWidth: 260, idealWidth: 300, maxWidth: 360)
            .background(Color(NSColor.windowBackgroundColor))

            // Middle & Right: Workflow Canvas & Live Execution Log
            VSplitView {
                // Canvas Flow Area
                VStack(spacing: 0) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Visual Workflow Composer")
                                .font(.headline)
                            Text("Drag-reorder, configure parameters, and toggle conditions.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()

                        Button(action: {
                            Task {
                                await store.executeAll(project: project)
                            }
                        }) {
                            Label(store.isRunning ? "Running..." : "Run Workflow", systemImage: "play.fill")
                        }
                        .disabled(store.isRunning || store.steps.isEmpty)
                        .buttonStyle(.borderedProminent)
                    }
                    .padding()
                    .background(Color(NSColor.windowBackgroundColor))

                    Divider()

                    if store.steps.isEmpty {
                        ContentUnavailableView("Empty Workflow", systemImage: "arrow.flow.to.point", description: Text("Add steps from the action catalog on the left to compose your automation pipeline."))
                            .frame(maxHeight: .infinity)
                    } else {
                        List {
                            ForEach(store.steps.indices, id: \.self) { idx in
                                let step = store.steps[idx]
                                stepCardView(at: idx, step: step)
                            }
                            .onMove(perform: store.moveSteps)
                            .onDelete(perform: store.removeStep)
                        }
                    }
                }
                .frame(maxHeight: .infinity)

                // Log output area
                VStack(spacing: 0) {
                    HStack {
                        Label("Console Output", systemImage: "terminal")
                            .font(.headline)
                        Spacer()
                        Button("Clear Logs") {
                            store.consoleOutput = ""
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(8)
                    .background(Color(NSColor.windowBackgroundColor))

                    Divider()

                    ScrollView {
                        Text(store.consoleOutput.isEmpty ? "No active logs. Click Run Workflow to trigger execution." : store.consoleOutput)
                            .font(.system(.body, design: .monospaced))
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .background(Color.black.opacity(0.85))
                    .foregroundStyle(.green)
                }
                .frame(height: 220)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - Step Row View

    @ViewBuilder
    private func stepCardView(at index: Int, step: AutomationStep) -> some View {
        let isRunningStep = store.activeStepIndex == index
        VStack(spacing: 0) {
            HStack {
                // Drag handle placeholder
                Image(systemName: "line.3.horizontal")
                    .foregroundStyle(.secondary)
                    .padding(.trailing, 4)

                Image(systemName: step.type.icon)
                    .foregroundStyle(.blue)
                    .font(.title2)

                VStack(alignment: .leading, spacing: 2) {
                    Text(step.name)
                        .bold()
                    Text(step.type.rawValue)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                // Status Indicator
                if isRunningStep {
                    ProgressView()
                        .controlSize(.small)
                        .padding(.trailing, 8)
                }

                // Configuration expand toggle
                Button {
                    if editingStepID == step.id {
                        editingStepID = nil
                    } else {
                        editingStepID = step.id
                    }
                } label: {
                    Image(systemName: "gearshape")
                        .font(.body)
                }
                .buttonStyle(.plain)

                // Trash delete
                Button {
                    store.steps.remove(at: index)
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
                stepParametersEditor(at: index)
                    .padding()
                    .background(Color(NSColor.windowBackgroundColor).opacity(0.4))
            }
        }
        .background(Color(NSColor.windowBackgroundColor))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isRunningStep ? Color.blue : Color.secondary.opacity(0.2), lineWidth: isRunningStep ? 2 : 1)
        )
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func stepParametersEditor(at index: Int) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Step Settings")
                .font(.subheadline)
                .bold()

            Toggle("Stop Workflow on Failure", isOn: Binding(
                get: { store.steps[index].stopOnFailure },
                set: { store.steps[index].stopOnFailure = $0 }
            ))

            Text("Parameters")
                .font(.caption)
                .bold()
                .foregroundStyle(.secondary)

            // Generic customizable parameters list depending on type
            let step = store.steps[index]
            ForEach(step.parameters.keys.sorted(), id: \.self) { key in
                HStack {
                    Text(key.capitalized)
                        .bold()
                        .frame(width: 120, alignment: .leading)
                    TextField("Value", text: Binding(
                        get: { store.steps[index].parameters[key] ?? "" },
                        set: { store.steps[index].parameters[key] = $0 }
                    ))
                    .textFieldStyle(.roundedBorder)
                }
            }

            if step.parameters.isEmpty {
                Text("No configurable options for this action type.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
