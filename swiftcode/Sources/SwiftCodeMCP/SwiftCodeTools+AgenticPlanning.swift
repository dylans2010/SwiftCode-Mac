import Foundation
import SwiftCodeAssistant
import SwiftCodeIDECore

/// The ported Legacy Agentic planning & memory tool family (Wave 8,
/// slice H): 8 of the 9 Agentic tools in this slice. The ninth,
/// `ask_user`, is ALREADY-SERVED — `MCPServer.toolAliases` maps it to
/// the Wave 4 `plan-AskUser` tool (verified live), so it is not
/// registered here.
///
/// Behaviour source: Legacy's `AIContextMemoryTool`,
/// `TaskPlannerTool`, `TodoManagerTool`, `ProgressTrackerTool`,
/// `CheckpointCreatorTool`, `RollbackChangesTool`,
/// `QuestionHandlerTool` and `ChecklistPlanTool` (Dylan's own code,
/// ported under MIT), all registered in Legacy's Agentic registry
/// (`SwiftCode/Tools/Agentic/ListTools.swift:137-145`). Legacy's
/// implementations are stubs that return canned strings
/// (`"Memory \(action)ed"`, `"Step 1 for \(goal)"`, a hardcoded
/// `0.75` progress, `"Checkpoint '…' created"`, `"Awaiting user
/// response..."`); the ports below implement the behaviour those
/// strings promise, grounded in real SwiftCode state, and say so in the
/// spec draft. Nothing is faked: where a Legacy behaviour cannot be
/// honoured, the handler fails instead.
///
/// Conventions, following Waves 1–7:
///
/// * Schemas are Legacy's `schema` verbatim, plus the `workspace`
///   parameter Wave 1 adds to every tool. Legacy's Agentic schemas
///   have no titles or per-property descriptions; the descriptions
///   below are the minimal wording needed to make each argument
///   usable. Structured data keeps Legacy's keys, with typed JSON
///   values (integers, booleans, numbers) the way SwiftCode's other
///   tools do.
/// * Approval gating: every writing handler gates BEFORE touching
///   disk or host state, through `commit()` (workspace files) or
///   `approveChangeWithoutFile()` / an explicit `MCPChange` +
///   `approve()` (stores outside the workspace), exactly like the
///   Wave 2 file-writing tools and Wave 7's `project_restore`.
///   `MCPServer.run` already refuses `writes: true` tools when the
///   server is read-only; the approval call is still required.
///   There is no Autopilot bypass anywhere in this file.
/// * Workspace confinement: plans, todos and context memory are
///   filed per workspace root path, never app-global. The todo list
///   is a workspace file (`.assist_temp/memory/todos.json`, the Wave
///   4 memory-directory pattern); plans and context memory live in
///   process-lifetime stores keyed by workspace root, like Wave 4's
///   `SwiftCodeMemoryGraphStore` and `PlanningPlanStore` — they do not
///   survive a server restart. Checkpoints live outside the
///   workspace (a full-tree copy cannot live inside the tree it
///   copies) in Application Support `SwiftCodeCheckpoints/`, a store
///   deliberately separate from Wave 7's `SwiftCodeSnapshots/` — see
///   below. No second memory store is invented: `ai_context_memory`
///   reuses Wave 4's `SwiftCodeMemoryGraphStore`, and `task_planner`
///   additionally records its steps in Wave 4's
///   `PlanningPlanStore`, so `intel_breakdown_task` can break a
///   `task_planner` plan down.
///
/// Deliberate deviations from Legacy, recorded here (full detail
/// in the spec draft `specs/ide/agentic-planning-draft.md`):
///
/// * `ai_context_memory`: Legacy accepts any `action` string and
///   echoes `"Memory \(action)ed"` without doing anything. The
///   port defines the real vocabulary — `store` / `retrieve` /
///   `list` / `clear` — backed by the Wave 4 memory graph, and
///   fails unknown actions instead of echoing them. Summaries keep
///   Legacy's `"Memory \(action)ed"` shape (`"Memory stored"`,
///   `"Memory retrieved"`, `"Memory listed"`, `"Memory cleared"`).
/// * `task_planner`: Legacy returns one canned step
///   (`"Step 1 for \(goal)"`). The port splits the goal the way
///   Wave 4's `intel_plan_task` does (clauses separated by `, . ;`
///   or newlines; a generic four-step plan when the goal has no
///   clauses), mints a `planId`, and stores the plan so
///   `checklist_plan` / `progress_tracker` can work on it.
/// * `todo_manager`: Legacy returns `["Todo list updated"]`
///   without storing anything. The port keeps a real per-workspace
///   todo list (`.assist_temp/memory/todos.json`) with `add` /
///   `list` / `complete` / `remove` / `clear`. Mutations keep
///   Legacy's `"Todo list updated"` wording as their summary
///   prefix.
/// * `progress_tracker`: Legacy always returns `0.75`. The port
///   computes real progress from the slice's plan store: a plan
///   ID reports the fraction of its tasks complete
///   (`completed` = 1, `in_progress` = 0.5, `queued` / `failed` =
///   0); a task ID reports that task's own progress. An unknown
///   ID fails — no progress is invented.
/// * `checkpoint_creator` / `rollback_changes`: Legacy's pair is
///   two stubs with no store behind them, so a checkpoint that
///   captured nothing would be fake. The port gives them a real
///   store of their own: a full-tree copy per checkpoint in
///   Application Support `SwiftCodeCheckpoints/<id>/files` plus
///   `metadata.json` (the Wave 7 `project_snapshot` layout, in a
///   separate directory). `rollback_changes` restores only
///   checkpoints from that store — a `project_snapshot` ID fails
///   and names `project_restore`, and a checkpoint from another
///   workspace fails. This is NOT an alias of
///   `project_snapshot` / `project_restore`: the parameter names
///   differ (`description` / `checkpointID` vs `message` /
///   `snapshot_id`), so an alias would fail validation, and the
///   stores are separate by design.
/// * `questions_handle`: Legacy returns `"Awaiting user response
///   to question set..."` and blocks. Like Wave 4's `plan-AskUser`
///   port, this port never blocks: it returns the question set as
///   a structured pending handoff (`questionSetId`, the questions,
///   `status: "pending"`) and returns immediately. The caller
///   presents the questions and feeds answers back; the tool
///   never waits.
/// * `checklist_plan`: Legacy returns `"Checklist updated"`
///   without storing anything. The port updates the workspace's
///   current plan in the slice's plan store (creating one from the
///   given tasks when no plan exists yet), matching tasks by `id`
///   then by title, and reports the completed count and progress.
/// * `ask_user` is not ported here: the alias already exists, but
///   note the parameter mismatch recorded in the spec draft — the
///   Agentic schema (`question`, `input_type`, `options`) is not a
///   subset of `plan-AskUser`'s (`question`,
///   `allowsMultipleAnswers`, `choices`), so an Agentic caller
///   passing `input_type` / `options` fails validation. The alias
///   is Legacy's own registry alias, kept as-is; the coordinator
///   owns the alias table.
extension SwiftCodeMCPHost {
    var agenticPlanningTools: [MCPTool] {
        let safeMutation = MCPToolAnnotations(readOnly: false, idempotent: true)
        let nonIdempotentMutation = MCPToolAnnotations(readOnly: false, idempotent: false)
        let destructive = MCPToolAnnotations(readOnly: false, destructive: true)
        return [
            tool("ai_context_memory", "AI Context Memory",
                 "Manages AI context memory.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "action": Schema.string("One of 'store', 'retrieve', 'list', or 'clear'."),
                                       "data": Schema.string("Context text to store. Required when action is 'store'.")],
                                      required: ["action"]),
                 output: Schema.output(["action": Schema.str, "entries": Schema.anyArray, "count": Schema.int]),
                 annotations: nonIdempotentMutation, writes: true) { h, call in
                try await h.agenticPlanningContextMemory(call)
            },
            tool("task_planner", "Task Planner",
                 "Plans tasks to achieve a goal.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "goal": Schema.string("The goal to plan tasks for.")],
                                      required: ["goal"]),
                 output: Schema.output(["planId": Schema.str, "steps": Schema.str, "taskCount": Schema.int,
                                        "tasks": Schema.anyArray]),
                 annotations: nonIdempotentMutation, writes: true) { h, call in
                try await h.agenticPlanningTaskPlanner(call)
            },
            tool("todo_manager", "Todo Manager",
                 "Manages a todo list.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "action": Schema.string("One of 'add', 'list', 'complete', 'remove', or 'clear'."),
                                       "todo": Schema.string("Todo text. Required for 'add', 'complete', and 'remove'.")],
                                      required: ["action"]),
                 output: Schema.output(["action": Schema.str, "todos": Schema.anyArray, "count": Schema.int]),
                 annotations: nonIdempotentMutation, writes: true) { h, call in
                try await h.agenticPlanningTodoManager(call)
            },
            tool("progress_tracker", "Progress Tracker",
                 "Tracks the progress of a task.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "taskID": Schema.string("Plan ID from task_planner, or a task ID from checklist_plan.")],
                                      required: ["taskID"]),
                 output: ["type": "object",
                          "properties": .object(["taskID": Schema.str,
                                                 "progress": ["type": "number", "description": .string("Progress from 0.0 to 1.0.")],
                                                 "status": Schema.str]),
                          "required": .strings(["taskID", "progress", "status"])]) { h, call in
                try h.agenticPlanningProgressTracker(call)
            },
            tool("checkpoint_creator", "Checkpoint Creator",
                 "Creates a checkpoint of the current state.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "description": Schema.string("Label stored on the checkpoint.")],
                                      required: ["description"]),
                 output: Schema.output(["checkpoint_id": Schema.str, "description": Schema.str]),
                 annotations: nonIdempotentMutation, writes: true) { h, call in
                try await h.agenticPlanningCheckpointCreator(call)
            },
            tool("rollback_changes", "Rollback Changes",
                 "Rolls back changes to a specified checkpoint.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "checkpointID": Schema.string("Checkpoint identifier from checkpoint_creator.")],
                                      required: ["checkpointID"]),
                 output: Schema.output(["checkpoint_id": Schema.str]),
                 annotations: destructive, writes: true) { h, call in
                try await h.agenticPlanningRollbackChanges(call)
            },
            tool("questions_handle", "Handle Questions",
                 "Asks multiple clarifying questions before starting work.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "questions": Schema.array(
                                        Schema.object(["id": Schema.string("Question identifier."),
                                                       "prompt": Schema.string("The question to ask."),
                                                       "input_type": Schema.string("One of 'text' or 'selection'.", oneOf: ["text", "selection"]),
                                                       "options": Schema.array(Schema.str, "Choice labels. Required when input_type is 'selection'.")],
                                                      required: ["id", "prompt", "input_type"]),
                                        "Questions to ask the user before starting work.")],
                                      required: ["questions"]),
                 output: Schema.output(["questionSetId": Schema.str, "questions": Schema.anyArray, "status": Schema.str])) { h, call in
                try h.agenticPlanningQuestionsHandle(call)
            },
            tool("checklist_plan", "Checklist Plan",
                 "Updates the execution plan checklist.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "tasks": Schema.array(
                                        Schema.object(["id": Schema.string("Task identifier."),
                                                       "title": Schema.string("Task title."),
                                                       "status": Schema.string("One of 'queued', 'in_progress', 'completed', or 'failed'.",
                                                                               oneOf: ["queued", "in_progress", "completed", "failed"]),
                                                       "detail": Schema.string("Optional detail or note for the task.")],
                                                      required: ["id", "title", "status"]),
                                        "Tasks with their current status.")],
                                      required: ["tasks"]),
                 output: ["type": "object",
                          "properties": .object(["planId": Schema.str, "taskCount": Schema.int,
                                                 "completedCount": Schema.int,
                                                 "progress": ["type": "number", "description": .string("Fraction of tasks completed, 0.0 to 1.0.")]]),
                          "required": .strings(["planId", "taskCount", "completedCount", "progress"])],
                 annotations: safeMutation, writes: true) { h, call in
                try await h.agenticPlanningChecklistPlan(call)
            },
        ]
    }
}

