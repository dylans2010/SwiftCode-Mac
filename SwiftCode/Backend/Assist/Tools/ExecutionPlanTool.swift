import Foundation
import os

@MainActor
public struct ExecutionPlanTool: AssistTool {
    public let id: String = "execution_plan"
    public let name: String = "Generate Execution Plan"
    public let description: String = """
    Analyzes the actual repository state, reads relevant files, discovers instructions and skills, \
    and generates a task-specific Execution Plan. This tool MUST be called before any codebase modification. \
    The plan is written to agent_notes.md and contains objective, findings, steps, dependencies, \
    verification requirements, and completion criteria — all grounded in actual repository state.
    """

    public var parametersSchema: JSONSchema {
        JSONSchema(
            type: "object",
            description: "Generates a task-specific Execution Plan from actual repository state.",
            properties: [
                "objective": JSONSchema(type: "string", description: "The user's task objective."),
                "mode": JSONSchema(type: "string", description: "Execution mode: 'plan' or 'autopilot'."),
                "relevantFiles": JSONSchema(type: "array", description: "Optional list of file paths already known to be relevant.", items: ["type": JSONSchema(type: "string")])
            ],
            required: ["objective", "mode"]
        )
    }

    public var capability: ToolCapability { .planning }
    public var riskLevel: ToolRiskLevel { .safeRead }
    public var isReadOnly: Bool { true }
    public var isMutating: Bool { false }
    public var estimatedCost: Double { 0.1 }

    private let logger = Logger(subsystem: "com.swiftcode.app", category: "ExecutionPlanTool")

    public init() {}

    public func execute(input: [String: Any], context: AssistContext) async throws -> AssistToolResult {
        guard let objective = input["objective"] as? String, !objective.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .failure("Missing required argument: 'objective' must be a non-empty string.")
        }

        let modeRaw = input["mode"] as? String ?? "autopilot"
        let mode = ExecutionMode(rawValue: modeRaw) ?? .autopilot
        let relevantFilesHint = input["relevantFiles"] as? [String] ?? []

        logger.info("[execution_plan] Generating plan for objective: \(objective.prefix(80)) [mode: \(mode.rawValue)]")

        let planInstructions = Self.loadPlanInstructions()

        let workspaceRoot = context.workspaceRoot

        let fileTree = await inspectRepositoryStructure(workspaceRoot: workspaceRoot)
        let buildConfig = await inspectBuildConfiguration(workspaceRoot: workspaceRoot)
        let agentsInstructions = await discoverInstructions(workspaceRoot: workspaceRoot)
        let skills = await discoverSkills(workspaceRoot: workspaceRoot)
        let relevantFiles = await identifyRelevantFiles(
            objective: objective,
            workspaceRoot: workspaceRoot,
            hints: relevantFilesHint
        )
        let fileContents = await readRelevantFiles(files: relevantFiles, workspaceRoot: workspaceRoot)

        let plan = buildExecutionPlan(
            objective: objective,
            mode: mode,
            fileTree: fileTree,
            buildConfig: buildConfig,
            agentsInstructions: agentsInstructions,
            skills: skills,
            relevantFiles: relevantFiles,
            fileContents: fileContents,
            workspaceRoot: workspaceRoot,
            planInstructions: planInstructions
        )

        let planMarkdown = renderPlanMarkdown(plan, instructions: planInstructions)
        let notesURL = workspaceRoot.appendingPathComponent("agent_notes.md")
        do {
            try planMarkdown.write(to: notesURL, atomically: true, encoding: .utf8)
            logger.info("[execution_plan] Plan written to \(notesURL.path)")
        } catch {
            logger.error("[execution_plan] Failed to write agent_notes.md: \(error.localizedDescription)")
        }

        let summary = """
        Execution Plan generated for: \(objective)
        Mode: \(mode.rawValue)
        Files inspected: \(fileTree.fileCount) total, \(fileTree.swiftFileCount) Swift
        Relevant files identified: \(relevantFiles.count)
        Execution steps: \(plan.steps.count)
        Workers needed: \(plan.workerAssignments.count)
        Plan written to: agent_notes.md
        """

