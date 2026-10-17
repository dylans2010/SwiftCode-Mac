import Foundation

public struct AssistSecurityAuditTool: AssistTool {
    public let id = "security_audit_scanner"
    public let name = "Security Audit Scanner"
    public let description = "Scans Swift source files for hardcoded secrets, API keys, insecure HTTP endpoints, and unsafe storage practices."

    public init() {}

    public var capability: ToolCapability { .diagnostics }
    public var riskLevel: ToolRiskLevel { .safeRead }

    public var parametersSchema: JSONSchema {
        JSONSchema(
            type: "object",
            description: "Perform static security audit over workspace files.",
            properties: [
                "path": JSONSchema(type: "string", description: "Workspace-relative path to a directory or Swift file.")
            ],
            required: ["path"]
        )
    }

    public func execute(input: [String: Any], context: AssistContext) async throws -> AssistToolResult {
        guard let path = input["path"] as? String else {
            return .failure("Missing required parameter: path")
        }

        let targetURL = context.workspaceRoot.appendingPathComponent(path)
        let fileManager = FileManager.default

        var isDir: ObjCBool = false
        guard fileManager.fileExists(atPath: targetURL.path, isDirectory: &isDir) else {
            return .failure("Path does not exist: \(path)")
        }

        var files: [URL] = []
        if isDir.boolValue {
            if let enumerator = fileManager.enumerator(at: targetURL, includingPropertiesForKeys: nil) {
                while let fileURL = enumerator.nextObject() as? URL {
                    if fileURL.pathExtension == "swift" || fileURL.pathExtension == "plist" {
                        files.append(fileURL)
                    }
                }
            }
        } else {
            files.append(targetURL)
        }

        var findings: [String] = []

        for fileURL in files {
            guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else { continue }
            let relPath = fileURL.path.replacingOccurrences(of: context.workspaceRoot.path + "/", with: "")
            let lines = content.components(separatedBy: .newlines)

            for (idx, line) in lines.enumerated() {
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.hasPrefix("//") { continue }

                // 1. Plain HTTP URLs (ATS violation)
                if trimmed.contains("\"http://") && !trimmed.contains("localhost") && !trimmed.contains("127.0.0.1") {
                    findings.append("\(relPath):\(idx + 1) [ATS] Insecure plaintext HTTP URL detected: '\(trimmed)'. Upgrade to HTTPS.")
                }

                // 2. Hardcoded secret / token patterns
                let lower = trimmed.lowercased()
                if (lower.contains("api_key = \"") || lower.contains("apikey = \"") || lower.contains("secret = \"") || lower.contains("password = \"")) && !trimmed.contains("\"\"") {
                    findings.append("\(relPath):\(idx + 1) [Credential] Potential hardcoded credential or secret assignment. Use Keychain or Environment variables.")
                }

                // 3. Sensitive logging
                if trimmed.contains("print(\"token") || trimmed.contains("print(\"password") || trimmed.contains("print(\"apiKey") {
                    findings.append("\(relPath):\(idx + 1) [Privacy] Sensitive credential leaked into debug console print statement.")
                }
            }
        }

        if findings.isEmpty {
            return .success("Security Audit passed: 0 vulnerabilities or hardcoded secrets found across \(files.count) files in '\(path)'.")
        } else {
            return .success("Security Audit flagged \(findings.count) items in '\(path)':\n\n" + findings.prefix(20).joined(separator: "\n") + (findings.count > 20 ? "\n...and \(findings.count - 20) more." : ""))
        }
    }
}