/// One checklist task in an Agentic plan, mirroring Legacy's
/// `ChecklistPlanTool` task object (`id`, `title`, `status`,
/// `detail`).
struct AgenticPlanningTask: Codable, Sendable, Equatable {
    var id: String
    var title: String
    var status: String
    var detail: String

    init(id: String, title: String, status: String, detail: String = "") {
        self.id = id
        self.title = title
        self.status = status
        self.detail = detail
    }

    /// Legacy's status weight, as used by `progress_tracker`:
    /// `completed` counts fully, `in_progress` half, `queued` and
    /// `failed` nothing.
    var progressWeight: Double {
        switch status {
        case "completed": return 1.0
        case "in_progress": return 0.5
        default: return 0.0
        }
    }
}

/// One plan created by `task_planner` (or implicitly by
/// `checklist_plan`): a goal plus its checklist tasks.
struct AgenticPlanningPlan: Codable, Sendable, Equatable {
    var id: String
    var goal: String
    var tasks: [AgenticPlanningTask]
    var createdAt: Date

    /// Fraction of tasks complete, by status weight.
    var progress: Double {
        guard !tasks.isEmpty else { return 0.0 }
        return tasks.map(\.progressWeight).reduce(0.0, +) / Double(tasks.count)
    }

    /// The plan's overall status, derived from its tasks.
    var status: String {
        if tasks.isEmpty { return "queued" }
        if tasks.allSatisfy({ $0.status == "completed" }) { return "completed" }
        if tasks.contains(where: { $0.status == "completed" || $0.status == "in_progress" }) { return "in_progress" }
        return "queued"
    }
}

