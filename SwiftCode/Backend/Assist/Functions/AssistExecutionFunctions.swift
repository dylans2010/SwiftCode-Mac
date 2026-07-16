import Foundation

public struct AssistExecutionFunctions {
    public typealias ExecutionTask = (AssistContext) async throws -> String

    private static var registry: [String: ExecutionTask] = [:]

    public static func register(id: String, task: @escaping ExecutionTask) {
        registry[id] = task
    }

    public static func executeTask(id: String, context: AssistContext) async throws -> String {
        guard let task = registry[id] else {
            throw NSError(domain: "AssistExecution", code: 404, userInfo: [NSLocalizedDescriptionKey: "Task '\(id)' not found in registry."])
        }
        return try await task(context)
    }

    public static func initializeRegistry() {
        register(id: "project_indexing") { context in
            let fileCount = try FileManager.default.subpathsOfDirectory(atPath: context.workspaceRoot.path).count
            return "Indexed project at \(context.workspaceRoot.lastPathComponent). Found \(fileCount) filesystem entries."
        }

        register(id: "dependency_analysis") { context in
            let hasPackageSwift = FileManager.default.fileExists(atPath: context.workspaceRoot.appendingPathComponent("Package.swift").path)
            let hasPodfile = FileManager.default.fileExists(atPath: context.workspaceRoot.appendingPathComponent("Podfile").path)
            let hasCartfile = FileManager.default.fileExists(atPath: context.workspaceRoot.appendingPathComponent("Cartfile").path)
            return "Dependency scan complete. SPM: \(hasPackageSwift), CocoaPods: \(hasPodfile), Carthage: \(hasCartfile)."
        }

        register(id: "lint_project") { context in
            let findings = collectSwiftFindings(root: context.workspaceRoot)
            if findings.isEmpty {
                return "Lint completed. 0 issues found across scanned Swift files."
            }
            let summary = findings.prefix(20).joined(separator: "\n")
            return "Lint completed. Found \(findings.count) issue(s).\n\(summary)"
        }

        register(id: "project_test") { context in
            let testFiles = discoverTestFiles(root: context.workspaceRoot)
            guard !testFiles.isEmpty else {
                return "No XCTest files discovered under workspace root."
            }
            return "Discovered \(testFiles.count) XCTest file(s). Sample: \(testFiles.prefix(5).joined(separator: ", "))"
        }
    }

    private static func collectSwiftFindings(root: URL) -> [String] {
        let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles])
        var findings: [String] = []

        while let fileURL = enumerator?.nextObject() as? URL {
            guard fileURL.pathExtension == "swift" else { continue }
            guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else { continue }
            let lines = content.components(separatedBy: .newlines)

            for (index, line) in lines.enumerated() {
                if line.contains("\t") {
                    findings.append("\(fileURL.lastPathComponent):\(index + 1) contains tab indentation")
                }
                if line.count > 140 {
                    findings.append("\(fileURL.lastPathComponent):\(index + 1) line exceeds 140 chars")
                }
                if line.hasSuffix(" ") {
                    findings.append("\(fileURL.lastPathComponent):\(index + 1) trailing whitespace")
                }
            }
        }

        return findings
    }

    private static func discoverTestFiles(root: URL) -> [String] {
        let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles])
        var testFiles: [String] = []

        while let fileURL = enumerator?.nextObject() as? URL {
            guard fileURL.pathExtension == "swift" else { continue }
            let lowercasedPath = fileURL.path.lowercased()
            if lowercasedPath.contains("test") {
                testFiles.append(fileURL.lastPathComponent)
            }
        }

        return testFiles.sorted()
    }
}
