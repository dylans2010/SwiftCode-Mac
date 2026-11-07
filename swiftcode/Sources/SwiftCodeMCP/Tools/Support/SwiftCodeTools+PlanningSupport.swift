import Foundation

enum PlanningSupport {

}

enum PlanningExecutionMode: String {
    case plan = "Plan"
    case autopilot = "Autopilot"

    init(documented raw: String) {
        self = raw.lowercased() == "plan" ? .plan : .autopilot
    }
}

final class PlanningPlanStore: @unchecked Sendable {
    static let shared = PlanningPlanStore()
    private let lock = NSLock()
    private var values: [String: String] = [:]
    private init() {}

    func store(key: String, value: String) { lock.withLock { values[key] = value } }
    func retrieve(key: String) -> String? { lock.withLock { values[key] } }
}

extension PlanningSupport {

    struct RepositoryStructure {
        var fileCount: Int
        var swiftFileCount: Int
        var directories: [String]
        var rootFiles: [String]
    }

    struct BuildConfiguration {
        var hasXcodeProj: Bool
        var hasPackageSwift: Bool
        var hasPodfile: Bool
        var hasCartfile: Bool
        var xcodeProjName: String?
    }

    struct InstructionFile {
        var path: String
        var content: String
    }

    struct SkillInfo {
        var name: String
        var summary: String
    }

    struct PlanStep {
        var order: Int
        var toolId: String
        var description: String
        var targetFiles: [String]
        var verification: String
    }

    struct WorkerAssignment {
        var name: String
        var scope: String
        var task: String
    }

    struct ExecutionPlanData {
        var objective: String
        var mode: PlanningExecutionMode
        var steps: [PlanStep]
        var workerAssignments: [WorkerAssignment]
        var relevantFiles: [String]
        var detectedProblems: [String]
        var risks: [String]
        var verificationRequirements: [String]
        var completionCriteria: [String]
    }

    static func inspectRepositoryStructure(workspaceRoot: URL) -> RepositoryStructure {
        let fm = FileManager.default
        var fileCount = 0
        var swiftFileCount = 0
        var directories: [String] = []
        var rootFiles: [String] = []
        if let enumerator = fm.enumerator(at: workspaceRoot, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) {
            while let url = enumerator.nextObject() as? URL {
                let relPath = url.path.replacingOccurrences(of: workspaceRoot.path + "/", with: "")
                if relPath.hasPrefix(".git/") || relPath.hasPrefix(".build/") || relPath.hasPrefix("build/") { continue }
                let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
                if isDir {
                    directories.append(relPath)
                } else {
                    fileCount += 1
                    if url.pathExtension == "swift" { swiftFileCount += 1 }
                    if !relPath.contains("/") { rootFiles.append(relPath) }
                }
            }
        }
        return RepositoryStructure(fileCount: fileCount, swiftFileCount: swiftFileCount,
                                   directories: directories.sorted().prefix(30).map { $0 }, rootFiles: rootFiles.sorted())
    }

    static func inspectBuildConfiguration(workspaceRoot: URL) -> BuildConfiguration {
        let fm = FileManager.default
        let xcodeProj = fm.enumerator(at: workspaceRoot, includingPropertiesForKeys: nil)?
            .compactMap { $0 as? URL }
            .first { $0.pathExtension == "xcodeproj" }
        return BuildConfiguration(
            hasXcodeProj: xcodeProj != nil,
            hasPackageSwift: fm.fileExists(atPath: workspaceRoot.appendingPathComponent("Package.swift").path),
            hasPodfile: fm.fileExists(atPath: workspaceRoot.appendingPathComponent("Podfile").path),
            hasCartfile: fm.fileExists(atPath: workspaceRoot.appendingPathComponent("Cartfile").path),
            xcodeProjName: xcodeProj?.lastPathComponent)
    }

    static func discoverInstructions(workspaceRoot: URL) -> [InstructionFile] {
        let fm = FileManager.default
        var results: [InstructionFile] = []
        for candidate in ["AGENTS.md", "Agents.md", "agents.md", ".agents/AGENTS.md", ".agents/Agents.md"] {
            let url = workspaceRoot.appendingPathComponent(candidate)
            if fm.fileExists(atPath: url.path), let content = try? String(contentsOf: url, encoding: .utf8) {
                results.append(InstructionFile(path: candidate, content: String(content.prefix(2000))))
            }
        }
        return results
    }

