import Foundation
import os

/// The production `use_workers` tool that creates, schedules, and executes live Assist Workers (M-TOOL).
/// Fulfills SO1 and INV-11 (never an echo or simulation).
@MainActor
public struct UseWorkersTool: AssistTool {
    public let id: String = "use_workers"
    public let name: String = "Create and Coordinate Assist Workers"
    public let description: String = """
    Decomposes and schedules parallel or sequenced autonomous Workers for sub-tasks.
    Each worker must have a distinct name, non-overlapping scope, and concise task (under 500 characters).
    Workers execute real work through the Assist tool suite; results are verified against the filesystem.
    """

    public var parametersSchema: JSONSchema {
        JSONSchema(
            type: "object",
            description: "Decomposes and schedules parallel or sequenced autonomous Workers for sub-tasks.",
            properties: [
                "workers": JSONSchema(
                    type: "array",
                    description: """
                    List of distinct worker assignments. Each element is an object with:
                    - name (string, required): unique worker name.
                    - scope (string, required): explicit area of responsibility (module or directory). Must not overlap with other workers' scopes.
                    - task (string, required): concrete task description, max 500 characters.
                    - role (string, optional): e.g. "General Engineer", "Systems Architect".
                    - dependencies (array of strings, optional): names of other workers in this batch that must complete first.
                    - targetFiles (array of strings, optional): specific files this worker may modify. Must not overlap with other workers' target files.
                    """
                )
            ],
            required: ["workers"]
        )
    }

    public var capability: ToolCapability { .planning }
    public var riskLevel: ToolRiskLevel { .safeMutation }
    public var isReadOnly: Bool { false }
    public var isMutating: Bool { true }
    public var estimatedCost: Double { 0.5 }

    private let logger = Logger(subsystem: "com.swiftcode.app", category: "UseWorkersTool")

    public init() {}

