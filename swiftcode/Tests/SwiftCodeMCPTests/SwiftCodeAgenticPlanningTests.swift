import Foundation
import Testing
import SwiftCodeAssistant
@testable import SwiftCodeMCP

@MainActor
@Suite(.serialized) struct SwiftCodeAgenticPlanningTests {
    static let sliceHIDs = ["ai_context_memory", "checklist_plan", "checkpoint_creator", "progress_tracker",
                            "questions_handle", "rollback_changes", "task_planner", "todo_manager"]

    func opened(_ sample: TempSample, policy: MCPWritePolicy = .readOnly) async throws -> SwiftCodeMCPHost {
        let host = SwiftCodeMCPHost()
        host.server.writePolicy = policy
        let ported = Set(host.agenticPlanningTools.map(\.name))
        host.server.tools = host.server.tools.filter { !ported.contains($0.name) } + host.agenticPlanningTools
        let r = try await host.server.callTool("workspace_open", ["path": .string(sample.url.path)])
        #expect(!r.isToolError, "\(r.resultText)")
        return host
    }

    @Test func toolsAreListedWithLegacySchemas() async throws {
        let host = SwiftCodeMCPHost()
        let tools = host.agenticPlanningTools
        #expect(tools.count == 8, "expected 8 slice-H tools, got \(tools.map(\.name))")
        #expect(tools.map(\.name).sorted() == Self.sliceHIDs.sorted())
        #expect(!tools.map(\.name).contains("ask_user"), "ask_user must not be registered here; it is an alias of plan-AskUser")
        let expectedRequired: [String: [String]] = [
            "ai_context_memory": ["action"], "task_planner": ["goal"], "todo_manager": ["action"],
            "progress_tracker": ["taskID"], "checkpoint_creator": ["description"], "rollback_changes": ["checkpointID"],
            "questions_handle": ["questions"], "checklist_plan": ["tasks"],
        ]
        for tool in tools {
            let required = tool.inputSchema["required"]?.array?.compactMap(\.string) ?? []
            #expect(required == expectedRequired[tool.name], "\(tool.name) required: \(required)")
            #expect(tool.inputSchema["properties"]?["workspace"] != nil, "\(tool.name) is missing the workspace parameter")
            switch tool.name {
            case "progress_tracker", "questions_handle":
                #expect(tool.annotations.readOnly && !tool.writes, "\(tool.name) must be read-only")
            case "rollback_changes":
                #expect(!tool.annotations.readOnly && tool.writes, "\(tool.name) must be a write tool")
                #expect(tool.annotations.destructive, "\(tool.name) must be marked destructive")
            default:
                #expect(!tool.annotations.readOnly && tool.writes, "\(tool.name) must be a write tool")
                #expect(!tool.annotations.destructive, "\(tool.name) must not be marked destructive")
            }
        }
        let sample = try TempSample()
        defer { sample.remove() }
        let servedHost = try await opened(sample)
        let served = servedHost.server.tools.map(\.name)
        for id in Self.sliceHIDs { #expect(served.contains(id), "\(id) is not installed on the server") }
        #expect(served.filter { $0 == "task_planner" }.count == 1, "task_planner must be served exactly once")
    }

    @Test func askUserIsAlreadyServedByPlanAskUserAlias() {
        #expect(MCPServer.toolAliases["ask_user"] == "plan-AskUser")
        let host = SwiftCodeMCPHost()
        #expect(host.planningTools.map(\.name).contains("plan-AskUser"), "plan-AskUser must exist for the alias to resolve to")
    }

    @Test func contextMemoryStoreRetrieveClear() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample, policy: .allow)
        let stored = try await host.server.callTool("ai_context_memory", ["action": .string("store"), "data": .string("Prefer MVVM for new views")])
        #expect(!stored.isToolError, "\(stored.resultText)")
        #expect(stored.firstText == "Memory stored")
        #expect(stored.structured?["count"]?.int == 1)
        let stored2 = try await host.server.callTool("ai_context_memory", ["action": .string("store"), "data": .string("Tests live in Tests/")])
        #expect(stored2.structured?["count"]?.int == 2)

