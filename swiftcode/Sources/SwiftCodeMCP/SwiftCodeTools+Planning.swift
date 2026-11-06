import Foundation
import SwiftCodeAssistant
import SwiftCodeIDECore

/// The ported Legacy planning / workflow / agent-control tool family (Wave 4).
///
/// Behaviour source: Legacy's `ExecutionPlanTool`,
/// `AssistPlanTaskTool`, `AssistBreakdownTaskTool`,
/// `AssistAutoFixErrorsTool`, `AssistExplainCodeTool`,
/// `AssistGenerateTestsTool`, `PlanAskUserTool` and `ReportToUserTool`
/// (Dylan's own code, ported under MIT), plus
/// `Functions/System Assets/ExecutionPlans.md` (plan-mode / execution-plan
/// behaviour) and `Resources/WriteExecutionPlan.md` (the plan-generation
/// instruction the `execution_plan` tool loads; in SwiftCode there is no such
/// bundle resource, so the plan carries no "Plan Generation Instructions"
/// section — Legacy renders that section only when the instruction text
/// is non-empty).
///
/// Conventions, following Waves 1–3:
///
/// * Schemas are Legacy's `parametersSchema` verbatim, plus the
///   `workspace` parameter Wave 1 adds to every tool. Legacy's
///   parameter-name aliases are NOT supported: SwiftCode's argument
///   validation rejects unknown arguments before the handler runs.
///   Legacy's registry aliases (`plan_askuser` / `plan_ask_user` /
///   `ask_user` → `plan-AskUser`, `task_complete` / `task_completion`
///   → `report_to_user`) live in `MCPServer.toolAliases`, which this
///   wave does not touch — the coordinator owns that table.
/// * Structured data keeps Legacy's keys, with typed JSON values
///   (integers and booleans) the way SwiftCode's other tools do — Legacy's
///   string-only map is not reproduced.
/// * Path resolution uses the session-aware `resolveFileReadingPath`
///   (plain relative paths resolve against the `dir_cd` working
///   directory; `..` that stays inside the workspace is allowed; no
///   path may escape the workspace), the same resolver the file
///   tools use. `execution_plan`'s own repository inspection is
///   deliberately separate: it enumerates the workspace root directly
///   (never the session working directory), as Legacy does.
/// * Approval gating: the two writing handlers (`execution_plan`,
///   which writes `agent_notes.md`, and `intel_generate_tests`,
///   which writes the generated test file) gate BEFORE touching disk,
///   through `commit()` — the Wave 1 helper — exactly like the Wave 2
///   file-writing tools. `MCPServer.run` already refuses `writes: true`
///   tools when the server is read-only; the approval call is still
///   required. There is no Autopilot bypass anywhere in this file.
/// * Plans are produced, never executed: no tool in this family runs a
///   plan, invokes another tool, or spawns workers. Execution stays
///   with the caller, through the normal approval gate.
///
/// Deliberate deviations from Legacy, recorded here:
///
/// * `intel_autofix` is wired to the configured Assist LLM provider
///   (gap-closure wiring, through `LLMToolCompletionService` — see
///   `SwiftCodeTools+AgenticCode.swift` for the shared service) and to the
///   existing `lint_project` diagnostics (`terminalTaskLintProject` in
///   `SwiftCodeTools+Terminal.swift`: Legacy's `collectSwiftFindings`).
///   With no lint issues it reports success without calling the LLM;
///   otherwise each file with findings is rewritten by the LLM (Legacy's
///   prompt shape) and written through `commit()`. With no provider
///   usable it fails honestly naming the provider; no file is changed.
///   Findings carry basenames only, so two Swift files sharing a
///   basename resolve to the first match.
/// * `intel_explain_code` is implemented as honest static analysis,
///   not as an LLM call: Legacy tries an OpenAI LLM first and falls
///   back to a one-line static summary when the LLM fails. SwiftCode's MCP
///   host has no LLM provider wired for this tool, so the port always
///   takes the static path — and says so in the result ("Static
///   analysis for …"). The explanation is grounded in the file itself
///   (line count, imports, declared types, functions); nothing is
///   invented and no LLM output is claimed.
/// * `plan-AskUser` never blocks. Legacy presents a native macOS
///   question UI and suspends execution for up to 300 seconds waiting
///   for the user's answer, and is available only in Plan mode. SwiftCode's
///   MCP host is non-interactive and has no Plan/Autopilot execution
///   mode, so the port returns the question as a structured handoff
///   payload (`questionId`, `question`, `status: "pending"`, the
///   choices with their `assistRecommended` flags) and returns
///   immediately. The caller must present the question to the user and
///   feed the answer back; the tool itself never waits and never hangs.
///   The Legacy Plan-mode-only restriction cannot be enforced here
///   (there is no mode to check) and is therefore not a failure case.
/// * `execution_plan` accepts the documented mode values `"plan"` and
///   `"autopilot"` case-insensitively. Legacy's schema documents those
///   lowercase values but its `ExecutionMode(rawValue:)` init only
///   matches the capitalised `"Plan"` / `"Autopilot"`, so a literal
///   `"plan"` silently became Autopilot. The port honours the documented
///   values; the mode only labels the plan document and never changes
///   any gating.
/// * `intel_generate_tests` derives the `@testable import` module from
///   the source path (`Sources/<Module>/…`, else the source file's
///   parent directory name, else `App`). Legacy hardcodes
///   `@testable import SwiftCode`. The generated stub body is otherwise
///   Legacy's verbatim template.
/// * `intel_plan_task` / `intel_breakdown_task` store plans in an
///   in-memory, process-wide store (`PlanningPlanStore`, see
///   `SwiftCodeTools+PlanningSupport.swift`). Legacy stores them in the
///   session's `AssistContext.memory`; SwiftCode's MCP host has no session
///   memory store. Plan IDs are UUIDs, so plans from different
///   workspaces cannot collide; plans do not survive a server restart.
/// * `report_to_user` has no `AssistManager` to broadcast to: Legacy
///   posts the rendered report as the assistant's last message. In
///   SwiftCode the tool result text IS the report; there is no side effect.
/// * `execution_plan` writes `agent_notes.md` through `commit()`, so a
///   rejected or read-only call fails instead of writing. Legacy writes
///   the file directly and still returns success when the write fails.
///   The SwiftCode behaviour is the correct one under the approval model:
///   a write the reviewer refused must not land on disk.
extension SwiftCodeMCPHost {
    var planningTools: [MCPTool] {
        let safeMutation = MCPToolAnnotations(readOnly: false, idempotent: true)
        return [
            tool("execution_plan", "Generate Execution Plan",
                 """
                 Analyzes the actual repository state, reads relevant files, discovers instructions and skills, \
                 and generates a task-specific Execution Plan. This tool MUST be called before any codebase modification. \
                 The plan is written to agent_notes.md and contains objective, findings, steps, dependencies, \
                 verification requirements, and completion criteria — all grounded in actual repository state.
                 """,
                 input: Schema.object(["workspace": Schema.workspace,
                                       "objective": Schema.string("The user's task objective."),
                                       "mode": Schema.string("Execution mode: 'plan' or 'autopilot'."),
                                       "relevantFiles": Schema.array(Schema.str, "Optional list of file paths already known to be relevant.")],
                                      required: ["objective", "mode"]),
                 output: Schema.output(["planFile": Schema.str, "stepCount": Schema.int, "relevantFileCount": Schema.int,
                                        "workerCount": Schema.int, "mode": Schema.str]),
                 annotations: safeMutation, writes: true) { h, call in
                try await h.generateExecutionPlan(call)
            },
            tool("intel_plan_task", "Plan Task",
                 "Generates a high-level execution plan for a complex task.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "task": Schema.string("Natural-language description of the task to plan.")],
                                      required: ["task"]),
                 output: Schema.output(["planId": Schema.str, "steps": Schema.str])) { h, call in
                try await h.planTask(call)
            },
            tool("intel_breakdown_task", "Breakdown Task",
                 "Breaks down a plan into granular, actionable steps.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "planId": Schema.string("Plan identifier previously returned by intel_plan_task.")],
                                      required: ["planId"]),
                 output: Schema.output(["breakdown": Schema.str])) { h, call in
                try await h.breakdownTask(call)
            },
            tool("intel_autofix", "Auto-Fix Errors",
                 "Attempts to automatically fix detected compilation or linting errors.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "path": Schema.string("Workspace-relative file or directory to auto-fix. Defaults to the workspace root. Default: \".\".")]),
                 annotations: safeMutation, writes: true) { h, call in
                try await h.autoFixErrors(call)
            },
            tool("intel_explain_code", "Explain Code",
                 "Provides a detailed explanation of the code at a path.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "path": Schema.string("Workspace-relative path of the file to explain.")],
                                      required: ["path"]),
                 output: Schema.output(["explanation": Schema.str])) { h, call in
                try await h.explainCode(call)
            },
            tool("intel_generate_tests", "Generate Tests",
                 "Generates unit test stubs for Swift types with proper setup and teardown.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "path": Schema.string("Workspace-relative path of the source file to generate tests for."),
                                       "testPath": Schema.string("Workspace-relative output path for the generated test file. Default: \"Tests/<SourceName>Tests.swift\".")],
                                      required: ["path"]),
                 output: Schema.output(["test_path": Schema.str, "test_count": Schema.int, "types_count": Schema.int,
                                        "functions_count": Schema.int]),
                 annotations: safeMutation, writes: true) { h, call in
                try await h.generateTests(call)
            },
            tool("plan-AskUser", "Ask User for Decision",
                 """
                 Presents a structured question to the user during Plan mode execution. \
                 The question is rendered as a native macOS UI (PlanUserAskView) and execution \
                 suspends until the user provides an answer. The answer becomes persistent session data. \
                 This tool is ONLY available in Plan mode and is blocked at the runtime registry layer \
                 in Autopilot mode.
                 """,
                 input: Schema.object(["workspace": Schema.workspace,
                                       "question": Schema.string("The decision question to present to the user."),
                                       "allowsMultipleAnswers": Schema.boolean("Whether multiple choices may be selected."),
                                       "choices": Schema.array(
                                        Schema.object(["choice": Schema.string("The choice text."),
                                                       "assistRecommended": Schema.boolean("Whether the assistant recommends this choice.")],
                                                      required: ["choice"]),
                                        "Available choices for the user. Each choice must have 'choice' (string) and 'assistRecommended' (boolean) fields."),
                                       "userSpecification": Schema.boolean("Whether the user may provide a free-form response.")],
                                      required: ["question", "allowsMultipleAnswers", "choices"]),
                 output: Schema.output(["questionId": Schema.str, "question": Schema.str, "status": Schema.str,
                                        "allowsMultipleAnswers": Schema.bool, "userSpecification": Schema.bool,
                                        "choices": Schema.array(Schema.anyObject, "The choices as presented.")])) { h, call in
                try await h.askUser(call)
            },
            tool("report_to_user", "Report Task Completion to User",
                 """
                 Delivers the authoritative task completion report to the user once all task work, \
                 builds, tests, and audits are fully finished. Must be called at all times when Assist \
                 finishes doing task work. Not for conversational Q&A. Cleans and renders polished Markdown.
                 """,
                 input: Schema.object(["workspace": Schema.workspace,
                                       "summary": Schema.string("Structured, concise completion report summarizing work done, files modified, and build/test verification results. Clean Markdown formatted."),
                                       "status": Schema.string("Task outcome status (e.g. 'completed', 'verified', 'partially_completed')."),
                                       "filesModified": Schema.array(Schema.str, "List of files that were created, updated, or audited during this task execution."),
                                       "verification": Schema.string("Build, compiler diagnostic, and automated test execution results proving correctness.")],
                                      required: ["summary"]),
                 output: Schema.output(["status": Schema.str, "filesCount": Schema.int, "renderedLength": Schema.int])) { h, call in
                try await h.reportToUser(call)
            },
        ]
    }
}