/// One process-lifetime plan store per workspace, mirroring Wave 4's
/// `PlanningPlanStore` shape (NSLock + dictionary, never persisted)
/// but holding structured plans instead of step strings, so
/// `checklist_plan` can update task statuses and `progress_tracker`
/// can compute real progress. Plans do not survive a server restart.
final class AgenticPlanningPlanStore: @unchecked Sendable {
    static let shared = AgenticPlanningPlanStore()

    private let lock = NSLock()
    private var plans: [String: [String: AgenticPlanningPlan]] = [:]
    private var currentPlanIDs: [String: String] = [:]

    private init() {}

    /// Creates a plan, makes it the workspace's current plan, and
    /// returns it.
    func create(workspace: String, goal: String, tasks: [AgenticPlanningTask]) -> AgenticPlanningPlan {
        lock.withLock {
            let plan = AgenticPlanningPlan(id: UUID().uuidString, goal: goal, tasks: tasks, createdAt: Date())
            plans[workspace, default: [:]][plan.id] = plan
            currentPlanIDs[workspace] = plan.id
            return plan
        }
    }

    func plan(workspace: String, id: String) -> AgenticPlanningPlan? {
        lock.withLock { plans[workspace]?[id] }
    }

    /// The workspace's most recently created plan, if any.
    func currentPlan(workspace: String) -> AgenticPlanningPlan? {
        lock.withLock {
            guard let id = currentPlanIDs[workspace] else { return nil }
            return plans[workspace]?[id]
        }
    }