    static func discoverSkills(workspaceRoot: URL) -> [SkillInfo] {
        let fm = FileManager.default
        var results: [SkillInfo] = []
        for dir in [".agents/skills", ".skills", "skills"] {
            let baseURL = workspaceRoot.appendingPathComponent(dir)
            guard let entries = try? fm.contentsOfDirectory(atPath: baseURL.path) else { continue }
            for entry in entries {
                let skillMD = baseURL.appendingPathComponent(entry).appendingPathComponent("SKILL.md")
                if fm.fileExists(atPath: skillMD.path), let content = try? String(contentsOf: skillMD, encoding: .utf8) {
                    let summary = content.components(separatedBy: "\n").first { $0.hasPrefix("# ") }?
                        .replacingOccurrences(of: "# ", with: "") ?? entry
                    results.append(SkillInfo(name: entry, summary: summary))
                }
            }
        }
        return results
    }

    static func extractKeywords(from text: String) -> [String] {
        let words = text.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { $0.count >= 3 }
        let stopWords: Set<String> = ["the", "and", "for", "with", "this", "that", "from", "have", "will", "should",
                                      "into", "when", "then", "than", "them", "they", "what", "where", "which", "while",
                                      "being", "been", "were", "was", "are", "not", "but", "all", "can", "her", "his",
                                      "how", "its", "our", "out", "you", "your"]
        return Array(Set(words.filter { !stopWords.contains($0) })).sorted()
    }

    static func identifyRelevantFiles(objective: String, workspaceRoot: URL, hints: [String]) -> [String] {
        var relevant = Set(hints)
        let keywords = extractKeywords(from: objective.lowercased())
        let fm = FileManager.default
        if let enumerator = fm.enumerator(at: workspaceRoot, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) {
            while let url = enumerator.nextObject() as? URL {
                let relPath = url.path.replacingOccurrences(of: workspaceRoot.path + "/", with: "")
                if relPath.hasPrefix(".git/") || relPath.hasPrefix(".build/") || relPath.hasPrefix("build/") { continue }
                let filename = url.lastPathComponent.lowercased()
                for keyword in keywords where filename.contains(keyword) {
                    relevant.insert(relPath)
                    break
                }
            }
        }
        return Array(relevant).sorted()
    }

    static func readRelevantFiles(files: [String], workspaceRoot: URL) -> [String: String] {
        var contents: [String: String] = [:]
        for file in files.prefix(10) {
            let url = workspaceRoot.appendingPathComponent(file)
            if let content = try? String(contentsOf: url, encoding: .utf8) {
                contents[file] = String(content.prefix(3000))
            }
        }
        return contents
    }

    static func buildExecutionPlan(objective: String, mode: PlanningExecutionMode,
                                               fileTree: RepositoryStructure, buildConfig: BuildConfiguration,
                                               agentsInstructions: [InstructionFile], skills: [SkillInfo],
                                               relevantFiles: [String], fileContents: [String: String]) -> ExecutionPlanData {
        var steps: [PlanStep] = []
        var detectedProblems: [String] = []
        var risks: [String] = []
        var verificationReqs: [String] = []
        var completionCriteria: [String] = []

        steps.append(PlanStep(order: 1, toolId: "file_read",
                              description: "Read all relevant files to understand current implementation",
                              targetFiles: relevantFiles, verification: "File contents loaded into context"))

        for file in relevantFiles {
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
            steps.append(PlanStep(order: 2, toolId: "search_text",
                                  description: "Search codebase for symbols and patterns related to the objective",
                                  targetFiles: [], verification: "Search results confirm relevant code locations"))
        }

        let needsBuild = buildConfig.hasXcodeProj || buildConfig.hasPackageSwift
        if needsBuild {
            steps.append(PlanStep(order: 3, toolId: "project_build",
                                  description: "Build project to verify changes compile",
                                  targetFiles: [], verification: "Build succeeds with zero errors"))
            verificationReqs.append("Build must pass: \(buildConfig.hasXcodeProj ? "xcodebuild" : "swift build")")
            completionCriteria.append("Project builds without errors")
        }

        steps.append(PlanStep(order: 4, toolId: "project_test",
                              description: "Run tests to verify behavior",
                              targetFiles: [], verification: "All tests pass"))
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

        let workerAssignments: [WorkerAssignment] = relevantFiles.count > 8 ? [
            WorkerAssignment(name: "Core Implementation", scope: relevantFiles.prefix(4).joined(separator: ", "),
                             task: "Implement core changes for: \(objective)"),
            WorkerAssignment(name: "Verification & QA", scope: "Build & test", task: "Verify build and run tests")
        ] : []

        return ExecutionPlanData(objective: objective, mode: mode, steps: steps, workerAssignments: workerAssignments,
                                 relevantFiles: relevantFiles, detectedProblems: detectedProblems, risks: risks,
                                 verificationRequirements: verificationReqs, completionCriteria: completionCriteria)
    }

