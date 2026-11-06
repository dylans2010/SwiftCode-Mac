import Foundation

public struct AssistProjectTargetListTool: AssistTool {
    public let id = "project_target_list"
    public let name = "List Targets"
    public let description = "Lists the Xcode targets in the user's project by scanning project.pbxproj and xcodebuild output."

    public init() {}

    public var capability: ToolCapability { .compilation }
    public var riskLevel: ToolRiskLevel { .safeRead }

    public var parametersSchema: JSONSchema {
        JSONSchema(
            type: "object",
            description: "Lists the Xcode targets in the user's project.",
            properties: [:],
            required: []
        )
    }

    public func execute(input: [String: Any], context: AssistContext) async throws -> AssistToolResult {
        var targets = Set<String>()
        var sources: [String] = []

        let pbxprojURLs = findPBXProjURLs(in: context.workspaceRoot)
        for pbxURL in pbxprojURLs {
            guard let content = try? String(contentsOf: pbxURL, encoding: .utf8) else { continue }
            let scanned = scanTargets(in: content)
            if !scanned.isEmpty {
                targets.formUnion(scanned)
                sources.append(pbxURL.lastPathComponent)
            }
        }

        #if os(macOS)
        if let project = locateProject(in: context.workspaceRoot) {
            var args: [String] = project.isWorkspace
                ? ["-workspace", project.url.path]
                : ["-project", project.url.path]
            args += ["-list", "-json"]
            if let result = try? runProcess(executable: "/usr/bin/xcodebuild", args: args, cwd: context.workspaceRoot.path),
               result.status == 0,
               let data = result.output.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                if let projectDict = json["project"] as? [String: Any],
                   let list = projectDict["targets"] as? [String] {
                    targets.formUnion(list)
                }
                if let workspaceDict = json["workspace"] as? [String: Any],
                   let list = workspaceDict["targets"] as? [String] {
                    targets.formUnion(list)
                }
                if !targets.isEmpty && !sources.contains("xcodebuild") {
                    sources.append("xcodebuild")
                }
            }
        }
        #endif

        let sorted = targets.sorted()
        if sorted.isEmpty {
            return .failure("No Xcode targets found. No .xcodeproj with a project.pbxproj was located in the workspace.")
        }
        return .success(
            "Found \(sorted.count) target(s): \(sorted.joined(separator: ", "))",
            data: ["targets": sorted.joined(separator: ","), "count": "\(sorted.count)", "sources": sources.joined(separator: ",")]
        )
    }

    private func findPBXProjURLs(in workspaceRoot: URL) -> [URL] {
        var results: [URL] = []
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: workspaceRoot,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return results }
        var depthByURL: [URL: Int] = [workspaceRoot: 0]
        for case let url as URL in enumerator {
            let parent = url.deletingLastPathComponent()
            let depth = (depthByURL[parent] ?? 0) + 1
            depthByURL[url] = depth
            if depth > 4 { enumerator.skipDescendants(); continue }
            if url.lastPathComponent == "project.pbxproj" {
                results.append(url)
            }
        }
        return results.sorted { $0.path < $1.path }
    }

    private func scanTargets(in content: String) -> [String] {
        var names: [String] = []
        let lines = content.components(separatedBy: "\n")
        for (index, line) in lines.enumerated() {
            guard line.contains("isa = PBXNativeTarget") else { continue }
            // Preferred: the /* Name */ comment on the same line.
            if let commentName = commentName(in: line), !commentName.isEmpty {
                names.append(commentName)
                continue
            }
            // Fallback: look ahead for a `name = ...;` line within this block.
            var found: String?
            var cursor = index + 1
            while cursor < lines.count && cursor < index + 12 {
                let candidate = lines[cursor]
                if candidate.contains("};") && !candidate.contains("name =") { break }
                if let value = valueAfterEquals(in: candidate, key: "name") {
                    found = value
                    break
                }
                cursor += 1
            }
            if let found, !found.isEmpty {
                names.append(found)
            }
        }
        return names
    }

    private func commentName(in line: String) -> String? {
        guard let start = line.range(of: "/* "),
              let end = line.range(of: " */", range: start.upperBound..<line.endIndex) else {
            return nil
        }
        let name = String(line[start.upperBound..<end.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? nil : name
    }

    private func valueAfterEquals(in line: String, key: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("\(key) = ") || trimmed.hasPrefix("\(key) =") else { return nil }
        guard let equals = trimmed.firstIndex(of: "=") else { return nil }
        var value = String(trimmed[trimmed.index(after: equals)...]).trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasSuffix(";") { value = String(value.dropLast()) }
        value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("\"") && value.hasSuffix("\"") && value.count >= 2 {
            value = String(value.dropFirst().dropLast())
        }
        return value.isEmpty ? nil : value
    }

    private struct LocatedBundle {
        let url: URL
        let isWorkspace: Bool
    }

    private func locateProject(in workspaceRoot: URL) -> LocatedBundle? {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(
            at: workspaceRoot,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return nil }
        let workspaces = entries.filter { $0.pathExtension == "xcworkspace" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
        if let ws = workspaces.first {
            return LocatedBundle(url: ws, isWorkspace: true)
        }
        let projects = entries.filter { $0.pathExtension == "xcodeproj" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
        if let proj = projects.first {
            return LocatedBundle(url: proj, isWorkspace: false)
        }
        return nil
    }

    #if os(macOS)
    private func runProcess(executable: String, args: [String], cwd: String) throws -> (status: Int32, output: String) {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = args
        process.currentDirectoryURL = URL(fileURLWithPath: cwd)
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let output = String(data: data, encoding: .utf8) ?? ""
        return (process.terminationStatus, output)
    }
    #endif
}