    /// Every plan of the workspace, oldest first (gap closure:
    /// `session_progress_report` aggregates across plans).
    func plans(workspace: String) -> [AgenticPlanningPlan] {
        lock.withLock { (plans[workspace] ?? [:]).values.sorted { $0.createdAt < $1.createdAt } }
    }

    func update(workspace: String, plan: AgenticPlanningPlan) {
        lock.withLock { plans[workspace, default: [:]][plan.id] = plan }
    }

    /// Finds a single task by ID anywhere in the workspace's plans.
    func task(workspace: String, id: String) -> (AgenticPlanningPlan, AgenticPlanningTask)? {
        lock.withLock {
            guard let workspacePlans = plans[workspace] else { return nil }
            for plan in workspacePlans.values {
                if let task = plan.tasks.first(where: { $0.id == id }) { return (plan, task) }
            }
            return nil
        }
    }
}

/// One todo-list item, persisted in the workspace's
/// `.assist_temp/memory/todos.json`.
struct AgenticPlanningTodo: Codable, Sendable, Equatable {
    var text: String
    var completed: Bool
    var createdAt: Date
}

extension SwiftCodeMCPHost {
    /// The checkpoint store: Application Support `SwiftCodeCheckpoints/`
    /// (the Wave 7 `project_snapshot` layout — one directory per
    /// checkpoint holding a full-tree `files/` copy plus
    /// `metadata.json` — in a directory of its own, so checkpoints
    /// and project snapshots can never be confused).
    nonisolated static func agenticPlanningCheckpointsDirectory() throws -> URL {
        let appSupport = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let dir = appSupport.appendingPathComponent("SwiftCodeCheckpoints", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    /// `<workspace>/.assist_temp/memory/todos.json`.
    func agenticPlanningTodosURL(in s: WorkspaceSession) -> URL {
        memoryDirectory(in: s).appendingPathComponent("todos.json")
    }

    /// The todo list, parsed from the workspace file (empty when the
    /// file does not exist yet; an unparsable file also reads as
    /// empty, like Wave 4's context store).
    func agenticPlanningLoadTodos(in s: WorkspaceSession) -> [AgenticPlanningTodo] {
        guard let text = text(of: agenticPlanningTodosURL(in: s)),
              let data = text.data(using: .utf8) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([AgenticPlanningTodo].self, from: data)) ?? []
    }

    /// The todo list rendered as pretty-printed, sorted-key JSON.
    nonisolated static func agenticPlanningRenderTodos(_ todos: [AgenticPlanningTodo]) -> String {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(todos), let text = String(data: data, encoding: .utf8) { return text }
        return "[]"
    }

    /// The JSON form of one todo, for structured results.
    nonisolated static func agenticPlanningTodoJSON(_ todo: AgenticPlanningTodo) -> AnyJSON {
        ["text": .string(todo.text), "completed": .bool(todo.completed),
         "createdAt": .string(ISO8601DateFormatter().string(from: todo.createdAt))]
    }

    /// Splits a goal into plan steps the way Wave 4's
    /// `intel_plan_task` does: clauses separated by `, . ;` or
    /// newlines, numbered; a generic four-step plan when the goal
    /// has no clauses.
    nonisolated static func agenticPlanningSplitGoal(_ goal: String) -> [String] {
        let verbs = goal
            .components(separatedBy: CharacterSet(charactersIn: ",.;\n"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if verbs.isEmpty {
            return ["Analyze requirements", "Implement changes", "Validate with tests", "Summarize outputs"]
        }
        return verbs.enumerated().map { "\($0.offset + 1). \($0.element)" }
    }

    /// The context-memory entries for a workspace, held in Wave 4's
    /// memory graph under the `ai_context_memory` key as a JSON
    /// array (a legacy newline-joined value still parses).
    func agenticPlanningContextEntries(in s: WorkspaceSession) -> [String] {
        guard let raw = SwiftCodeMemoryGraphStore.shared.retrieve(workspace: memoryWorkspaceKey(in: s), key: "ai_context_memory"),
              !raw.isEmpty else { return [] }
        if let data = raw.data(using: .utf8),
           let entries = try? JSONSerialization.jsonObject(with: data) as? [String] {
            return entries
        }
        return raw.components(separatedBy: .newlines).filter { !$0.isEmpty }
    }

    func agenticPlanningStoreContextEntries(_ entries: [String], in s: WorkspaceSession) {
        let data = (try? JSONSerialization.data(withJSONObject: entries)) ?? Data("[]".utf8)
        SwiftCodeMemoryGraphStore.shared.store(workspace: memoryWorkspaceKey(in: s), key: "ai_context_memory",
                                           value: String(data: data, encoding: .utf8) ?? "[]")
    }

    // MARK: - Context memory

    func agenticPlanningContextMemory(_ call: MCPToolCall) async throws -> MCPToolResult {
        let s = try session(for: call)
        guard let action = call.string("action")?.lowercased() else {
            throw MCPToolError("Missing required parameter: action ('store', 'retrieve', 'list', or 'clear')")
        }
        var entries = agenticPlanningContextEntries(in: s)
        let summary: String
        switch action {
        case "store":
            guard let data = call.string("data") else {
                throw MCPToolError("Action 'store' requires 'data'.")
            }
            entries.append(data)
            agenticPlanningStoreContextEntries(entries, in: s)
            summary = "Memory stored"
        case "retrieve", "list":
            // Legacy's "Memory \(action)ed" shape: retrieve ->
            // "Memory retrieved", list -> "Memory listed".
            summary = action == "retrieve" ? "Memory retrieved" : "Memory listed"
        case "clear":
            agenticPlanningStoreContextEntries([], in: s)
            entries = []
            summary = "Memory cleared"
        default:
            throw MCPToolError("Unknown action '\(action)'. Supported actions: store, retrieve, list, clear.")
        }
        return .structured(["action": .string(action), "entries": .array(entries.map(AnyJSON.string)),
                            "count": .int(entries.count)], summary: summary)
    }

    // MARK: - Task planner

    func agenticPlanningTaskPlanner(_ call: MCPToolCall) async throws -> MCPToolResult {
        let s = try session(for: call)
        let goal = try call.require("goal")
        guard !goal.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw MCPToolError("Missing required parameter: goal")
        }
        let steps = Self.agenticPlanningSplitGoal(goal)
        let tasks = steps.map { AgenticPlanningTask(id: UUID().uuidString, title: $0, status: "queued") }
        let plan = AgenticPlanningPlanStore.shared.create(workspace: memoryWorkspaceKey(in: s), goal: goal, tasks: tasks)
        // Wave 4 interop: record the steps where
        // `intel_breakdown_task` looks for them.
        PlanningPlanStore.shared.store(key: "plan:\(plan.id)", value: steps.joined(separator: "\n"))
        let stepsText = steps.joined(separator: "\n")
        let taskJSON: [AnyJSON] = tasks.map { ["id": .string($0.id), "title": .string($0.title), "status": .string($0.status)] }
        return .structured(["planId": .string(plan.id), "steps": .string(stepsText), "taskCount": .int(tasks.count),
                            "tasks": .array(taskJSON)],
                           summary: "Plan generated for goal: \(goal)")
    }

    // MARK: - Todo manager

    func agenticPlanningTodoManager(_ call: MCPToolCall) async throws -> MCPToolResult {
        let s = try session(for: call)
        guard let action = call.string("action")?.lowercased() else {
            throw MCPToolError("Missing required parameter: action ('add', 'list', 'complete', 'remove', or 'clear')")
        }
        let url = agenticPlanningTodosURL(in: s)
        var todos = agenticPlanningLoadTodos(in: s)
        let summary: String
        switch action {
        case "add":
            guard let todo = call.string("todo") else {
                throw MCPToolError("Action 'add' requires 'todo'.")
            }
            todos.append(AgenticPlanningTodo(text: todo, completed: false, createdAt: Date()))
            try await commit(MCPChange(tool: call.name, path: url.path, relativePath: ".assist_temp/memory/todos.json",
                                       original: text(of: url), proposed: Self.agenticPlanningRenderTodos(todos),
                                       summary: "Add todo '\(todo)'"), call: call, session: s)
            summary = "Todo list updated: added \"\(todo)\""
        case "list":
            if todos.isEmpty { return .structured(["action": .string("list"), "todos": .array([]), "count": .int(0)],
                                                  summary: "Todo list is empty.") }
            let lines = todos.enumerated().map { $0.element.completed ? "[x] \($0.element.text)" : "[ ] \($0.element.text)" }
            return .structured(["action": .string("list"),
                                "todos": .array(todos.map(Self.agenticPlanningTodoJSON)),
                                "count": .int(todos.count)],
                               summary: "Todo list (\(todos.count) items):\n" + lines.joined(separator: "\n"))
        case "complete", "remove":
            guard let todo = call.string("todo") else {
                throw MCPToolError("Action '\(action)' requires 'todo'.")
            }
            guard let idx = todos.firstIndex(where: { $0.text == todo })
                    ?? todos.firstIndex(where: { $0.text.caseInsensitiveCompare(todo) == .orderedSame }) else {
                throw MCPToolError("Todo '\(todo)' was not found in the todo list.")
            }
            if action == "complete" {
                todos[idx].completed = true
                summary = "Todo list updated: completed \"\(todos[idx].text)\""
            } else {
                let removed = todos.remove(at: idx)
                summary = "Todo list updated: removed \"\(removed.text)\""
            }
            try await commit(MCPChange(tool: call.name, path: url.path, relativePath: ".assist_temp/memory/todos.json",
                                       original: text(of: url), proposed: Self.agenticPlanningRenderTodos(todos),
                                       summary: summary), call: call, session: s)
        case "clear":
            todos = []
            try await commit(MCPChange(tool: call.name, path: url.path, relativePath: ".assist_temp/memory/todos.json",
                                       original: text(of: url), proposed: Self.agenticPlanningRenderTodos(todos),
                                       summary: "Clear todo list"), call: call, session: s)
            summary = "Todo list cleared."
        default:
            throw MCPToolError("Unknown action '\(action)'. Supported actions: add, list, complete, remove, clear.")
        }
        return .structured(["action": .string(action),
                            "todos": .array(todos.map(Self.agenticPlanningTodoJSON)),
                            "count": .int(todos.count)], summary: summary)
    }

    // MARK: - Progress tracker

    func agenticPlanningProgressTracker(_ call: MCPToolCall) throws -> MCPToolResult {
        let s = try session(for: call)
        let taskID = try call.require("taskID")
        guard !taskID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw MCPToolError("Missing required parameter: taskID")
        }
        let workspace = memoryWorkspaceKey(in: s)
        let progress: Double
        let status: String
        if let plan = AgenticPlanningPlanStore.shared.plan(workspace: workspace, id: taskID) {
            progress = plan.progress
            status = plan.status
        } else if let (_, task) = AgenticPlanningPlanStore.shared.task(workspace: workspace, id: taskID) {
            progress = task.progressWeight
            status = task.status
        } else {
            throw MCPToolError("No task or plan found with ID '\(taskID)'. Use a planId from task_planner or a task ID from checklist_plan.")
        }
        return .structured(["taskID": .string(taskID), "progress": .double(progress), "status": .string(status)],
                           summary: "Progress for \(taskID): \(progress * 100)%")
    }

    // MARK: - Checkpoints

    func agenticPlanningCheckpointCreator(_ call: MCPToolCall) async throws -> MCPToolResult {
        let s = try session(for: call)
        let root = Self.folder(of: s.model)
        let description = try call.require("description")
        guard !description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw MCPToolError("Missing required parameter: description")
        }
        try await approveChangeWithoutFile(tool: call.name,
                                           summary: "Create checkpoint '\(description)' — full copy of the workspace into the checkpoint store",
                                           call: call)
        let checkpointId = UUID().uuidString
        do {
            let checkpointsDir = try Self.agenticPlanningCheckpointsDirectory()
            let checkpointURL = checkpointsDir.appendingPathComponent(checkpointId, isDirectory: true)
            try FileManager.default.createDirectory(at: checkpointURL, withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: root, to: checkpointURL.appendingPathComponent("files", isDirectory: true))
            let metadata: [String: Any] = [
                "id": checkpointId,
                "timestamp": ISO8601DateFormatter().string(from: Date()),
                "description": description,
                "rootPath": root.path,
            ]
            let metadataData = try JSONSerialization.data(withJSONObject: metadata, options: [.prettyPrinted, .sortedKeys])
            try metadataData.write(to: checkpointURL.appendingPathComponent("metadata.json"))
        } catch {
            if let dir = try? Self.agenticPlanningCheckpointsDirectory() {
                try? FileManager.default.removeItem(at: dir.appendingPathComponent(checkpointId))
            }
            throw MCPToolError("Failed to create checkpoint: \(error.localizedDescription)")
        }
        return .structured(["checkpoint_id": .string(checkpointId), "description": .string(description)],
                           summary: "Checkpoint '\(description)' created")
    }

