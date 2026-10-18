import Foundation

public struct AssistDocsGenerateTool: AssistTool {
    public let id = "docs_generate"
    public let name = "Generate Docs"
    public let description = "Generates a markdown API document from public Swift declarations in the workspace. Refuses to overwrite unless overwrite is true."

    public init() {}

    public var capability: ToolCapability { .fileModification }
    public var riskLevel: ToolRiskLevel { .safeMutation }

    public var parametersSchema: JSONSchema {
        JSONSchema(
            type: "object",
            description: "Generates markdown docs from public Swift declarations.",
            properties: [
                "outputPath": JSONSchema(type: "string", description: "Workspace-relative output path. Default is DOCS_GENERATED.md."),
                "title": JSONSchema(type: "string", description: "Document title (optional)."),
                "overwrite": JSONSchema(type: "string", description: "Set to true to overwrite an existing output file. Default is false.")
            ],
            required: []
        )
    }

    public func execute(input: [String: Any], context: AssistContext) async throws -> AssistToolResult {
        let rawOutput = (input["outputPath"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let outputRelative = (rawOutput?.isEmpty == false) ? rawOutput! : "DOCS_GENERATED.md"
        guard let outputURL = resolveInsideWorkspace(outputRelative, workspaceRoot: context.workspaceRoot) else {
            return .failure("Invalid outputPath: '\(outputRelative)' must be a workspace-relative path without '..' and must stay inside the workspace.")
        }
        let overwrite = ((input["overwrite"] as? String) ?? "").lowercased() == "true"
        if FileManager.default.fileExists(atPath: outputURL.path) && !overwrite {
            return .failure("Refusing to overwrite existing file at '\(outputRelative)'. Pass overwrite=true to replace it.")
        }
        let title = (input["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let effectiveTitle = (title?.isEmpty == false) ? title! : "Generated API Documentation"

        let swiftFiles = listSwiftFiles(under: context.workspaceRoot)
        var sections: [String] = []
        var totalDeclarations = 0
        for fileURL in swiftFiles {
            guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else { continue }
            let relative = relativePath(for: fileURL, workspaceRoot: context.workspaceRoot)
            let header = fileHeader(from: content)
            let declarations = publicDeclarations(from: content)
            totalDeclarations += declarations.count
            var section = "## \(relative)\n\n"
            if !header.isEmpty {
                section += header + "\n\n"
            }
            if declarations.isEmpty {
                section += "_No public declarations found._\n"
            } else {
                for declaration in declarations {
                    section += "- `\(declaration)`\n"
                }
            }
            sections.append(section)
        }

        let formatter = ISO8601DateFormatter()
        var markdown = "# \(effectiveTitle)\n\n"
        markdown += "- Generated: \(formatter.string(from: Date()))\n"
        markdown += "- Workspace: \(context.workspaceRoot.path)\n"
        markdown += "- Swift files: \(swiftFiles.count)\n"
        markdown += "- Public declarations: \(totalDeclarations)\n\n"
        if sections.isEmpty {
            markdown += "_No Swift files found in the workspace._\n"
        } else {
            markdown += sections.joined(separator: "\n")
        }
        do {
            try markdown.data(using: .utf8)?.write(to: outputURL, options: [.atomic])
        } catch {
            return .failure("Failed to write docs to '\(outputRelative)': \(error.localizedDescription)")
        }
        return .success("Generated docs for \(swiftFiles.count) Swift file(s), \(totalDeclarations) public declaration(s), at \(outputRelative)", data: [
            "output_path": outputURL.path,
            "output_relative": outputRelative,
            "file_count": "\(swiftFiles.count)",
            "declaration_count": "\(totalDeclarations)"
        ])
    }

    private func listSwiftFiles(under root: URL) -> [URL] {
        var found: [URL] = []
        let skipped = Set([".git", "DerivedData", ".build", "Pods", "node_modules", ".swiftpm", "Carthage", "vendor"])
        guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) else {
            return found
        }
        for case let url as URL in enumerator {
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue {
                if skipped.contains(url.lastPathComponent) {
                    enumerator.skipDescendants()
                }
                continue
            }
            if url.pathExtension == "swift" {
                found.append(url)
            }
        }
        return found.sorted(by: { $0.path < $1.path })
    }

    private func fileHeader(from content: String) -> String {
        let lines = content.components(separatedBy: .newlines)
        var headerLines: [String] = []
        for line in lines.prefix(5) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("//") {
                headerLines.append(trimmed)
            } else if trimmed.isEmpty {
                continue
            } else {
                break
            }
        }
        return headerLines.joined(separator: "\n")
    }

    private func publicDeclarations(from content: String) -> [String] {
        let markers = ["struct ", "class ", "enum ", "protocol ", "actor ", "func ", "var ", "let ", "extension "]
        var results: [String] = []
        for rawLine in content.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard line.hasPrefix("public ") else { continue }
            guard markers.contains(where: { line.contains($0) }) else { continue }
            var cleaned = line
            if let brace = cleaned.firstIndex(of: "{") {
                cleaned = String(cleaned[..<brace]).trimmingCharacters(in: .whitespaces)
            }
            if cleaned.count > 200 {
                cleaned = String(cleaned.prefix(200))
            }
            if !cleaned.isEmpty {
                results.append(cleaned)
            }
        }
        return results
    }

    private func resolveInsideWorkspace(_ raw: String, workspaceRoot: URL) -> URL? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let components = trimmed.split(separator: "/").map(String.init)
        if components.contains("..") { return nil }
        if trimmed.hasPrefix("/") {
            guard trimmed == workspaceRoot.path || trimmed.hasPrefix(workspaceRoot.path + "/") else { return nil }
            return URL(fileURLWithPath: trimmed)
        }
        return workspaceRoot.appendingPathComponent(trimmed)
    }

    private func relativePath(for url: URL, workspaceRoot: URL) -> String {
        let root = workspaceRoot.path
        if url.path == root { return "." }
        if url.path.hasPrefix(root + "/") {
            return String(url.path.dropFirst(root.count + 1))
        }
        return url.lastPathComponent
    }
}
