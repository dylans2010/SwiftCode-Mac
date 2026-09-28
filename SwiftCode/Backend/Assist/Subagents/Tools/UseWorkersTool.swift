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
    """

    public var parametersSchema: JSONSchema {
        JSONSchema(
            type: "object",
            description: "Decomposes and schedules parallel or sequenced autonomous Workers for sub-tasks.",
            properties: [
                "workers": JSONSchema(
                    type: "array",
                    description: "List of distinct worker assignments to create and execute."
                )
            ],
            required: ["workers"]
        )
    }

    private let logger = Logger(subsystem: "com.swiftcode.app", category: "UseWorkersTool")

    public init() {}

    public func execute(input: [String: Any], context: AssistContext) async throws -> AssistToolResult {
        logger.info("Executing use_workers tool...")

        // 1. Parse JSON input (support both array of objects or serialized JSON string)
        let jsonArray: [[String: Any]]
        if let array = input["workers"] as? [[String: Any]] {
            jsonArray = array
        } else if let workersJSON = input["workers"] as? String {
            guard let data = workersJSON.data(using: .utf8),
                  let parsed = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
                return .failure("Invalid JSON format for 'workers'. Expected a JSON array of worker objects.")
            }
            jsonArray = parsed
        } else {
            return .failure("Invalid input: 'workers' argument is required and must be an array of worker objects.")
        }

        // 2. Validate assignments
        var assignments: [WorkerAssignment] = []
        var seenNames = Set<String>()

        for dict in jsonArray {
            guard let name = dict["name"] as? String, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return .failure("Validation Error: Each worker must have a non-empty 'name'.")
            }
            guard let scope = dict["scope"] as? String, !scope.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return .failure("Validation Error: Worker '\(name)' missing 'scope'.")
            }
            guard let task = dict["task"] as? String, !task.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return .failure("Validation Error: Worker '\(name)' missing 'task'.")
            }

            if task.count > 500 {
                return .failure("Validation Error: Worker '\(name)' task exceeds 500 character limit (\(task.count) chars).")
            }

            if seenNames.contains(name) {
                return .failure("Validation Error: Duplicate worker name '\(name)' detected.")
            }
            seenNames.insert(name)

            let role = dict["role"] as? String ?? "General Engineer"
            let deps = dict["dependencies"] as? [String] ?? []

            assignments.append(WorkerAssignment(
                name: name,
                scope: scope,
                task: task,
                role: role,
                dependencies: deps
            ))
        }

        guard !assignments.isEmpty else {
            return .failure("Validation Error: At least one worker assignment is required.")
        }

        // 3. Schedule and run real workers via WorkerScheduler
        let results = await WorkerScheduler.shared.scheduleAndExecute(
            assignments: assignments,
            parentTaskID: context.sessionId,
            context: context
        )

        // 4. Persist task & worker tree
        WorkerPersistenceStore.shared.persistWorkers(
            WorkerRuntimeState.shared.allWorkers,
            parentTaskID: context.sessionId
        )

        // 5. Build structured return output
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

        return .success(output)
    }
}