    func agenticPlanningRollbackChanges(_ call: MCPToolCall) async throws -> MCPToolResult {
        let checkpointID = try call.require("checkpointID")
        guard !checkpointID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw MCPToolError("Missing required parameter: checkpointID")
        }
        let s = try session(for: call)
        let root = Self.folder(of: s.model)
        let filesURL: URL
        do {
            let checkpointsDir = try Self.agenticPlanningCheckpointsDirectory()
            let checkpointURL = checkpointsDir.appendingPathComponent(checkpointID, isDirectory: true)
            filesURL = checkpointURL.appendingPathComponent("files", isDirectory: true)
            if let metadataData = try? Data(contentsOf: checkpointURL.appendingPathComponent("metadata.json")),
               let metadata = try? JSONSerialization.jsonObject(with: metadataData) as? [String: Any],
               let owner = metadata["rootPath"] as? String, owner != root.path {
                throw MCPToolError("Checkpoint '\(checkpointID)' belongs to workspace '\(owner)'; it cannot be rolled back into '\(root.path)'.")
            }
        } catch let e as MCPToolError {
            throw e
        } catch {
            throw MCPToolError("Failed to roll back changes: \(error.localizedDescription)")
        }
        guard FileManager.default.fileExists(atPath: filesURL.path) else {
            throw MCPToolError("Checkpoint '\(checkpointID)' not found. Checkpoints are created by checkpoint_creator; use project_restore for project_snapshot snapshots.")
        }
        let change = MCPChange(tool: call.name, path: root.path, relativePath: ".", original: nil, proposed: "",
                               summary: "Roll back workspace to checkpoint \(checkpointID) — replaces all files in the workspace")
        guard await call.approve(change) else {
            throw MCPToolError(MCPServer.rejectedMessage)
        }
        do {
            let contents = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
            for url in contents {
                try FileManager.default.removeItem(at: url)
            }
            let restoredContents = try FileManager.default.contentsOfDirectory(at: filesURL, includingPropertiesForKeys: nil)
            for url in restoredContents {
                try FileManager.default.copyItem(at: url, to: root.appendingPathComponent(url.lastPathComponent))
            }
        } catch {
            throw MCPToolError("Failed to roll back changes: \(error.localizedDescription)")
        }
        return .structured(["checkpoint_id": .string(checkpointID)],
                           summary: "Changes rolled back to \(checkpointID)")
    }

    // MARK: - Question handoff

    func agenticPlanningQuestionsHandle(_ call: MCPToolCall) throws -> MCPToolResult {
        guard let questionsRaw = call.arguments["questions"]?.array, !questionsRaw.isEmpty else {
            throw MCPToolError("Missing required parameter: questions (at least one question is required)")
        }
        var questions: [AnyJSON] = []
        var prompts: [String] = []
        for raw in questionsRaw {
            let obj = raw.object ?? [:]
            guard let id = obj["id"]?.string, !id.isEmpty,
                  let prompt = obj["prompt"]?.string, !prompt.isEmpty,
                  let inputType = obj["input_type"]?.string, !inputType.isEmpty else {
                throw MCPToolError("Each question requires 'id', 'prompt', and 'input_type'.")
            }
            guard inputType == "text" || inputType == "selection" else {
                throw MCPToolError("Question '\(id)' has unsupported input_type '\(inputType)'. Supported: text, selection.")
            }
            let options = obj["options"]?.array?.compactMap(\.string) ?? []
            if inputType == "selection" && options.isEmpty {
                throw MCPToolError("Question '\(id)' uses input_type 'selection' but has no options.")
            }
            prompts.append(prompt)
            questions.append(["id": .string(id), "prompt": .string(prompt), "input_type": .string(inputType),
                              "options": .array(options.map(AnyJSON.string))])
        }
        let questionSetId = UUID().uuidString
        let summary = "Questions for the user (pending — present these questions to the user; this tool does not wait for an answer):\n"
            + prompts.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n")
        return .structured(["questionSetId": .string(questionSetId), "questions": .array(questions),
                            "status": .string("pending")], summary: summary)
    }

    // MARK: - Checklist plan

    func agenticPlanningChecklistPlan(_ call: MCPToolCall) async throws -> MCPToolResult {
        let s = try session(for: call)
        guard let tasksRaw = call.arguments["tasks"]?.array, !tasksRaw.isEmpty else {
            throw MCPToolError("Missing required parameter: tasks (at least one task is required)")
        }
        var incoming: [AgenticPlanningTask] = []
        for raw in tasksRaw {
            let obj = raw.object ?? [:]
            guard let id = obj["id"]?.string, !id.isEmpty,
                  let title = obj["title"]?.string, !title.isEmpty,
                  let status = obj["status"]?.string, !status.isEmpty else {
                throw MCPToolError("Each task requires 'id', 'title', and 'status'.")
            }
            guard ["queued", "in_progress", "completed", "failed"].contains(status) else {
                throw MCPToolError("Task '\(id)' has unsupported status '\(status)'. Supported: queued, in_progress, completed, failed.")
            }
            incoming.append(AgenticPlanningTask(id: id, title: title, status: status,
                                                detail: obj["detail"]?.string ?? ""))
        }
        let workspace = memoryWorkspaceKey(in: s)
        var plan = AgenticPlanningPlanStore.shared.currentPlan(workspace: workspace)
            ?? AgenticPlanningPlanStore.shared.create(workspace: workspace, goal: "Checklist", tasks: [])
        for task in incoming {
            if let idx = plan.tasks.firstIndex(where: { $0.id == task.id }) {
                plan.tasks[idx].status = task.status
                plan.tasks[idx].title = task.title
                plan.tasks[idx].detail = task.detail
            } else if let idx = plan.tasks.firstIndex(where: { $0.title.caseInsensitiveCompare(task.title) == .orderedSame }) {
                plan.tasks[idx].status = task.status
                plan.tasks[idx].detail = task.detail
            } else {
                plan.tasks.append(task)
            }
        }
        AgenticPlanningPlanStore.shared.update(workspace: workspace, plan: plan)
        let completed = plan.tasks.filter { $0.status == "completed" }.count
        return .structured(["planId": .string(plan.id), "taskCount": .int(plan.tasks.count),
                            "completedCount": .int(completed), "progress": .double(plan.progress)],
                           summary: "Checklist updated: \(completed) of \(plan.tasks.count) tasks completed.")
    }
}
