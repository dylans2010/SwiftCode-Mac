import Foundation

public struct AssistLicenseHeaderCheckTool: AssistTool {
    public let id = "license_header_check"
    public let name = "License Header Check"
    public let description = "Checks the first 15 lines of each Swift file for required header text (default: \"Copyright\") and reports files missing it."

    public init() {}

    public var capability: ToolCapability { .diagnostics }
    public var riskLevel: ToolRiskLevel { .safeRead }

    public var parametersSchema: JSONSchema {
        JSONSchema(
            type: "object",
            description: "Checks Swift file headers for required text.",
            properties: [
                "path": JSONSchema(type: "string", description: "Workspace-relative path of a file or directory to check. Defaults to the workspace root."),
                "requiredText": JSONSchema(type: "string", description: "Header text that must appear in the first 15 lines. Case-insensitive. Default: \"Copyright\".")
            ],
            required: []
        )
    }

    public func execute(input: [String: Any], context: AssistContext) async throws -> AssistToolResult {
        guard let root = resolvePath(input["path"] as? String, in: context) else {
            return .failure("Invalid path: path must stay inside the workspace and must not contain '..'.")
        }
        let rawRequired = (input["requiredText"] ?? input["required_text"]) as? String
        let requiredText = (rawRequired?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { $0.isEmpty ? nil : $0 } ?? "Copyright"

        let files = enumerateSwiftFiles(at: root)
        if files.isEmpty {
            return .success(
                "License Header Check: no Swift files found.",
                data: ["scannedFiles": "0", "withHeader": "0", "missingHeader": "0", "missingFiles": ""]
            )
        }

        var missing: [String] = []
        var withHeader = 0
        for url in files {
            guard let text = readFile(url) else { continue }
            let relative = relativePath(url, root: context.workspaceRoot)
            let header = text.components(separatedBy: "\n").prefix(15).joined(separator: "\n")
            if header.lowercased().contains(requiredText.lowercased()) {
                withHeader += 1
            } else {
                missing.append(relative)
            }
        }

        var output = "License Header Check: scanned \(files.count) Swift file(s) for header text \"\(requiredText)\" in the first 15 lines — \(withHeader) with header, \(missing.count) missing.\n"
        if missing.isEmpty {
            output += "All scanned files contain the required header text."
        } else {
            output += "Files missing the header text:\n"
            output += missing.map { "- \($0)" }.joined(separator: "\n")
        }
        return .success(
            output,
            data: [
                "scannedFiles": "\(files.count)",
                "withHeader": "\(withHeader)",
                "missingHeader": "\(missing.count)",
                "missingFiles": missing.joined(separator: "\n")
            ]
        )
    }

    private func resolvePath(_ raw: String?, in context: AssistContext) -> URL? {
        let workspace = context.workspaceRoot.standardized
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return workspace }
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
