import Foundation
import SwiftCodeAssistant
import SwiftCodeIDECore

/// The `use_workers` batch runtime: Legacy's validation, ported
/// exactly, plus topological ordering and durable persistence of
/// the batch plan. Execution itself is still honestly unavailable:
/// there is no LLM/subagent runtime in the MCP host (the
/// LLM-wiring family owns it), so after the plan is persisted the
/// handler fails naming the missing runtime — no worker is ever
/// claimed to have run. See `specs/ide/gap-closure-failing-tools.md` §7.
///
/// Legacy's validation (`UseWorkersTool`, verified live):
/// * input may be an array, a stringified JSON array, a single
///   object, or a `{"tasks": …}` / `{"subtasks": …}` wrapper — but
///   SwiftCode's schema validation runs before the handler, so only the
///   array form can arrive; the other forms are unreachable here
///   and are NOT reproduced (recorded in the spec).
/// * each worker needs a non-empty task; tasks are truncated to
///   500 characters (497 + "…").
/// * duplicate names are suffixed `-2`, `-3`, …; duplicate scopes
///   are suffixed with the worker name.
/// * dependencies must name workers in the same batch.
extension SwiftCodeMCPHost {
    /// One validated worker assignment.
    struct FailingToolsWorkerAssignment: Sendable, Equatable {
        var name: String
        var task: String
        var scope: String?
        var targetFiles: [String]
        var dependencies: [String]
    }

    /// A validated batch plan, ready to persist and (once a
    /// runtime exists) to execute.
    struct FailingToolsWorkerPlan: Sendable {
        var batchID: String
        var assignments: [FailingToolsWorkerAssignment]
        /// The assignments in dependency order.
        var order: [FailingToolsWorkerAssignment]
        var createdAt: Date
    }

    /// The seam a future subagent runtime plugs into: given a
    /// validated plan, run it and return one result line per
    /// worker, in execution order. Nil today — the handler fails
    /// honestly naming the missing runtime.
    protocol FailingToolsWorkerExecutor: Sendable {
        func execute(plan: FailingToolsWorkerPlan) async throws -> [String]
    }

    nonisolated(unsafe) static var workersTestExecutor: (any FailingToolsWorkerExecutor)?

    /// Legacy's exact validation over the already-decoded array
    /// form. Throws `MCPToolError` with Legacy's messages.
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

    /// Topological order by `dependencies` (a dependency runs
    /// before its dependent). Throws naming the workers in a
    /// dependency cycle.
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

    /// The batch plan file: `<workspace>/.assist_temp/workers/<batch-id>.json`.
    static func workersPlanURL(batchID: String, in s: WorkspaceSession) -> URL {
        Self.folder(of: s.model)
            .appendingPathComponent(".assist_temp").appendingPathComponent("workers")
            .appendingPathComponent("\(batchID).json")
    }

    /// Persists the plan as JSON (assignments, execution order,
    /// status, timestamps) and returns the file URL. Target-file
    /// existence is reconciled per worker: a missing target file is
    /// recorded in the plan's `missingTargetFiles` list, not an
    /// error — the plan is still written.
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

    /// `use_workers`: Legacy validation + topological order +
    /// approval + persistence, then the honest execution failure
    /// (or the test executor's results when one is installed).
    func useWorkersReal(_ call: MCPToolCall) async throws -> MCPToolResult {
        guard let workersJSON = call.arguments["workers"]?.array else {
            throw MCPToolError("Invalid input: 'workers' argument is required and must contain worker assignments.")
        }
        let assignments = try Self.workersValidate(workersJSON)
        let order = try Self.workersTopologicalOrder(assignments)
        let s = try session(for: call)
        try await terminalApproveChange(
            tool: "use_workers",
            summary: "Plan a batch of \(assignments.count) worker(s): \(order.map(\.name).joined(separator: ", ")). Workers are planned and persisted; they do not run until a subagent runtime is connected.",
            in: s, call: call)
        let plan = FailingToolsWorkerPlan(batchID: UUID().uuidString.lowercased(), assignments: assignments,
                                          order: order, createdAt: Date())
        let (url, missing) = try workersPersistPlan(plan, in: s)
        let relative = Self.relativePath(url.path, root: Self.folder(of: s.model).path)
        if let executor = Self.workersTestExecutor {
            let results = try await executor.execute(plan: plan)
            return .structured(["batchId": .string(plan.batchID), "workerCount": .int(assignments.count),
                                "planPath": .string(relative),
                                "results": .array(results.map(AnyJSON.string))],
                               summary: "Worker batch \(plan.batchID) executed (\(assignments.count) workers, plan at \(relative)):\n" + results.joined(separator: "\n"))
        }
        var summary = "Worker batch \(plan.batchID) validated and persisted to \(relative) " +
            "(\(assignments.count) workers, execution order: \(order.map(\.name).joined(separator: ", "))).\n" +
            "No worker was run: use_workers needs the Assist worker runtime (an LLM/subagent runtime), which the MCP host does not have yet. " +
            "The plan is saved so a runtime can pick it up later."
        if !missing.isEmpty {
            summary += "\nMissing target files: " + missing.map { "\($0.key): \($0.value)" }.joined(separator: "; ")
        }
        throw MCPToolError(summary)
    }
}