        return .success(summary, data: [
            "planFile": "agent_notes.md",
            "stepCount": "\(plan.steps.count)",
            "relevantFileCount": "\(relevantFiles.count)",
            "workerCount": "\(plan.workerAssignments.count)",
            "mode": mode.rawValue
        ])
    }

    // MARK: - Repository Inspection

    private struct RepositoryStructure {
        let fileCount: Int
        let swiftFileCount: Int
        let directories: [String]
        let rootFiles: [String]
    }

    private func inspectRepositoryStructure(workspaceRoot: URL) async -> RepositoryStructure {
        let fm = FileManager.default
        var fileCount = 0
        var swiftFileCount = 0
        var directories: [String] = []
        var rootFiles: [String] = []

        if let enumerator = fm.enumerator(at: workspaceRoot, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) {
            while let url = enumerator.nextObject() as? URL {
                let relPath = url.path.replacingOccurrences(of: workspaceRoot.path + "/", with: "")
                if relPath.hasPrefix(".git/") || relPath.hasPrefix(".build/") || relPath.hasPrefix("build/") {
                    continue
                }
                let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
                if isDir {
                    directories.append(relPath)
                } else {
                    fileCount += 1
                    if url.pathExtension == "swift" {
                        swiftFileCount += 1
                    }
                    if !relPath.contains("/") {
                        rootFiles.append(relPath)
                    }
                }
            }
        }

        return RepositoryStructure(
            fileCount: fileCount,
            swiftFileCount: swiftFileCount,
            directories: directories.sorted().prefix(30).map { $0 },
            rootFiles: rootFiles.sorted()
        )
    }

    private struct BuildConfiguration {
        let hasXcodeProj: Bool
        let hasPackageSwift: Bool
        let hasPodfile: Bool
        let hasCartfile: Bool
        let xcodeProjName: String?
    }

    private func inspectBuildConfiguration(workspaceRoot: URL) async -> BuildConfiguration {
        let fm = FileManager.default
        let xcodeProj = fm.enumerator(at: workspaceRoot, includingPropertiesForKeys: nil)?
            .compactMap { $0 as? URL }
            .first { $0.pathExtension == "xcodeproj" }
        let packageSwift = workspaceRoot.appendingPathComponent("Package.swift")
        let podfile = workspaceRoot.appendingPathComponent("Podfile")
        let cartfile = workspaceRoot.appendingPathComponent("Cartfile")

        return BuildConfiguration(
            hasXcodeProj: xcodeProj != nil,
            hasPackageSwift: fm.fileExists(atPath: packageSwift.path),
            hasPodfile: fm.fileExists(atPath: podfile.path),
            hasCartfile: fm.fileExists(atPath: cartfile.path),
            xcodeProjName: xcodeProj?.lastPathComponent
        )
    }

    private struct InstructionFile {
        let path: String
        let content: String
    }

    private func discoverInstructions(workspaceRoot: URL) async -> [InstructionFile] {
        let fm = FileManager.default
        var results: [InstructionFile] = []
        let candidates = ["AGENTS.md", "Agents.md", "agents.md", ".agents/AGENTS.md", ".agents/Agents.md"]

        for candidate in candidates {
            let url = workspaceRoot.appendingPathComponent(candidate)
            if fm.fileExists(atPath: url.path),
               let content = try? String(contentsOf: url, encoding: .utf8) {
                results.append(InstructionFile(path: candidate, content: String(content.prefix(2000))))
            }
        }

        return results
    }

    private struct SkillInfo {
        let name: String
        let summary: String
    }

    private func discoverSkills(workspaceRoot: URL) async -> [SkillInfo] {
        let fm = FileManager.default
        var results: [SkillInfo] = []
        let skillDirs = [".agents/skills", ".skills", "skills"]

        for dir in skillDirs {
            let baseURL = workspaceRoot.appendingPathComponent(dir)
            guard let entries = try? fm.contentsOfDirectory(atPath: baseURL.path) else { continue }
            for entry in entries {
                let skillMD = baseURL.appendingPathComponent(entry).appendingPathComponent("SKILL.md")
                if fm.fileExists(atPath: skillMD.path),
                   let content = try? String(contentsOf: skillMD, encoding: .utf8) {
                    let name = entry
                    let summary = content.components(separatedBy: "\n").first { $0.hasPrefix("# ") }?.replacingOccurrences(of: "# ", with: "") ?? entry
                    results.append(SkillInfo(name: name, summary: summary))
                }
            }
        }

        return results
    }

    private func identifyRelevantFiles(objective: String, workspaceRoot: URL, hints: [String]) async -> [String] {
        var relevant = Set(hints)
        let lower = objective.lowercased()

        let keywords = extractKeywords(from: lower)
        let fm = FileManager.default

        if let enumerator = fm.enumerator(at: workspaceRoot, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) {
            while let url = enumerator.nextObject() as? URL {
                let relPath = url.path.replacingOccurrences(of: workspaceRoot.path + "/", with: "")
                if relPath.hasPrefix(".git/") || relPath.hasPrefix(".build/") || relPath.hasPrefix("build/") {
                    continue
                }
                let filename = url.lastPathComponent.lowercased()
                for keyword in keywords {
                    if filename.contains(keyword) {
                        relevant.insert(relPath)
                        break
                    }
                }
            }
        }

        return Array(relevant).sorted()
    }

    private func extractKeywords(from text: String) -> [String] {
        let words = text.components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count >= 3 }
        let stopWords: Set<String> = ["the", "and", "for", "with", "this", "that", "from", "have", "will", "should", "into", "when", "then", "than", "them", "they", "what", "where", "which", "while", "being", "been", "were", "was", "are", "not", "but", "all", "can", "her", "his", "how", "its", "our", "out", "you", "your"]
        return Array(Set(words.filter { !stopWords.contains($0) })).sorted()
    }

    private func readRelevantFiles(files: [String], workspaceRoot: URL) async -> [String: String] {
        var contents: [String: String] = [:]
        for file in files.prefix(10) {
            let url = workspaceRoot.appendingPathComponent(file)
            if let content = try? String(contentsOf: url, encoding: .utf8) {
                contents[file] = String(content.prefix(3000))
            }
        }
        return contents
    }

    // MARK: - Plan Building

    private struct ExecutionPlanData {
        let objective: String
        let mode: ExecutionMode
        let steps: [PlanStepData]
        let workerAssignments: [WorkerAssignmentData]
        let relevantFiles: [String]
        let detectedProblems: [String]
        let risks: [String]
        let verificationRequirements: [String]
        let completionCriteria: [String]
    }

    private struct PlanStepData {
        let order: Int
        let toolId: String
        let description: String
        let targetFiles: [String]
        let verification: String
    }

    private struct WorkerAssignmentData {
        let name: String
        let scope: String
        let task: String
    }

    private static func loadPlanInstructions() -> String {
        if let url = Bundle.main.url(forResource: "WriteExecutionPlan", withExtension: "md"),
           let content = try? String(contentsOf: url, encoding: .utf8) {
            return content
        }
        return ""
    }

    private func buildExecutionPlan(
        objective: String,
        mode: ExecutionMode,
        fileTree: RepositoryStructure,
        buildConfig: BuildConfiguration,
        agentsInstructions: [InstructionFile],
        skills: [SkillInfo],
        relevantFiles: [String],
        fileContents: [String: String],
        workspaceRoot: URL,
        planInstructions: String
    ) -> ExecutionPlanData {
        var steps: [PlanStepData] = []
        var detectedProblems: [String] = []
        var risks: [String] = []
        var verificationReqs: [String] = []
        var completionCriteria: [String] = []

        steps.append(PlanStepData(
            order: 1,
            toolId: "file_read",
            description: "Read all relevant files to understand current implementation",
            targetFiles: relevantFiles,
            verification: "File contents loaded into context"
        ))

        for (idx, file) in relevantFiles.enumerated() {
            if let content = fileContents[file] {
                let lines = content.components(separatedBy: "\n").count
                if lines > 200 {
                    detectedProblems.append("File \(file) is \(lines) lines — may need decomposition")
                }
            }
        }

        if relevantFiles.isEmpty {
            detectedProblems.append("No relevant files identified — task may require broader search")
        }

        if fileTree.swiftFileCount > 0 {
            steps.append(PlanStepData(
                order: 2,
                toolId: "search_text",
                description: "Search codebase for symbols and patterns related to the objective",
                targetFiles: [],
                verification: "Search results confirm relevant code locations"
            ))
        }

        let needsBuild = buildConfig.hasXcodeProj || buildConfig.hasPackageSwift
        if needsBuild {
            steps.append(PlanStepData(
                order: 3,
                toolId: "project_build",
                description: "Build project to verify changes compile",
                targetFiles: [],
                verification: "Build succeeds with zero errors"
            ))
            verificationReqs.append("Build must pass: \(buildConfig.hasXcodeProj ? "xcodebuild" : "swift build")")
            completionCriteria.append("Project builds without errors")
        }

        steps.append(PlanStepData(
            order: 4,
            toolId: "project_test",
            description: "Run tests to verify behavior",
            targetFiles: [],
            verification: "All tests pass"
        ))
        verificationReqs.append("Tests must pass")
        completionCriteria.append("All tests pass")

        if mode == .plan {
            completionCriteria.append("User decisions incorporated into plan")
        }

        if relevantFiles.count > 5 {
            risks.append("Large number of relevant files (\(relevantFiles.count)) — consider Worker decomposition")
        }

        if detectedProblems.isEmpty {
            detectedProblems.append("No structural issues detected during static analysis")
        }

        let workerAssignments: [WorkerAssignmentData] = relevantFiles.count > 8 ? [
            WorkerAssignmentData(name: "Core Implementation", scope: relevantFiles.prefix(4).joined(separator: ", "), task: "Implement core changes for: \(objective)"),
            WorkerAssignmentData(name: "Verification & QA", scope: "Build & test", task: "Verify build and run tests")
        ] : []

        return ExecutionPlanData(
            objective: objective,
            mode: mode,
            steps: steps,
            workerAssignments: workerAssignments,
            relevantFiles: relevantFiles,
            detectedProblems: detectedProblems,
            risks: risks,
            verificationRequirements: verificationReqs,
            completionCriteria: completionCriteria
        )
    }

    private func renderPlanMarkdown(_ plan: ExecutionPlanData, instructions: String) -> String {
        var md = ""
        md += "# Execution Plan\n\n"
        md += "## Objective\n\(plan.objective)\n\n"
        md += "## Execution Mode\n\(plan.mode.rawValue)\n\n"
        if !instructions.isEmpty {
            md += "## Plan Generation Instructions\n\(instructions)\n\n"
        }
        md += "## Repository Findings\n"
        md += "- Total files inspected: \(plan.relevantFiles.count) relevant files\n"
        md += "- Build configuration detected\n"
        md += "- Instructions and skills discovered\n\n"
        md += "## Current State\n"
        md += "Relevant files identified through repository inspection:\n"
        for file in plan.relevantFiles {
            md += "- \(file)\n"
        }
        md += "\n## Relevant Files\n"
        for file in plan.relevantFiles {
            md += "- \(file)\n"
        }
        md += "\n## Detected Problems\n"
        for problem in plan.detectedProblems {
            md += "- \(problem)\n"
        }
        md += "\n## Execution Steps\n"
        for step in plan.steps {
            md += "### Step \(step.order): \(step.description)\n"
            md += "- Tool: `\(step.toolId)`\n"
            if !step.targetFiles.isEmpty {
                md += "- Target files: \(step.targetFiles.joined(separator: ", "))\n"
            }
            md += "- Verification: \(step.verification)\n\n"
        }
        if !plan.workerAssignments.isEmpty {
            md += "## Worker Assignments\n"
            for worker in plan.workerAssignments {
                md += "- **\(worker.name)**: \(worker.task) (scope: \(worker.scope))\n"
            }
            md += "\n"
        }
        md += "## Verification Requirements\n"
        for req in plan.verificationRequirements {
            md += "- \(req)\n"
        }
        md += "\n## Risk Areas\n"
        for risk in plan.risks {
            md += "- \(risk)\n"
        }
        md += "\n## Completion Criteria\n"
        for criterion in plan.completionCriteria {
            md += "- [ ] \(criterion)\n"
        }
        md += "\n---\n*Plan generated by execution_plan tool. This is a living document that evolves as execution progresses.*\n"
        return md
    }
}