extension SwiftCodeMCPHost {
    // MARK: - Execution plan

    func generateExecutionPlan(_ call: MCPToolCall) async throws -> MCPToolResult {
        let s = try session(for: call)
        guard let objective = call.arguments["objective"]?.string,
              !objective.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw MCPToolError("Missing required argument: 'objective' must be a non-empty string.")
        }
        let modeRaw = call.arguments["mode"]?.string ?? "autopilot"
        let mode = PlanningExecutionMode(documented: modeRaw)
        let relevantFilesHint = call.strings("relevantFiles") ?? []
        let root = Self.folder(of: s.model)

        let fileTree = PlanningSupport.inspectRepositoryStructure(workspaceRoot: root)
        let buildConfig = PlanningSupport.inspectBuildConfiguration(workspaceRoot: root)
        let agentsInstructions = PlanningSupport.discoverInstructions(workspaceRoot: root)
        let skills = PlanningSupport.discoverSkills(workspaceRoot: root)
        let relevantFiles = PlanningSupport.identifyRelevantFiles(objective: objective, workspaceRoot: root, hints: relevantFilesHint)
        let fileContents = PlanningSupport.readRelevantFiles(files: relevantFiles, workspaceRoot: root)
        let plan = PlanningSupport.buildExecutionPlan(objective: objective, mode: mode, fileTree: fileTree,
                                                      buildConfig: buildConfig, agentsInstructions: agentsInstructions,
                                                      skills: skills, relevantFiles: relevantFiles, fileContents: fileContents)
        let planMarkdown = PlanningSupport.renderPlanMarkdown(plan)