    public func execute(input: [String: Any], context: AssistContext) async throws -> AssistToolResult {
        logger.info("Executing use_workers tool...")

        // 1. Resilient JSON input decoding (support array, stringified JSON, single object, top-level dict, synonyms)
        let jsonArray: [[String: Any]]
        if let array = input["workers"] as? [[String: Any]] {
            jsonArray = array
        } else if let singleDict = input["workers"] as? [String: Any] {
            jsonArray = [singleDict]
        } else if let workersJSON = (input["workers"] as? String) ?? (input["tasks"] as? String) {
            let trimmed = workersJSON.trimmingCharacters(in: .whitespacesAndNewlines)
            if let data = trimmed.data(using: .utf8) {
                if let parsedArray = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
                    jsonArray = parsedArray
                } else if let parsedDict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    if let nested = parsedDict["workers"] as? [[String: Any]] {
                        jsonArray = nested
                    } else {
                        jsonArray = [parsedDict]
                    }
                } else {
                    return .failure("Invalid JSON format for 'workers'. Expected a JSON array of worker objects.")
                }
            } else {
                return .failure("Invalid string payload for 'workers'.")
            }
        } else if let tasksArray = (input["tasks"] as? [[String: Any]]) ?? (input["subtasks"] as? [[String: Any]]) {
            jsonArray = tasksArray
        } else if input["name"] != nil && (input["task"] != nil || input["description"] != nil) {
            jsonArray = [input]
        } else {
            return .failure("Invalid input: 'workers' argument is required and must contain worker assignments.")
        }

        // 2. Validate assignments
        var assignments: [WorkerAssignment] = []
        var seenNames = Set<String>()
        var seenScopes = Set<String>()
        var seenTargetFiles = Set<String>()

        for (index, dict) in jsonArray.enumerated() {
            let rawName = (dict["name"] as? String) ?? "Worker-\(index + 1)"
            let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Worker-\(index + 1)" : rawName.trimmingCharacters(in: .whitespacesAndNewlines)

            let rawScope = (dict["scope"] as? String) ?? "General"
            var scope = rawScope.trimmingCharacters(in: .whitespacesAndNewlines)
            if scope.isEmpty { scope = "Module-\(index + 1)" }

            let rawTask = (dict["task"] as? String) ?? (dict["description"] as? String) ?? ""
            let task = rawTask.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !task.isEmpty else {
                return .failure("Validation Error: Worker '\(name)' missing 'task' description.")
            }

            let boundedTask = task.count > 500 ? String(task.prefix(497)) + "..." : task

            let uniqueName: String
            if seenNames.contains(name) {
                uniqueName = "\(name)-\(index + 1)"
            } else {
                uniqueName = name
            }
            seenNames.insert(uniqueName)

            let normalizedScope = scope.lowercased()
            let effectiveScope: String
            if seenScopes.contains(normalizedScope) {
                effectiveScope = "\(scope) (\(uniqueName))"
            } else {
                effectiveScope = scope
            }
            seenScopes.insert(effectiveScope.lowercased())

            let targetFiles = dict["targetFiles"] as? [String] ?? []
            for file in targetFiles {
                let normalizedFile = file.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                if !seenTargetFiles.contains(normalizedFile) {
                    seenTargetFiles.insert(normalizedFile)
                }
            }

            let role = dict["role"] as? String ?? "General Engineer"
            let deps = dict["dependencies"] as? [String] ?? []

            assignments.append(WorkerAssignment(
                name: uniqueName,
                scope: effectiveScope,
                task: boundedTask,
                role: role,
                dependencies: deps,
                targetFiles: targetFiles
            ))
        }

        guard !assignments.isEmpty else {
            return .failure("Validation Error: At least one worker assignment is required.")
        }

        // 3. Validate dependency references against this batch
        for assignment in assignments {
            for dep in assignment.dependencies {
                guard seenNames.contains(dep) else {
                    return .failure("Validation Error: Worker '\(assignment.name)' depends on unknown worker '\(dep)'. Dependencies must reference workers in the same batch.")
                }
            }
        }

        // 4. Schedule and run real workers via WorkerScheduler
        WorkerPersistenceStore.shared.recordAssignments(assignments)

        let results = await WorkerScheduler.shared.scheduleAndExecute(
            assignments: assignments,
            parentTaskID: context.sessionId,
            context: context
        )

        // 5. Persist task & worker tree
        WorkerPersistenceStore.shared.persistWorkers(
            WorkerRuntimeState.shared.allWorkers,
            parentTaskID: context.sessionId,
            workspaceRoot: context.workspaceRoot
        )

        // 6. Reconcile claimed file changes against the real filesystem
        let reconciliation = WorkerPersistenceStore.shared.reconcileWithFilesystem(workspaceRoot: context.workspaceRoot)

        // 7. Build structured return output
        var output = "Successfully executed \(results.count) Assist Workers under Parent Coordination:\n\n"
        for result in results {
            output += "### Worker: \(result.workerName)\n"
            output += "- Summary: \(result.summary)\n"
            output += "- Build: \(result.buildResult) | Verification: \(result.verificationResult)\n"
            if !result.modifiedFiles.isEmpty {
                output += "- Modified Files: \(result.modifiedFiles.joined(separator: ", "))\n"
            }
            if !result.completedWork.isEmpty {
                output += "- Completed Milestones: \(result.completedWork.joined(separator: "; "))\n"
            }
            output += "- Recommended Action: \(result.recommendedParentAction)\n\n"
        }
        output += "### Filesystem Reconciliation\n\(reconciliation.summary)\n"
        for discrepancy in reconciliation.discrepancies.prefix(5) {
            output += "- \(discrepancy.description)\n"
        }

        var data: [String: String] = [
            "workerCount": "\(results.count)",
            "verifiedClaims": "\(reconciliation.verifiedClaims)",
            "discrepancyCount": "\(reconciliation.discrepancies.count)"
        ]
        for result in results {
            data["worker.\(result.workerName).status"] = result.verificationResult
        }

        return .success(output, data: data)
    }
}
