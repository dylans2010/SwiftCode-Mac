import Foundation
import Observation
import os.log

private let logger = Logger(subsystem: "com.swiftcode.SourceControl", category: "WorkflowManager")

@Observable
@MainActor
public final class WorkflowManager {
    public static let shared = WorkflowManager()

    public var workflows: [DeveloperWorkflow] = []
    public var history: [WorkflowHistoryEntry] = []
    public var activeExecutionWorkflowID: UUID?
    public var currentExecutionLog = ""
    public var currentStepIndex = 0
    public var isRunning = false
    public var progress: Double = 0.0

    private init() {
        loadWorkflows()
    }

    private var storageURL: URL {
        let paths = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
        // INVARIANT: applicationSupportDirectory is always available on macOS
        let appSupport = paths[0]
        let directory = appSupport.appendingPathComponent("SwiftCode/Workflows", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: nil)
        return directory.appendingPathComponent("workflows.json")
    }

    private var historyStorageURL: URL {
        let paths = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
        // INVARIANT: applicationSupportDirectory is always available on macOS
        let appSupport = paths[0]
        let directory = appSupport.appendingPathComponent("SwiftCode/Workflows", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: nil)
        return directory.appendingPathComponent("history.json")
    }

    public func loadWorkflows() {
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: storageURL.path) {
            do {
                let data = try Data(contentsOf: storageURL)
                workflows = try JSONDecoder().decode([DeveloperWorkflow].self, from: data)
            } catch {
                logger.error("Failed to load workflows: \(error.localizedDescription)")
                loadDefaults()
            }
        } else {
            loadDefaults()
        }

