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
    public var workflowVariables: [String: String] = [:]

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
        workflowVariables = [:]

        let startTime = Date()
        var overallSuccess = true
        var previousOutput = ""

        if workflow.useCLIOnly {
            currentExecutionLog += ">>> Executing Advanced CLI Canvas commands...\n"
            let resolvedCommands = resolveVariables(workflow.customCommands, project: project, gitViewModel: gitViewModel)

            do {
                let result = try await ProcessRunnerTool.shared.run(
                    executableURL: URL(fileURLWithPath: "/bin/sh"),
                    arguments: ["-c", resolvedCommands],
                    workingDirectory: project.directoryURL
                )
                if !result.stdout.isEmpty {
                    currentExecutionLog += result.stdout + "\n"
                }
                if !result.stderr.isEmpty {
                    currentExecutionLog += "Error:\n" + result.stderr + "\n"
                }
                if result.exitCode == 0 {
                    currentExecutionLog += ">>> Commands completed successfully!\n"
                } else {
                    currentExecutionLog += ">>> Commands failed with exit code \(result.exitCode)\n"
                    overallSuccess = false
                }
            } catch {
                currentExecutionLog += ">>> Execution failed: \(error.localizedDescription)\n"
                overallSuccess = false
            }
        } else {
            let totalSteps = Double(workflow.steps.count)
            for idx in workflow.steps.indices {
                currentStepIndex = idx
                progress = Double(idx) / totalSteps

                let step = workflow.steps[idx]
                currentExecutionLog += "[STEP \(idx + 1)/\(workflow.steps.count)] \(step.name)\n"
                currentExecutionLog += "  Description: \(step.description)\n"

                workflowVariables["PREVIOUS_OUTPUT"] = previousOutput

                do {
                    let stepOutput = try await executeIndividualStep(step, project: project, gitViewModel: gitViewModel)
                    previousOutput = stepOutput

                    let cleanVar = step.outputVariableName.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !cleanVar.isEmpty {
                        workflowVariables[cleanVar] = stepOutput
                        currentExecutionLog += "  [Saved Output to Variable: $(\(cleanVar))]\n"
                    }

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

    private func executeIndividualStep(_ step: WorkflowStep, project: Project, gitViewModel: GitViewModel) async throws -> String {
        var cmdToRun = step.command
        if cmdToRun.isEmpty {
            if let script = step.inputs["script"] {
                cmdToRun = script
            } else if let commandInput = step.inputs["command"] {
                cmdToRun = commandInput
            } else {
                cmdToRun = "echo 'No terminal command configured for step: \(step.name)'"
            }
        }

        // Resolve generic smart variables
        cmdToRun = resolveVariables(cmdToRun, project: project, gitViewModel: gitViewModel)

        // Resolve custom accumulated output variables
        for (varName, varVal) in workflowVariables {
            cmdToRun = cmdToRun.replacingOccurrences(of: "$(\(varName))", with: varVal)
            cmdToRun = cmdToRun.replacingOccurrences(of: "{{\(varName)}}", with: varVal)
        }

        var finalWorkingDir = project.directoryURL
        let cleanWorkDir = step.workingDirectory.trimmingCharacters(in: .whitespacesAndNewlines)
        if !cleanWorkDir.isEmpty {
            let resolvedDir = resolveVariables(cleanWorkDir, project: project, gitViewModel: gitViewModel)
            finalWorkingDir = URL(fileURLWithPath: resolvedDir)
        }

        var env = ProcessInfo.processInfo.environment
        let cleanEnvVars = step.environmentVariables.trimmingCharacters(in: .whitespacesAndNewlines)
        if !cleanEnvVars.isEmpty {
            let pairs = cleanEnvVars.components(separatedBy: " ")
            for pair in pairs {
                let parts = pair.components(separatedBy: "=")
                if parts.count == 2 {
                    env[parts[0]] = parts[1]
                }
            }
        }

        currentExecutionLog += "  $ \(cmdToRun)\n"

        let result = try await ProcessRunnerTool.shared.run(
            executableURL: URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-c", cmdToRun],
            environment: env,
            workingDirectory: finalWorkingDir
        )

        if !result.stdout.isEmpty {
            currentExecutionLog += result.stdout + "\n"
        }
        if !result.stderr.isEmpty {
            currentExecutionLog += "Error: " + result.stderr + "\n"
        }

        if result.exitCode != 0 {
            throw NSError(domain: "WorkflowStepError", code: Int(result.exitCode), userInfo: [NSLocalizedDescriptionKey: "Command failed with exit code \(result.exitCode)"])
        }

        return result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public func cancelExecution() {
        if isRunning {
            currentExecutionLog += "\n\n[CANCELLED] Pipeline execution was manually cancelled by the user.\n"
            isRunning = false
            activeExecutionWorkflowID = nil
        }
    }
}
