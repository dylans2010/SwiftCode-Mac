import Foundation
import SwiftCodeAssistant
import SwiftCodeIDECore

extension SwiftCodeMCPHost {
    struct FailingToolsWorkerAssignment: Sendable, Equatable {
        var name: String
        var task: String
        var scope: String?
        var targetFiles: [String]
        var dependencies: [String]
    }

    struct FailingToolsWorkerPlan: Sendable {
        var batchID: String
        var assignments: [FailingToolsWorkerAssignment]
        var order: [FailingToolsWorkerAssignment]
        var createdAt: Date
    }

    protocol FailingToolsWorkerExecutor: Sendable {
        func execute(plan: FailingToolsWorkerPlan) async throws -> [String]
    }

    nonisolated(unsafe) static var workersTestExecutor: (any FailingToolsWorkerExecutor)?

    nonisolated static func workersValidate(_ workersJSON: [AnyJSON]) throws -> [FailingToolsWorkerAssignment] {
        var seenNames: Set<String> = []
        var seenScopes: Set<String> = []
        var assignments: [FailingToolsWorkerAssignment] = []
        for (index, workerJSON) in workersJSON.enumerated() {
            let dict = workerJSON.object ?? [:]
            let rawName = dict["name"]?.string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            var name = rawName.isEmpty ? "Worker-\(index + 1)" : rawName
            if seenNames.contains(name) {
                var suffix = 2
                while seenNames.contains("\(name)-\(suffix)") { suffix += 1 }
                name = "\(name)-\(suffix)"
            }
            seenNames.insert(name)
            var task = (dict["task"]?.string ?? dict["description"]?.string ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !task.isEmpty else {
                throw MCPToolError("Validation Error: Worker '\(name)' missing 'task' description.")
            }
            if task.count > 500 { task = String(task.prefix(497)) + "..." }
            var scope = dict["scope"]?.string?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let s = scope, !s.isEmpty {
                if seenScopes.contains(s) { scope = "\(s) (\(name))" }
                seenScopes.insert(scope ?? "")
            } else { scope = nil }
            let targetFiles = dict["targetFiles"]?.array?.compactMap(\.string) ?? []
            let dependencies = dict["dependencies"]?.array?.compactMap(\.string) ?? []
            assignments.append(FailingToolsWorkerAssignment(name: name, task: task, scope: scope,
                                                            targetFiles: targetFiles, dependencies: dependencies))
        }
        guard !assignments.isEmpty else {
            throw MCPToolError("Validation Error: At least one worker assignment is required.")
        }
        for assignment in assignments {
            for dep in assignment.dependencies {
                guard seenNames.contains(dep) else {
                    throw MCPToolError("Validation Error: Worker '\(assignment.name)' depends on unknown worker '\(dep)'. Dependencies must reference workers in the same batch.")
                }
            }
        }
        return assignments
    }

    nonisolated static func workersTopologicalOrder(_ assignments: [FailingToolsWorkerAssignment]) throws -> [FailingToolsWorkerAssignment] {
        var byName: [String: FailingToolsWorkerAssignment] = [:]
        for a in assignments { byName[a.name] = a }
        var ordered: [FailingToolsWorkerAssignment] = []
        var visiting: Set<String> = []
        var done: Set<String> = []
        func visit(_ name: String) throws {
            if done.contains(name) { return }
            guard visiting.insert(name).inserted else {
                let cycle = (visiting.sorted() + [name]).joined(separator: " -> ")
                throw MCPToolError("Validation Error: dependency cycle among workers: \(cycle).")
            }
            for dep in byName[name]?.dependencies ?? [] { try visit(dep) }
            visiting.remove(name)
            done.insert(name)
            if let a = byName[name] { ordered.append(a) }
        }
        for a in assignments { try visit(a.name) }
        return ordered
    }

    static func workersPlanURL(batchID: String, in s: WorkspaceSession) -> URL {
        Self.folder(of: s.model)
            .appendingPathComponent(".assist_temp").appendingPathComponent("workers")
            .appendingPathComponent("\(batchID).json")
    }

    func workersPersistPlan(_ plan: FailingToolsWorkerPlan, in s: WorkspaceSession) throws -> (url: URL, missingTargetFiles: [String: String]) {
        let root = Self.folder(of: s.model)
        var missing: [String: String] = [:]
        for assignment in plan.assignments {
            for target in assignment.targetFiles {
                let url = URL(fileURLWithPath: (target as NSString).expandingTildeInPath)
                let resolved = target.hasPrefix("/") ? url : root.appendingPathComponent(target)
                if !FileManager.default.fileExists(atPath: resolved.path) {
                    if let existing = missing[assignment.name] {
                        missing[assignment.name] = "\(existing), \(target)"
                    } else {
                        missing[assignment.name] = target
                    }
                }
            }
        }
        let url = Self.workersPlanURL(batchID: plan.batchID, in: s)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let iso = ISO8601DateFormatter()
        let assignmentsJSON: [[String: Any]] = plan.assignments.map { a in
            ["name": a.name, "task": a.task, "scope": a.scope as Any,
             "targetFiles": a.targetFiles, "dependencies": a.dependencies]
        }
        let planJSON: [String: Any] = [
            "batchId": plan.batchID,
            "createdAt": iso.string(from: plan.createdAt),
            "status": "planned",
            "executionOrder": plan.order.map(\.name),
            "assignments": assignmentsJSON,
            "missingTargetFiles": missing,
        ]
        let data = try JSONSerialization.data(withJSONObject: planJSON, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: url, options: [.atomic])
        return (url, missing)
    }

    func useWorkersReal(_ call: MCPToolCall) async throws -> MCPToolResult {
        guard let workersJSON = call.arguments["workers"]?.array else {
            throw MCPToolError("Invalid input: 'workers' argument is required and must contain worker assignments.")
        }
        let assignments = try Self.workersValidate(workersJSON)
        let order = try Self.workersTopologicalOrder(assignments)
        let s = try session(for: call)
        let root = Self.folder(of: s.model)
        try await terminalApproveChange(
            tool: "use_workers",
            summary: "Run a batch of \(assignments.count) worker(s): \(order.map(\.name).joined(separator: ", ")).",
            in: s, call: call)
        let plan = FailingToolsWorkerPlan(batchID: UUID().uuidString.lowercased(), assignments: assignments,
                                          order: order, createdAt: Date())
        let (url, missing) = try workersPersistPlan(plan, in: s)
        let relative = Self.relativePath(url.path, root: root.path)
        if let executor = Self.workersTestExecutor {
            let results = try await executor.execute(plan: plan)
            return .structured(["batchId": .string(plan.batchID), "workerCount": .int(assignments.count),
                                "planPath": .string(relative),
                                "results": .array(results.map(AnyJSON.string))],
                               summary: "Worker batch \(plan.batchID) executed (\(assignments.count) workers, plan at \(relative)):\n" + results.joined(separator: "\n"))
        }
        let parentTaskID = UUID(uuidString: plan.batchID) ?? UUID()
        let workerAssignments = order.map { assignment in
            WorkerAssignment(name: assignment.name,
                             scope: assignment.scope ?? "General",
                             task: assignment.task,
                             role: "General Engineer",
                             dependencies: assignment.dependencies,
                             targetFiles: assignment.targetFiles)
        }
        WorkerPersistenceStore.shared.recordAssignments(workerAssignments)
        let results = await WorkerScheduler.shared.scheduleAndExecute(
            assignments: workerAssignments,
            parentTaskID: parentTaskID,
            context: WorkerExecutionContext(sessionId: parentTaskID, workspaceRoot: root))
        WorkerPersistenceStore.shared.persistWorkers(
            WorkerRuntimeState.shared.allWorkers,
            parentTaskID: parentTaskID,
            workspaceRoot: root)
        let reconciliation = WorkerPersistenceStore.shared.reconcileWithFilesystem(workspaceRoot: root)
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
        if !missing.isEmpty {
            output += "\nMissing target files: " + missing.map { "\($0.key): \($0.value)" }.joined(separator: "; ")
        }
        var data: [String: AnyJSON] = [
            "batchId": .string(plan.batchID),
            "workerCount": .int(results.count),
            "planPath": .string(relative),
            "verifiedClaims": .int(reconciliation.verifiedClaims),
            "discrepancyCount": .int(reconciliation.discrepancies.count),
        ]
        for result in results {
            data["worker.\(result.workerName).status"] = .string(result.verificationResult)
        }
        return .structured(data, summary: output)
    }
}
