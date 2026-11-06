import Foundation

public struct AssistProjectBuildSettingsTool: AssistTool {
    public let id = "project_build_settings"
    public let name = "Build Settings"
    public let description = "Reads Xcode build settings with xcodebuild, or sets one build setting key in the project's pbxproj."

    public init() {}

    public var capability: ToolCapability { .compilation }
    public var riskLevel: ToolRiskLevel { .safeMutation }

    public var parametersSchema: JSONSchema {
        JSONSchema(
            type: "object",
            description: "Reads build settings (action=read) or sets one key (action=set) in project.pbxproj.",
            properties: [
                "action": JSONSchema(type: "string", description: "read or set. Default: read."),
                "target": JSONSchema(type: "string", description: "Optional target name for read or set."),
                "configuration": JSONSchema(type: "string", description: "Build configuration, e.g. Debug or Release. Default: Debug."),
                "key": JSONSchema(type: "string", description: "Build setting key. Required for set; optional filter for read."),
                "value": JSONSchema(type: "string", description: "New value for the key. Required for set.")
            ],
            required: []
        )
    }

    public func execute(input: [String: Any], context: AssistContext) async throws -> AssistToolResult {
        let action = (input["action"] as? String ?? "read").lowercased()
        let configuration = (input["configuration"] as? String ?? "Debug").trimmingCharacters(in: .whitespacesAndNewlines)
        let target = (input["target"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let key = (input["key"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let value = (input["value"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)

        guard action == "read" || action == "set" else {
            return .failure("Invalid action '\(action)'. Expected read or set.")
        }
        guard !configuration.isEmpty else {
            return .failure("Missing required parameter: configuration")
        }
        if action == "set" {
            guard let key, !key.isEmpty else { return .failure("Missing required parameter: key for action=set") }
            guard let value, !value.isEmpty else { return .failure("Missing required parameter: value for action=set") }
            guard isValidSettingKey(key) else { return .failure("Invalid build setting key '\(key)'.") }
            return setSetting(key: key, value: value, target: target, configuration: configuration, workspaceRoot: context.workspaceRoot)
        }

        #if os(macOS)
        guard let project = locateProject(in: context.workspaceRoot) else {
            return .failure("No .xcodeproj or .xcworkspace found at the top level of the workspace.")
        }
        var args: [String] = project.isWorkspace
            ? ["-workspace", project.url.path]
            : ["-project", project.url.path]
        if let target, !target.isEmpty {
            args += ["-target", target]
        }
        args += ["-configuration", configuration, "-showBuildSettings"]
        let result: (status: Int32, output: String)
        do {
            result = try runProcess(executable: "/usr/bin/xcodebuild", args: args, cwd: context.workspaceRoot.path)
        } catch {
            return .failure("Failed to run xcodebuild -showBuildSettings: \(error.localizedDescription)")
        }
        guard result.status == 0 else {
            return .failure("xcodebuild -showBuildSettings failed: \(result.output)")
        }
        var settings: [String: String] = [:]
        for line in result.output.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("Build settings"), !trimmed.hasPrefix("Command line") else { continue }
            guard let equals = trimmed.firstIndex(of: "=") else { continue }
            let name = trimmed[..<equals].trimmingCharacters(in: .whitespaces)
            let val = trimmed[trimmed.index(after: equals)...].trimmingCharacters(in: .whitespaces)
            if !name.isEmpty {
                settings[String(name)] = String(val)
            }
        }
        if let key, !key.isEmpty {
            guard let found = settings[key] else {
                return .failure("Build setting '\(key)' not found for configuration '\(configuration)'.")
            }
            return .success("Build setting \(key) = \(found)", data: ["key": key, "value": found, "configuration": configuration])
        }
        let preview = settings.sorted { $0.key < $1.key }.prefix(50).map { "\($0.key) = \($0.value)" }.joined(separator: "\n")
        return .success(
            "Found \(settings.count) build setting(s) for configuration '\(configuration)'.",
            data: ["count": "\(settings.count)", "configuration": configuration, "settings": preview]
        )
        #else
        return .failure("Reading build settings requires macOS with xcodebuild.")
        #endif
    }

    private func isValidSettingKey(_ key: String) -> Bool {
        guard !key.isEmpty else { return false }
        if key.contains("..") || key.contains("\n") || key.contains("\r") || key.contains(";") || key.contains("{") || key.contains("}") {
            return false
        }
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_")
        return key.unicodeScalars.allSatisfy { allowed.contains($0) }
    }

    private func setSetting(key: String, value: String, target: String?, configuration: String, workspaceRoot: URL) -> AssistToolResult {
        guard let pbxURL = findPBXProjURL(in: workspaceRoot) else {
            return .failure("No project.pbxproj found in the workspace.")
        }
        guard let content = try? String(contentsOf: pbxURL, encoding: .utf8) else {
            return .failure("Failed to read project.pbxproj.")
        }
        if let target, !target.isEmpty, !content.contains(target) {
            return .failure("Target '\(target)' not found in project.pbxproj.")
        }
        var lines = content.components(separatedBy: "\n")
        var updated = false
        var index = 0
        while index < lines.count {
            guard lines[index].contains("isa = XCBuildConfiguration") else { index += 1; continue }
            // Collect this XCBuildConfiguration block.
            var end = index
            var blockHasConfiguration = false
            while end < lines.count {
                if lines[end].contains("name = \(configuration);") { blockHasConfiguration = true }
                if lines[end].trimmingCharacters(in: .whitespaces) == "};" || lines[end].trimmingCharacters(in: .whitespaces) == "}" {
                    break
                }
                end += 1
            }
            guard blockHasConfiguration else { index = end + 1; continue }
            // Find buildSettings = { inside this block.
            var settingsOpen: Int?
            for cursor in index...end where lines[cursor].contains("buildSettings = {") {
                settingsOpen = cursor
                break
            }
            guard let open = settingsOpen else { index = end + 1; continue }
            // Replace existing key or insert after the opening line.
            var replaced = false
            var cursor = open + 1
            while cursor <= end {
                let trimmed = lines[cursor].trimmingCharacters(in: .whitespaces)
                if trimmed == "};" || trimmed == "}" { break }
                if trimmed.hasPrefix("\(key) = ") || trimmed.hasPrefix("\(key) =") {
                    let indent = String(lines[cursor].prefix(while: { $0 == " " || $0 == "\t" }))
                    lines[cursor] = "\(indent)\(key) = \(value);"
                    replaced = true
                    break
                }
                cursor += 1
            }
            if !replaced {
                let indent = String(lines[open].prefix(while: { $0 == " " || $0 == "\t" })) + "\t\t"
                lines.insert("\(indent)\(key) = \(value);", at: open + 1)
            }
            updated = true
            break
        }
        guard updated else {
            return .failure("No XCBuildConfiguration block for configuration '\(configuration)' found in project.pbxproj.")
        }
        let updatedContent = lines.joined(separator: "\n")
        do {
            try updatedContent.write(to: pbxURL, atomically: true, encoding: .utf8)
        } catch {
            return .failure("Failed to write project.pbxproj: \(error.localizedDescription)")
        }
        guard let verify = try? String(contentsOf: pbxURL, encoding: .utf8),
              verify.contains("\(key) = \(value);") else {
            return .failure("Verification failed: '\(key) = \(value);' not found after writing project.pbxproj.")
        }
        return .success(
            "Set build setting \(key) = \(value) for configuration '\(configuration)'.",
            data: ["key": key, "value": value, "configuration": configuration, "file": "project.pbxproj"],
            filesChanged: ["project.pbxproj"]
        )
    }

    private func findPBXProjURL(in workspaceRoot: URL) -> URL? {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(at: workspaceRoot, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else { return nil }
        for case let url as URL in enumerator {
            if url.lastPathComponent == "project.pbxproj" { return url }
        }
        return nil
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
        if let ws = workspaces.first { return LocatedBundle(url: ws, isWorkspace: true) }
        let projects = entries.filter { $0.pathExtension == "xcodeproj" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
        if let proj = projects.first { return LocatedBundle(url: proj, isWorkspace: false) }
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
