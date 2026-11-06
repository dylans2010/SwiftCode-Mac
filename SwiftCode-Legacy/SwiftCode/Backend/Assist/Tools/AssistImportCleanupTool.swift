import Foundation

public struct AssistImportCleanupTool: AssistTool {
    public let id = "import_cleanup"
    public let name = "Import Cleanup"
    public let description = "Removes unused import lines from Swift files. An import is removed only when its module name never appears as a whole word anywhere else in the file. Well-known Apple SDK and test modules (Foundation, SwiftUI, XCTest, Testing, and others) are never removed, because their symbols do not mention the module name. Only files that change are rewritten. Heuristic: it does not resolve re-exports or typealiases across modules."

    public init() {}

    public var capability: ToolCapability { .fileModification }
    public var riskLevel: ToolRiskLevel { .safeMutation }

    public var parametersSchema: JSONSchema {
        JSONSchema(
            type: "object",
            description: "Removes unused imports from a Swift file or directory.",
            properties: [
                "path": JSONSchema(type: "string", description: "Workspace-relative path of a Swift file or directory to clean. Required.")
            ],
            required: ["path"]
        )
    }

    public func execute(input: [String: Any], context: AssistContext) async throws -> AssistToolResult {
        guard let rawPath = (input["path"] ?? input["filePath"] ?? input["file_path"]) as? String, !rawPath.isEmpty else {
            return .failure("Missing required parameter: path")
        }
        guard let root = resolvePath(rawPath, in: context) else {
            return .failure("Invalid path: path must stay inside the workspace and must not contain '..'.")
        }
        let files = enumerateSwiftFiles(at: root)
        if files.isEmpty {
            return .success(
                "Import Cleanup: no Swift files found.",
                data: ["filesChanged": "", "removedImports": "0", "changedFileCount": "0"]
            )
        }

        guard let importRegex = try? NSRegularExpression(pattern: "^\\s*(?:@testable\\s+)?import\\s+([A-Za-z_][A-Za-z0-9_]*)\\b", options: []) else {
            return .failure("Import Cleanup: failed to build import pattern.")
        }
        let protectedModules: Set<String> = [
            "Foundation", "Swift", "SwiftUI", "UIKit", "AppKit", "Combine", "CoreData", "SwiftData",
            "CoreGraphics", "CoreAnimation", "QuartzCore", "WebKit", "MapKit", "AVFoundation", "Photos",
            "UserNotifications", "StoreKit", "Testing", "XCTest", "Observation", "OSLog",
            "UniformTypeIdentifiers", "CryptoKit", "Security", "Network", "WidgetKit", "AppIntents",
            "TipKit", "CoreLocation", "CoreMotion", "HealthKit", "EventKit", "Contacts",
            "SafariServices", "AuthenticationServices", "LocalAuthentication", "Speech", "Vision",
            "NaturalLanguage", "PlaygroundSupport"
        ]

        var changed: [String] = []
        var removed: [String] = []
        for url in files {
            guard let content = readFile(url) else { continue }
            let relative = relativePath(url, root: context.workspaceRoot)
            let lines = content.components(separatedBy: "\n")
            var importLineIndexes: [Int] = []
            var importModules: [Int: String] = [:]
            for (index, line) in lines.enumerated() {
                let range = NSRange(line.startIndex..., in: line)
                if let match = importRegex.firstMatch(in: line, options: [], range: range),
                   match.numberOfRanges >= 2, let moduleRange = Range(match.range(at: 1), in: line) {
                    importLineIndexes.append(index)
                    importModules[index] = String(line[moduleRange])
                }
            }
            if importLineIndexes.isEmpty { continue }
            let bodyText = lines.enumerated().filter { !importLineIndexes.contains($0.offset) }.map { $0.element }.joined(separator: "\n")
            var removeIndexes: Set<Int> = []
            for index in importLineIndexes {
                guard let module = importModules[index] else { continue }
                if protectedModules.contains(module) { continue }
                let usagePattern = "\\b" + NSRegularExpression.escapedPattern(for: module) + "\\b"
                guard let usageRegex = try? NSRegularExpression(pattern: usagePattern, options: []) else { continue }
                let bodyRange = NSRange(bodyText.startIndex..., in: bodyText)
                if usageRegex.firstMatch(in: bodyText, options: [], range: bodyRange) == nil {
                    removeIndexes.insert(index)
                    removed.append("\(relative): import \(module)")
                }
            }
            if removeIndexes.isEmpty { continue }
            let updated = lines.enumerated().filter { !removeIndexes.contains($0.offset) }.map { $0.element }.joined(separator: "\n")
            do {
                try updated.write(to: url, atomically: true, encoding: .utf8)
            } catch {
                return .failure("Import Cleanup failed while writing \(relative): \(error.localizedDescription)")
            }
            changed.append(relative)
        }

        if changed.isEmpty {
            return .success(
                "Import Cleanup: no unused imports found in \(files.count) Swift file(s). Nothing changed.",
                data: ["filesChanged": "", "removedImports": "0", "changedFileCount": "0"]
            )
        }
        return .success(
            "Import Cleanup: removed \(removed.count) unused import(s) across \(changed.count) file(s):\n" + removed.map { "- \($0)" }.joined(separator: "\n"),
            data: [
                "filesChanged": changed.joined(separator: "\n"),
                "removedImports": "\(removed.count)",
                "changedFileCount": "\(changed.count)",
                "removed": removed.joined(separator: "\n")
            ],
            filesChanged: changed
        )
    }

    private func resolvePath(_ raw: String?, in context: AssistContext) -> URL? {
        let workspace = context.workspaceRoot.standardized
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return nil }
        if raw.contains("..") { return nil }
        let candidate: URL
        if raw.hasPrefix("/") {
            candidate = URL(fileURLWithPath: raw).standardized
        } else {
            candidate = workspace.appendingPathComponent(raw).standardized
        }
        if candidate == workspace || candidate.path.hasPrefix(workspace.path + "/") {
            return candidate
        }
        return nil
    }

    private func enumerateSwiftFiles(at root: URL) -> [URL] {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: root.path, isDirectory: &isDir) else { return [] }
        if !isDir.boolValue {
            if root.pathExtension.lowercased() == "swift" && fileSize(root) <= 300_000 {
                return [root]
            }
            return []
        }
        var results: [URL] = []
        guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey], options: []) else { return results }
        while let url = enumerator.nextObject() as? URL {
            let name = url.lastPathComponent
            var isDirectory: ObjCBool = false
            _ = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
            if isDirectory.boolValue {
                if name == ".git" || name == "DerivedData" || name == ".build" || name == "Pods" || name == "node_modules" {
                    enumerator.skipDescendants()
                }
                continue
            }
            if url.pathExtension.lowercased() != "swift" { continue }
            if fileSize(url) > 300_000 { continue }
            results.append(url)
            if results.count >= 5000 { break }
        }
        return results.sorted { $0.path < $1.path }
    }

    private func fileSize(_ url: URL) -> Int {
        if let values = try? url.resourceValues(forKeys: [.fileSizeKey]), let size = values.fileSize {
            return size
        }
        return 0
    }

    private func readFile(_ url: URL) -> String? {
        try? String(contentsOf: url, encoding: .utf8)
    }

    private func relativePath(_ url: URL, root: URL) -> String {
        let rootPath = root.standardized.path
        let path = url.standardized.path
        if path.hasPrefix(rootPath + "/") {
            return String(path.dropFirst(rootPath.count + 1))
        }
        return url.lastPathComponent
    }
}