        let notesURL = root.appendingPathComponent("agent_notes.md")
        try await commit(MCPChange(tool: call.name, path: notesURL.path, relativePath: "agent_notes.md",
                                   original: text(of: notesURL), proposed: planMarkdown,
                                   summary: "Write execution plan to agent_notes.md"), call: call, session: s)

        let summary = """
        Execution Plan generated for: \(objective)
        Mode: \(mode.rawValue)
        Files inspected: \(fileTree.fileCount) total, \(fileTree.swiftFileCount) Swift
        Relevant files identified: \(relevantFiles.count)
        Execution steps: \(plan.steps.count)
        Workers needed: \(plan.workerAssignments.count)
        Plan written to: agent_notes.md
        """
        return .structured(["planFile": .string("agent_notes.md"), "stepCount": .int(plan.steps.count),
                            "relevantFileCount": .int(relevantFiles.count), "workerCount": .int(plan.workerAssignments.count),
                            "mode": .string(mode.rawValue)], summary: summary)
    }

    // MARK: - High-level plan and breakdown

    func planTask(_ call: MCPToolCall) async throws -> MCPToolResult {
        guard let task = call.arguments["task"]?.string else {
            throw MCPToolError("Missing required parameter: task")
        }
        let planId = UUID().uuidString
        let verbs = task
            .components(separatedBy: CharacterSet(charactersIn: ",.;\n"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let steps: [String]
        if verbs.isEmpty {
            steps = ["Analyze requirements", "Implement changes", "Validate with tests", "Summarize outputs"]
        } else {
            steps = verbs.enumerated().map { "\($0.offset + 1). \($0.element)" }
        }
        PlanningPlanStore.shared.store(key: "plan:\(planId)", value: steps.joined(separator: "\n"))
        return .structured(["planId": .string(planId), "steps": .string(steps.joined(separator: "\n"))],
                           summary: "Plan generated for task: \(task)")
    }

    func breakdownTask(_ call: MCPToolCall) async throws -> MCPToolResult {
        guard let planId = call.arguments["planId"]?.string else {
            throw MCPToolError("Missing required parameter: planId")
        }
        guard let plan = PlanningPlanStore.shared.retrieve(key: "plan:\(planId)") else {
            throw MCPToolError("No stored plan found for planId: \(planId)")
        }
        let granular = plan
            .components(separatedBy: .newlines)
            .flatMap { line -> [String] in
                ["\(line)", "- Define acceptance criteria for: \(line)", "- Implement and self-review: \(line)"]
            }
            .joined(separator: "\n")
        PlanningPlanStore.shared.store(key: "plan_breakdown:\(planId)", value: granular)
        return .structured(["breakdown": .string(granular)], summary: "Task breakdown completed for plan \(planId)")
    }

    // MARK: - Intel tools

    func autoFixErrors(_ call: MCPToolCall) async throws -> MCPToolResult {
        let s = try session(for: call)
        let raw = call.arguments["path"]?.string ?? "."
        let target = resolveFileWritingClampedPath(raw, in: s)
        let lintOutput = Self.terminalTaskLintProject(root: target)
        guard lintOutput.contains("issue(s)") else {
            return .text("No lint issues to fix in \(raw)")
        }
        // Candidate Swift files, for resolving the lint output's basenames.
        let candidates: [URL]
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: target.path, isDirectory: &isDir), !isDir.boolValue {
            candidates = target.pathExtension.lowercased() == "swift" ? [target] : []
        } else {
            candidates = SearchWorkspace.swiftFiles(under: target)
        }
        // Findings grouped per file by basename (`Name.swift:line message`).
        var issuesByFile: [String: [String]] = [:]
        var order: [String] = []
        for line in lintOutput.components(separatedBy: .newlines).dropFirst() {
            let parts = line.split(separator: ":", maxSplits: 1)
            guard parts.count == 2 else { continue }
            let file = String(parts[0])
            if issuesByFile[file] == nil { order.append(file) }
            issuesByFile[file, default: []].append(line)
        }
        var fixed: [String] = []
        var unchanged: [String] = []
        var failed: [String] = []
        for file in order.prefix(10) {
            guard let url = candidates.first(where: { $0.lastPathComponent == file }) else {
                failed.append("\(file) (file not found under \(raw))")
                continue
            }
            let rel = relative(url.path, in: s)
            guard let original = text(of: url) else {
                failed.append("\(rel) (could not be read)")
                continue
            }
            let issues = (issuesByFile[file] ?? []).joined(separator: "\n")
            let completion = try await llmToolComplete(
                systemPrompt: "Fix the linting issues in this Swift file. Return ONLY the fixed code.",
                userText: "Issues: \(issues)\n\nFile: \(rel)\n---\n\(original)",
                toolName: "intel_autofix", failureNote: "No file was changed.")
            let fixedCode = Self.llmToolStripFences(completion.text)
            if fixedCode.isEmpty || fixedCode == original {
                unchanged.append(rel)
                continue
            }
            do {
                try await commit(MCPChange(tool: call.name, path: url.path, relativePath: rel, original: original,
                                           proposed: fixedCode, summary: "Auto-fix \(rel)"),
                                 call: call, session: s)
                fixed.append(rel)
            } catch {
                failed.append("\(rel) (\(error.localizedDescription))")
            }
        }
        if fixed.isEmpty {
            throw MCPToolError("intel_autofix is unavailable: no file could be auto-fixed in \(raw). \(failed.isEmpty ? "No file was changed." : "Failures: " + failed.joined(separator: "; "))")
        }
        var summary = "Auto-fix applied to \(fixed.count) file(s) in \(raw): \(fixed.joined(separator: ", "))."
        if !unchanged.isEmpty { summary += " Unchanged: \(unchanged.joined(separator: ", "))." }
        if !failed.isEmpty { summary += " Failed: \(failed.joined(separator: "; "))." }
        return .text(summary)
    }

    func explainCode(_ call: MCPToolCall) async throws -> MCPToolResult {
        let s = try session(for: call)
        guard let path = call.arguments["path"]?.string else {
            throw MCPToolError("Missing required parameter: path")
        }
        let url = try resolveFileReadingPath(path, in: s)
        let content: String
        do {
            content = try String(contentsOf: url, encoding: .utf8)
        } catch {
            throw MCPToolError("Failed to explain \(path): \(error.localizedDescription)")
        }
        let explanation = PlanningSupport.staticExplanation(of: content, at: fileReadingRelativePath(of: url, in: s))
        return .structured(["explanation": .string(explanation)], summary: "Static analysis for \(path)")
    }

    func generateTests(_ call: MCPToolCall) async throws -> MCPToolResult {
        let s = try session(for: call)
        guard let path = call.arguments["path"]?.string else {
            throw MCPToolError("Missing required parameter: path")
        }
        let url = try resolveFileReadingPath(path, in: s)
        let source: String
        do {
            source = try String(contentsOf: url, encoding: .utf8)
        } catch {
            throw MCPToolError("Failed generating tests for \(path): \(error.localizedDescription)")
        }
        let sourceName = url.deletingPathExtension().lastPathComponent
        let testPath = call.arguments["testPath"]?.string ?? "Tests/\(sourceName)Tests.swift"
        let testURL = try resolveFileReadingPath(testPath, in: s)
        let module = PlanningSupport.moduleName(forSourcePath: fileReadingRelativePath(of: url, in: s))
        let body = PlanningSupport.testStub(source: source, sourceName: sourceName, path: path, module: module)
        let types = PlanningSupport.extractTypes(from: source)
        let functionNames = PlanningSupport.extractFunctionNames(from: source)
        let testCount = max(1, functionNames.count + types.count)
        let rel = fileReadingRelativePath(of: testURL, in: s)
        try await commit(MCPChange(tool: call.name, path: testURL.path, relativePath: rel, original: text(of: testURL),
                                   proposed: body, summary: "Generate tests for \(path) at \(rel)"), call: call, session: s)
        return .structured(["test_path": .string(testPath), "test_count": .int(testCount),
                            "types_count": .int(types.count), "functions_count": .int(functionNames.count)],
                           summary: "Tests generated for \(path) with \(testCount) test methods")
    }

    // MARK: - User question handoff

    func askUser(_ call: MCPToolCall) async throws -> MCPToolResult {
        guard let question = call.arguments["question"]?.string,
              !question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw MCPToolError("Missing required argument: 'question' must be a non-empty string.")
        }
        let allowsMultiple = call.bool("allowsMultipleAnswers") ?? false
        let userSpec = call.bool("userSpecification") ?? false
        var choices: [PlanningQuestionChoice] = []
        if let choicesRaw = call.arguments["choices"]?.array {
            for raw in choicesRaw {
                let obj = raw.object ?? [:]
                if let choiceText = obj["choice"]?.string {
                    choices.append(PlanningQuestionChoice(choice: choiceText,
                                                          assistRecommended: obj["assistRecommended"]?.bool ?? false))
                }
            }
        }
        if choices.isEmpty && !userSpec {
            throw MCPToolError("At least one choice is required when userSpecification is false.")
        }
        let questionId = UUID().uuidString
        let choicesJSON: [AnyJSON] = choices.map {
            ["choice": .string($0.choice), "assistRecommended": .bool($0.assistRecommended)]
        }
        var summary = "Question for the user (pending — present this question to the user; this tool does not wait for an answer): \(question)"
        if !choices.isEmpty {
            summary += "\nChoices: " + choices.map { $0.assistRecommended ? "\($0.choice) (recommended)" : $0.choice }.joined(separator: " | ")
        }
        if userSpec { summary += "\nThe user may also give a free-form answer." }
        return .structured(["questionId": .string(questionId), "question": .string(question),
                            "status": .string("pending"), "allowsMultipleAnswers": .bool(allowsMultiple),
                            "userSpecification": .bool(userSpec), "choices": .array(choicesJSON)], summary: summary)
    }

    // MARK: - Completion report

    func reportToUser(_ call: MCPToolCall) async throws -> MCPToolResult {
        let rawSummary = call.arguments["summary"]?.string
            ?? call.arguments["message"]?.string
            ?? call.arguments["report"]?.string
            ?? call.arguments["text"]?.string
            ?? "Task execution completed."
        let status = call.arguments["status"]?.string ?? "completed"
        let files = call.strings("filesModified") ?? []
        let verification = call.arguments["verification"]?.string ?? ""
        var finalContent = PlanningSupport.normalizeAndRenderMarkdown(rawSummary)
        if !files.isEmpty, let first = files.first, !finalContent.contains(first) {
            finalContent += "\n\n**Modified Files:**\n" + files.map { "- `\($0)`" }.joined(separator: "\n")
        }
        if !verification.isEmpty, !finalContent.contains(verification) {
            finalContent += "\n\n**Verification:**\n\(verification)"
        }
        return .structured(["status": .string(status), "filesCount": .int(files.count),
                            "renderedLength": .int(finalContent.count)], summary: finalContent)
    }
}

/// One choice of a `plan-AskUser` question, as presented to the user.
struct PlanningQuestionChoice: Sendable {
    var choice: String
    var assistRecommended: Bool
}