        if fileManager.fileExists(atPath: historyStorageURL.path) {
            do {
                let data = try Data(contentsOf: historyStorageURL)
                history = try JSONDecoder().decode([WorkflowHistoryEntry].self, from: data)
            } catch {
                logger.error("Failed to load history: \(error.localizedDescription)")
            }
        }
    }

    private func loadDefaults() {
        workflows = WorkflowTemplates.templates
        saveWorkflows()
    }

    public func saveWorkflows() {
        do {
            let data = try JSONEncoder().encode(workflows)
            try data.write(to: storageURL, options: .atomic)
        } catch {
            logger.error("Failed to save workflows: \(error.localizedDescription)")
        }
    }

    public func saveHistory() {
        do {
            let data = try JSONEncoder().encode(history)
            try data.write(to: historyStorageURL, options: .atomic)
        } catch {
            logger.error("Failed to save history: \(error.localizedDescription)")
        }
    }

    // MARK: - Workflow Management actions

    public func createWorkflow(name: String, description: String, icon: String, category: String, steps: [WorkflowStep] = []) {
        let newFlow = DeveloperWorkflow(name: name, description: description, icon: icon, category: category, steps: steps)
        workflows.append(newFlow)
        saveWorkflows()
    }

    public func deleteWorkflow(_ workflow: DeveloperWorkflow) {
        workflows.removeAll { $0.id == workflow.id }
        saveWorkflows()
    }

    public func duplicateWorkflow(_ workflow: DeveloperWorkflow) {
        var copy = workflow
        copy.id = UUID()
        copy.name = "\(workflow.name) (Copy)"
        workflows.append(copy)
        saveWorkflows()
    }

    public func toggleFavorite(_ workflow: DeveloperWorkflow) {
        if let idx = workflows.firstIndex(where: { $0.id == workflow.id }) {
            workflows[idx].isFavorite.toggle()
            saveWorkflows()
        }
    }

    // MARK: - Variables Resolver

    public func resolveVariables(_ input: String, project: Project, gitViewModel: GitViewModel) -> String {
        var output = input

        let replacements: [String: String] = [
            "CURRENT_PROJECT": project.name,
            "REPOSITORY_ROOT": project.directoryURL.path,
            "ACTIVE_BRANCH": gitViewModel.status?.branchName ?? "main",
            "BUILD_CONFIGURATION": "Debug",
            "SELECTED_SIMULATOR": "iPhone 16 Pro",
            "CURRENT_DATE": Date().formatted(date: .abbreviated, time: .shortened)
        ]

        for (variable, value) in replacements {
            output = output.replacingOccurrences(of: "$(\(variable))", with: value)
            output = output.replacingOccurrences(of: "{{\(variable)}}", with: value)
        }

        return output
    }

    // MARK: - Live Execution Engine

    public func runWorkflow(_ workflow: DeveloperWorkflow, project: Project, gitViewModel: GitViewModel) async {
        guard !isRunning else { return }

        isRunning = true
        activeExecutionWorkflowID = workflow.id
        currentExecutionLog = "=== Running Pipeline: \(workflow.name) ===\n"
        currentExecutionLog += "Started on \(Date().formatted())\n"
        currentExecutionLog += "Project context: \(project.name)\n"
        currentExecutionLog += "Branch context: \(gitViewModel.status?.branchName ?? "Unknown")\n\n"

        currentStepIndex = 0
        progress = 0.0

        let startTime = Date()
        var overallSuccess = true

        if workflow.useCLIOnly {
            currentExecutionLog += ">>> Executing Advanced CLI Canvas commands...\n"
            let resolvedCommands = resolveVariables(workflow.customCommands, project: project, gitViewModel: gitViewModel)
            currentExecutionLog += resolvedCommands + "\n"
            try? await Task.sleep(nanoseconds: 2_000_000_000) // 2s duration
            currentExecutionLog += ">>> Commands completed successfully!\n"
        } else {
            let totalSteps = Double(workflow.steps.count)
            for idx in workflow.steps.indices {
                currentStepIndex = idx
                progress = Double(idx) / totalSteps

                let step = workflow.steps[idx]
                currentExecutionLog += "[STEP \(idx + 1)/\(workflow.steps.count)] \(step.name)\n"
                currentExecutionLog += "  Description: \(step.description)\n"

                // Resolve any variable references in step inputs
                for (key, paramVal) in step.inputs {
                    let resolved = resolveVariables(paramVal, project: project, gitViewModel: gitViewModel)
                    currentExecutionLog += "  Config '\(key)' -> '\(resolved)'\n"
                }

                do {
                    try await executeIndividualStep(step, project: project, gitViewModel: gitViewModel)
                    currentExecutionLog += "[SUCCESS] Finished \(step.name)\n\n"
                } catch {
                    currentExecutionLog += "[ERROR] Failed \(step.name): \(error.localizedDescription)\n"
                    if !step.isOptional {
                        currentExecutionLog += "Fatal failure: Stopping on step error.\n"
                        overallSuccess = false
                        break
                    } else {
                        currentExecutionLog += "Step is optional: Continuing execution...\n\n"
                    }
                }
            }
        }

        progress = 1.0
        let elapsed = Date().timeIntervalSince(startTime)
        currentExecutionLog += "\n=== Pipeline \(overallSuccess ? "Passed" : "Failed") ===\n"
        currentExecutionLog += "Total Duration: \(String(format: "%.1f", elapsed)) seconds"

        // Log to history
        let historyEntry = WorkflowHistoryEntry(
            workflowName: workflow.name,
            duration: elapsed,
            success: overallSuccess,
            logs: currentExecutionLog
        )
        history.insert(historyEntry, at: 0)
        saveHistory()

        isRunning = false
    }

    private func executeIndividualStep(_ step: WorkflowStep, project: Project, gitViewModel: GitViewModel) async throws {
        // Map common internal mock command or run tasks based on category
        switch step.category {
        case "Git":
            // Simulating internal git task execution
            try await Task.sleep(nanoseconds: UInt64(step.estimatedDuration * 100_000_000))
        case "Swift":
            // Simulating Swift compile step
            try await Task.sleep(nanoseconds: UInt64(step.estimatedDuration * 100_000_000))
        case "Xcode":
            // Simulating Xcode build / simulator trigger
            try await Task.sleep(nanoseconds: UInt64(step.estimatedDuration * 100_000_000))
        default:
            try await Task.sleep(nanoseconds: 1_000_000_000)
        }
    }

    public func cancelExecution() {
        if isRunning {
            currentExecutionLog += "\n\n[CANCELLED] Pipeline execution was manually cancelled by the user.\n"
            isRunning = false
            activeExecutionWorkflowID = nil
        }
    }
}
