import Foundation
import SwiftCodeAssistant
import SwiftCodeIDECore

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
                                       "userSpecification": Schema.boolean("Whether the user may provide a free-form response."),
                                       "input_type": Schema.string("Legacy form: 'text' for a free-form question or 'selection' for a choice question. 'text' implies userSpecification=true; 'selection' reads its options from 'options'."),
                                       "options": Schema.array(Schema.str, "Legacy form: the choice strings for a 'selection' input_type question.")],
                                      required: ["question"]),
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

    func autoFixErrors(_ call: MCPToolCall) async throws -> MCPToolResult {
        let s = try session(for: call)
        let raw = call.arguments["path"]?.string ?? "."
        let target = resolveFileWritingClampedPath(raw, in: s)
        let lintOutput = Self.terminalTaskLintProject(root: target)
        guard lintOutput.contains("issue(s)") else {
            return .text("No lint issues to fix in \(raw)")
        }
        let candidates: [URL]
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: target.path, isDirectory: &isDir), !isDir.boolValue {
            candidates = target.pathExtension.lowercased() == "swift" ? [target] : []
        } else {
            candidates = SearchWorkspace.swiftFiles(under: target)
        }
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
        let systemPrompt = "Explain the code below in detail: what it does, how its parts fit together, and anything surprising or risky. Be concrete and cite the code."
        do {
            let completion = try await llmToolComplete(systemPrompt: systemPrompt, userText: content, toolName: "intel_explain_code",
                                                       failureNote: "Falling back to static analysis.")
            return .structured(["explanation": .string(completion.text)], summary: "Explanation for \(path)")
        } catch let error as MCPToolError {
            let staticExplanation = PlanningSupport.staticExplanation(of: content, at: fileReadingRelativePath(of: url, in: s))
            let explanation = staticExplanation + "\n\n_Note: no LLM was available (\(error.message)), so this is a static structural outline, not a model explanation._"
            return .structured(["explanation": .string(explanation)], summary: "Static analysis for \(path) (no LLM available)")
        }
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

    func askUser(_ call: MCPToolCall) async throws -> MCPToolResult {
        guard let question = call.arguments["question"]?.string,
              !question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw MCPToolError("Missing required argument: 'question' must be a non-empty string.")
        }
        let allowsMultiple = call.bool("allowsMultipleAnswers") ?? false
        var userSpec = call.bool("userSpecification") ?? false
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
        if let inputType = call.arguments["input_type"]?.string?.lowercased() {
            switch inputType {
            case "text":
                userSpec = true
            case "selection":
                let options = call.strings("options") ?? []
                choices = options.map { PlanningQuestionChoice(choice: $0, assistRecommended: false) }
            default:
                throw MCPToolError("Unknown input_type '\(inputType)': expected 'text' or 'selection'.")
            }
        }
        if choices.isEmpty && !userSpec {
            throw MCPToolError("At least one choice is required when userSpecification is false.")
        }
        let questionUUID = UUID()
        let questionId = questionUUID.uuidString
        let inputType: AgentPendingQuestion.InputType = userSpec && choices.isEmpty
            ? .text
            : .selection(options: choices.map { $0.choice })
        await PendingQuestionStore.shared.register(
            AgentPendingQuestion(id: questionUUID, question: question, inputType: inputType),
            allowsMultipleAnswers: allowsMultiple, userSpecification: userSpec)
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

struct PlanningQuestionChoice: Sendable {
    var choice: String
    var assistRecommended: Bool
}