    static func renderPlanMarkdown(_ plan: ExecutionPlanData) -> String {
        var md = ""
        md += "# Execution Plan\n\n"
        md += "## Objective\n\(plan.objective)\n\n"
        md += "## Execution Mode\n\(plan.mode.rawValue)\n\n"
        md += "## Repository Findings\n"
        md += "- Total files inspected: \(plan.relevantFiles.count) relevant files\n"
        md += "- Build configuration detected\n"
        md += "- Instructions and skills discovered\n\n"
        md += "## Current State\n"
        md += "Relevant files identified through repository inspection:\n"
        for file in plan.relevantFiles { md += "- \(file)\n" }
        md += "\n## Relevant Files\n"
        for file in plan.relevantFiles { md += "- \(file)\n" }
        md += "\n## Detected Problems\n"
        for problem in plan.detectedProblems { md += "- \(problem)\n" }
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
        for req in plan.verificationRequirements { md += "- \(req)\n" }
        md += "\n## Risk Areas\n"
        for risk in plan.risks { md += "- \(risk)\n" }
        md += "\n## Completion Criteria\n"
        for criterion in plan.completionCriteria { md += "- [ ] \(criterion)\n" }
        md += "\n---\n*Plan generated by execution_plan tool. This is a living document that evolves as execution progresses.*\n"
        return md
    }