        let retrieved = try await host.server.callTool("ai_context_memory", ["action": .string("retrieve")])
        #expect(!retrieved.isToolError, "\(retrieved.resultText)")
        #expect(retrieved.firstText == "Memory retrieved")
        let entries = retrieved.structured?["entries"]?.array?.compactMap(\.string) ?? []
        #expect(entries == ["Prefer MVVM for new views", "Tests live in Tests/"])

        let listed = try await host.server.callTool("ai_context_memory", ["action": .string("list")])
        #expect(!listed.isToolError, "\(listed.resultText)")
        #expect(listed.firstText == "Memory listed")
        #expect(listed.structured?["count"]?.int == 2)

        let cleared = try await host.server.callTool("ai_context_memory", ["action": .string("clear")])
        #expect(!cleared.isToolError, "\(cleared.resultText)")
        #expect(cleared.firstText == "Memory cleared")
        #expect(cleared.structured?["count"]?.int == 0)
        let afterClear = try await host.server.callTool("ai_context_memory", ["action": .string("retrieve")])
        #expect(afterClear.structured?["count"]?.int == 0)

        let unknown = try await host.server.callTool("ai_context_memory", ["action": .string("summarize")])
        #expect(unknown.isToolError, "unknown action must fail")
        #expect(unknown.firstText.contains("summarize"))
        let noData = try await host.server.callTool("ai_context_memory", ["action": .string("store")])
        #expect(noData.isToolError, "store without data must fail")
    }

    @Test func taskPlannerChecklistAndProgressRoundTrip() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample, policy: .allow)
        let planned = try await host.server.callTool("task_planner", ["goal": .string("Write the code, run the tests")])
        #expect(!planned.isToolError, "\(planned.resultText)")
        let planId = planned.structured?["planId"]?.string
        #expect(planId != nil && !planId!.isEmpty)
        #expect(planned.structured?["taskCount"]?.int == 2)
        let steps = planned.structured?["steps"]?.string ?? ""
        #expect(steps.contains("1. Write the code"))
        #expect(steps.contains("2. run the tests"))
        #expect(planned.firstText == "Plan generated for goal: Write the code, run the tests")
        let taskIDs = planned.structured?["tasks"]?.array?.compactMap { $0["id"]?.string } ?? []
        #expect(taskIDs.count == 2, "task_planner must expose its task IDs so checklist_plan and progress_tracker can address them")

        let zero = try await host.server.callTool("progress_tracker", ["taskID": .string(planId!)])
        #expect(!zero.isToolError, "\(zero.resultText)")
        #expect(zero.structured?["progress"]?.double == 0.0)
        #expect(zero.structured?["status"]?.string == "queued")
        #expect(zero.firstText == "Progress for \(planId!): 0.0%")

        let planned2 = try await host.server.callTool("task_planner", ["goal": .string("Something else")])
        #expect(planned2.structured?["planId"]?.string != planId)

        let replanned = try await host.server.callTool("task_planner", ["goal": .string("Write the code, run the tests")])
        let currentPlanId = replanned.structured?["planId"]?.string
        #expect(currentPlanId != nil && currentPlanId != planId)
        let currentTaskIDs = replanned.structured?["tasks"]?.array?.compactMap { $0["id"]?.string } ?? []
        #expect(currentTaskIDs.count == 2)
        let checklist = try await host.server.callTool("checklist_plan", ["tasks": .array([
            ["id": .string(currentTaskIDs[0]), "title": .string("Write the code"), "status": .string("completed")],
            ["id": .string(currentTaskIDs[1]), "title": .string("run the tests"), "status": .string("in_progress"), "detail": .string("swift test")],
        ])])
        #expect(!checklist.isToolError, "\(checklist.resultText)")
        #expect(checklist.structured?["planId"]?.string == currentPlanId, "checklist_plan must update the current plan")
        #expect(checklist.structured?["taskCount"]?.int == 2, "updating by ID must not append duplicate tasks")
        #expect(checklist.structured?["completedCount"]?.int == 1)
        #expect(checklist.structured?["progress"]?.double == 0.75)
        #expect(checklist.firstText == "Checklist updated: 1 of 2 tasks completed.")

        let tracked = try await host.server.callTool("progress_tracker", ["taskID": .string(currentPlanId!)])
        #expect(!tracked.isToolError, "\(tracked.resultText)")
        #expect(tracked.structured?["progress"]?.double == 0.75)
        #expect(tracked.structured?["status"]?.string == "in_progress")
        #expect(tracked.firstText == "Progress for \(currentPlanId!): 75.0%")

        let taskTracked = try await host.server.callTool("progress_tracker", ["taskID": .string(currentTaskIDs[0])])
        #expect(!taskTracked.isToolError, "\(taskTracked.resultText)")
        #expect(taskTracked.structured?["progress"]?.double == 1.0)
        #expect(taskTracked.structured?["status"]?.string == "completed")
        let taskTracked2 = try await host.server.callTool("progress_tracker", ["taskID": .string(currentTaskIDs[1])])
        #expect(taskTracked2.structured?["progress"]?.double == 0.5)

        let updated = try await host.server.callTool("checklist_plan", ["tasks": .array([
            ["id": .string(currentTaskIDs[1]), "title": .string("run the tests"), "status": .string("completed")],
        ])])
        #expect(!updated.isToolError, "\(updated.resultText)")
        #expect(updated.structured?["taskCount"]?.int == 2, "updating by ID must not append a duplicate task")
        #expect(updated.structured?["completedCount"]?.int == 2)
        #expect(updated.structured?["progress"]?.double == 1.0)
        let done = try await host.server.callTool("progress_tracker", ["taskID": .string(currentPlanId!)])
        #expect(done.structured?["status"]?.string == "completed")

        let unknown = try await host.server.callTool("progress_tracker", ["taskID": .string("no-such-task")])
        #expect(unknown.isToolError, "unknown taskID must fail")
        #expect(unknown.firstText.contains("no-such-task"))
    }

    @Test func checklistPlanCreatesPlanWhenNoneExists() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample, policy: .allow)
        let checklist = try await host.server.callTool("checklist_plan", ["tasks": .array([
            ["id": .string("solo"), "title": .string("Only task"), "status": .string("queued")],
        ])])
        #expect(!checklist.isToolError, "\(checklist.resultText)")
        #expect(checklist.structured?["planId"]?.string != nil)
        #expect(checklist.structured?["taskCount"]?.int == 1)
        #expect(checklist.structured?["completedCount"]?.int == 0)
        #expect(checklist.structured?["progress"]?.double == 0.0)

        let badStatus = try await host.server.callTool("checklist_plan", ["tasks": .array([
            ["id": .string("x"), "title": .string("Bad"), "status": .string("done")],
        ])])
        #expect(badStatus.isToolError, "unsupported status must fail")
        #expect(badStatus.firstText.contains("done"))
        let empty = try await host.server.callTool("checklist_plan", ["tasks": .array([])])
        #expect(empty.isToolError, "empty tasks must fail")
    }

    @Test func taskPlannerWithoutClausesUsesGenericSteps() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample, policy: .allow)
        let planned = try await host.server.callTool("task_planner", ["goal": .string("Refactor")])
        #expect(!planned.isToolError, "\(planned.resultText)")
        #expect(planned.structured?["taskCount"]?.int == 4)
        let steps = planned.structured?["steps"]?.string ?? ""
        #expect(steps.contains("1. Analyze requirements"))
        #expect(steps.contains("4. Summarize outputs"))
    }

    @Test func todoManagerRoundTrip() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample, policy: .allow)
        let empty = try await host.server.callTool("todo_manager", ["action": .string("list")])
        #expect(!empty.isToolError, "\(empty.resultText)")
        #expect(empty.firstText == "Todo list is empty.")
        #expect(empty.structured?["count"]?.int == 0)

        let added = try await host.server.callTool("todo_manager", ["action": .string("add"), "todo": .string("Fix the greeting")])
        #expect(!added.isToolError, "\(added.resultText)")
        #expect(added.firstText == "Todo list updated: added \"Fix the greeting\"")
        #expect(added.structured?["count"]?.int == 1)
        let added2 = try await host.server.callTool("todo_manager", ["action": .string("add"), "todo": .string("Write a test")])
        #expect(added2.structured?["count"]?.int == 2)

        let todosText = sample.read(".assist_temp/memory/todos.json")
        #expect(todosText.contains("Fix the greeting"))
        #expect(todosText.contains("Write a test"))

        let listed = try await host.server.callTool("todo_manager", ["action": .string("list")])
        #expect(!listed.isToolError, "\(listed.resultText)")
        #expect(listed.firstText.contains("[ ] Fix the greeting"))
        #expect(listed.firstText.contains("[ ] Write a test"))
        let todos = listed.structured?["todos"]?.array ?? []
        #expect(todos.count == 2)
        #expect(todos[0]["completed"]?.bool == false)

        let completed = try await host.server.callTool("todo_manager", ["action": .string("complete"), "todo": .string("Fix the greeting")])
        #expect(!completed.isToolError, "\(completed.resultText)")
        #expect(completed.firstText == "Todo list updated: completed \"Fix the greeting\"")
        let listed2 = try await host.server.callTool("todo_manager", ["action": .string("list")])
        #expect(listed2.firstText.contains("[x] Fix the greeting"))
        #expect(listed2.firstText.contains("[ ] Write a test"))

        let removed = try await host.server.callTool("todo_manager", ["action": .string("remove"), "todo": .string("Write a test")])
        #expect(!removed.isToolError, "\(removed.resultText)")
        #expect(removed.structured?["count"]?.int == 1)

        let missing = try await host.server.callTool("todo_manager", ["action": .string("complete"), "todo": .string("No such todo")])
        #expect(missing.isToolError, "completing a missing todo must fail")
        #expect(missing.firstText.contains("No such todo"))
        let noTodo = try await host.server.callTool("todo_manager", ["action": .string("add")])
        #expect(noTodo.isToolError, "add without todo must fail")
        let unknown = try await host.server.callTool("todo_manager", ["action": .string("prioritize")])
        #expect(unknown.isToolError, "unknown action must fail")

        let cleared = try await host.server.callTool("todo_manager", ["action": .string("clear")])
        #expect(!cleared.isToolError, "\(cleared.resultText)")
        #expect(cleared.firstText == "Todo list cleared.")
        #expect(cleared.structured?["count"]?.int == 0)
    }

    @Test func todoManagerIsRefusedWhenReadOnly() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample)
        let r = try await host.server.callTool("todo_manager", ["action": .string("add"), "todo": .string("Should not land")])
        #expect(r.isToolError, "a write tool must be refused when the server is read-only")
        #expect(r.firstText == MCPServer.readOnlyMessage("todo_manager"))
        #expect(!sample.read(".assist_temp/memory/todos.json").contains("Should not land"))
    }

    @Test func checkpointAndRollbackRoundTrip() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample, policy: .allow)
        let original = sample.read("Sources/Greeter/Greeter.swift")
        #expect(!original.isEmpty)

        let created = try await host.server.callTool("checkpoint_creator", ["description": .string("Before greeting change")])
        #expect(!created.isToolError, "\(created.resultText)")
        let checkpointId = created.structured?["checkpoint_id"]?.string
        #expect(checkpointId != nil && !checkpointId!.isEmpty)
        #expect(created.structured?["description"]?.string == "Before greeting change")
        #expect(created.firstText == "Checkpoint 'Before greeting change' created")

        try "struct Greeter { var salutation = \"Changed\" }\n".write(toFile: sample.path("Sources/Greeter/Greeter.swift"), atomically: true, encoding: .utf8)
        #expect(sample.read("Sources/Greeter/Greeter.swift").contains("Changed"))
        let rolled = try await host.server.callTool("rollback_changes", ["checkpointID": .string(checkpointId!)])
        #expect(!rolled.isToolError, "\(rolled.resultText)")
        #expect(rolled.structured?["checkpoint_id"]?.string == checkpointId)
        #expect(rolled.firstText == "Changes rolled back to \(checkpointId!)")
        #expect(sample.read("Sources/Greeter/Greeter.swift") == original)

        let unknown = try await host.server.callTool("rollback_changes", ["checkpointID": .string("no-such-checkpoint")])
        #expect(unknown.isToolError, "unknown checkpoint must fail")
        #expect(unknown.firstText.contains("no-such-checkpoint"))
        #expect(unknown.firstText.contains("project_restore"))
    }

    @Test func checkpointCreatorIsRefusedWhenReadOnly() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample)
        let r = try await host.server.callTool("checkpoint_creator", ["description": .string("Should not land")])
        #expect(r.isToolError, "a write tool must be refused when the server is read-only")
        #expect(r.firstText == MCPServer.readOnlyMessage("checkpoint_creator"))
        let rolled = try await host.server.callTool("rollback_changes", ["checkpointID": .string("anything")])
        #expect(rolled.isToolError, "rollback must be refused when the server is read-only")
        #expect(rolled.firstText == MCPServer.readOnlyMessage("rollback_changes"))
    }

    @Test func questionsHandleReturnsPendingHandoff() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample)
        let asked = try await host.server.callTool("questions_handle", ["questions": .array([
            ["id": .string("q1"), "prompt": .string("Which greeting style?"), "input_type": .string("selection"),
             "options": .array([.string("Formal"), .string("Casual")])],
            ["id": .string("q2"), "prompt": .string("Anything else to note?"), "input_type": .string("text")],
        ])])
        #expect(!asked.isToolError, "\(asked.resultText)")
        #expect(asked.structured?["status"]?.string == "pending")
        let questionSetId = asked.structured?["questionSetId"]?.string
        #expect(questionSetId != nil && !questionSetId!.isEmpty)
        let questions = asked.structured?["questions"]?.array ?? []
        #expect(questions.count == 2)
        #expect(questions[0]["id"]?.string == "q1")
        #expect(questions[0]["prompt"]?.string == "Which greeting style?")
        #expect(questions[0]["input_type"]?.string == "selection")
        #expect(questions[0]["options"]?.array?.compactMap(\.string) == ["Formal", "Casual"])
        #expect(questions[1]["input_type"]?.string == "text")
        #expect(asked.firstText.contains("Questions for the user (pending"))
        #expect(asked.firstText.contains("1. Which greeting style?"))
        #expect(asked.firstText.contains("2. Anything else to note?"))

        let empty = try await host.server.callTool("questions_handle", ["questions": .array([])])
        #expect(empty.isToolError, "empty questions must fail")
        let missingPrompt = try await host.server.callTool("questions_handle", ["questions": .array([
            ["id": .string("q1"), "input_type": .string("text")],
        ])])
        #expect(missingPrompt.isToolError, "a question without a prompt must fail")
        let badType = try await host.server.callTool("questions_handle", ["questions": .array([
            ["id": .string("q1"), "prompt": .string("Pick one"), "input_type": .string("choice")],
        ])])
        #expect(badType.isToolError, "an unsupported input_type must fail")
        #expect(badType.firstText.contains("choice"))
        let noOptions = try await host.server.callTool("questions_handle", ["questions": .array([
            ["id": .string("q1"), "prompt": .string("Pick one"), "input_type": .string("selection")],
        ])])
        #expect(noOptions.isToolError, "a selection without options must fail")
    }
}