    static func extractFunctionNames(from source: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: "\\bfunc\\s+([A-Za-z_][A-Za-z0-9_]*)", options: []) else { return [] }
        let range = NSRange(location: 0, length: source.utf16.count)
        return regex.matches(in: source, options: [], range: range).compactMap { match -> String? in
            guard match.numberOfRanges > 1, let r = Range(match.range(at: 1), in: source) else { return nil }
            return String(source[r])
        }
    }

    struct DeclaredType: Sendable, Equatable {
        var kind: String
        var name: String
    }

    static func extractDeclaredTypes(from content: String) -> [DeclaredType] {
        guard let regex = try? NSRegularExpression(
            pattern: "^(?:public |private |internal |fileprivate )?(?:final )?(class|struct|enum|actor)\\s+([A-Za-z0-9_]+)",
            options: []) else { return [] }
        var types: [DeclaredType] = []
        for line in content.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let range = NSRange(location: 0, length: trimmed.utf16.count)
            guard let match = regex.firstMatch(in: trimmed, options: [], range: range),
                  match.numberOfRanges > 2,
                  let kindRange = Range(match.range(at: 1), in: trimmed),
                  let nameRange = Range(match.range(at: 2), in: trimmed) else { continue }
            let name = String(trimmed[nameRange])
            guard !name.contains("{"), !name.contains(":") else { continue }
            types.append(DeclaredType(kind: String(trimmed[kindRange]), name: name))
        }
        return types
    }

    static func extractTypes(from content: String) -> [String] {
        extractDeclaredTypes(from: content).map(\.name)
    }

    static func extractImports(from content: String) -> [String] {
        var imports: [String] = []
        for line in content.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("import ") else { continue }
            let rest = trimmed.dropFirst("import ".count).trimmingCharacters(in: .whitespaces)
            let name = rest.components(separatedBy: CharacterSet(charactersIn: " .")).first ?? ""
            if !name.isEmpty { imports.append(name) }
        }
        return imports
    }

    static func moduleName(forSourcePath path: String) -> String {
        let components = path.components(separatedBy: "/").filter { !$0.isEmpty }
        if let idx = components.firstIndex(of: "Sources"), idx + 1 < components.count {
            return components[idx + 1]
        }
        if components.count >= 2 { return components[components.count - 2] }
        return "App"
    }

    static func testStub(source: String, sourceName: String, path: String, module: String) -> String {
        let functionNames = extractFunctionNames(from: source)
        let types = extractTypes(from: source)
        var body = """
        import XCTest
        @testable import \(module)

        /// Generated tests for \(path)
        final class \(sourceName)Tests: XCTestCase {

            override func setUpWithError() throws {
                try super.setUpWithError()
                // Put setup code here. This method is called before the invocation of each test method in the class.
            }

            override func tearDownWithError() throws {
                // Put teardown code here. This method is called after the invocation of each test method in the class.
                try super.tearDownWithError()
            }

        """
        if functionNames.isEmpty && types.isEmpty {
            body += """
            func testPlaceholder() {
                // No functions detected in source file. Add your tests here.
                XCTAssertTrue(true, "Replace with actual test implementation")
            }

        """
        } else {
            for typeName in types.prefix(10) {
                body += """
            // MARK: - Tests for \(typeName)

            func test\(typeName)_Initialization() {
                // TODO: Test initialization of \(typeName)
                // Example:
                // let instance = \(typeName)()
                // XCTAssertNotNil(instance, "\(typeName) should initialize")
            }

        """
            }
            for funcName in functionNames.prefix(10) {
                body += """
            func test_\(funcName)() {
                // TODO: Test \(funcName) behavior
                // Example:
                // let result = someInstance.\(funcName)()
                // XCTAssertEqual(result, expectedValue, "\(funcName) should return expected value")
            }

        """
            }
        }
        body += """
            func testPerformance() {
                measure {
                    // Put performance test code here
                }
            }
        }

        """
        return body
    }

    static func staticExplanation(of content: String, at path: String) -> String {
        let lines = content.components(separatedBy: .newlines)
        let imports = extractImports(from: content)
        let types = extractDeclaredTypes(from: content)
        let functions = extractFunctionNames(from: content)
        var out = "Static analysis of \(path) (no LLM explanation is available in SwiftCode's MCP host)."
        out += "\nFile: \(path), Lines: \(lines.count)."
        out += "\nImports: " + (imports.isEmpty ? "none" : imports.joined(separator: ", ")) + "."
        if types.isEmpty {
            out += "\nTypes: none declared."
        } else {
            out += "\nTypes: " + types.map { "\($0.kind) \($0.name)" }.joined(separator: ", ") + "."
        }
        if functions.isEmpty {
            out += "\nFunctions: none declared."
        } else {
            out += "\nFunctions: " + functions.joined(separator: ", ") + "."
        }
        return out
    }

    static func normalizeAndRenderMarkdown(_ input: String) -> String {
        var text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("```json") && text.hasSuffix("```") {
            let inner = text.dropFirst(7).dropLast(3).trimmingCharacters(in: .whitespacesAndNewlines)
            if let data = inner.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let summary = json["summary"] as? String {
                text = summary
            }
        }
        text = text.replacingOccurrences(of: "\\`", with: "`")
        text = text.replacingOccurrences(of: "\\*", with: "*")
        text = text.replacingOccurrences(of: "\\_", with: "_")
        text = text.replacingOccurrences(of: "\\#", with: "#")
        let annoyingQuestions = [
            "Want me to apply the fixes via a new use_workers batch?",
            "Want me to apply the fixes?",
            "Would you like me to proceed with applying these changes?",
            "Should I continue with the next batch?"
        ]
        for q in annoyingQuestions {
            text = text.replacingOccurrences(of: q, with: "")
        }
        text = text.replacingOccurrences(of: "Via muse.workflow (the use_workers equivalent in this runtime)", with: "Via parallel Assist workers")
        text = text.replacingOccurrences(of: "muse.workflow", with: "workers")
        text = text.replacingOccurrences(of: "use_workers", with: "parallel workers")
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
