import Foundation

public struct AssistFileHashVerifyTool: AssistTool {
    public let id = "file_hash_verify"
    public let name = "Verify File Hash"
    public let description = "Computes a file hash with shasum or md5 and compares it to an expected hash. A mismatch is reported as a successful comparison with match false, not as a tool error."

    public init() {}

    public var capability: ToolCapability { .fileReading }
    public var riskLevel: ToolRiskLevel { .safeRead }

    public var parametersSchema: JSONSchema {
        JSONSchema(
            type: "object",
            description: "Computes a file hash and compares it to an expected hash.",
            properties: [
                "path": JSONSchema(type: "string", description: "Workspace-relative path of the file to hash."),
                "expectedHash": JSONSchema(type: "string", description: "Expected hash in hexadecimal."),
                "algorithm": JSONSchema(type: "string", description: "Hash algorithm: sha256, sha1, or md5. Default: sha256.")
            ],
            required: ["path", "expectedHash"]
        )
    }

    public func execute(input: [String: Any], context: AssistContext) async throws -> AssistToolResult {
        guard let rawPath = (input["path"] as? String), !rawPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .failure("Missing required parameter: path")
        }
        guard let expectedRaw = (input["expectedHash"] as? String), !expectedRaw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .failure("Missing required parameter: expectedHash")
        }
        guard let url = resolveWorkspacePath(rawPath, workspaceRoot: context.workspaceRoot) else {
            return .failure("Refusing to access path outside the workspace: \(rawPath)")
        }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), !isDirectory.boolValue else {
            return .failure("Hash verification requires an existing file: \(rawPath)")
        }

        let algorithm = ((input["algorithm"] as? String) ?? "sha256").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let expectedLength: Int
        switch algorithm {
        case "sha256": expectedLength = 64
        case "sha1": expectedLength = 40
        case "md5": expectedLength = 32
        default:
            return .failure("Invalid algorithm '\(algorithm)'. Allowed: sha256, sha1, md5.")
        }
        let expected = expectedRaw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard expected.count == expectedLength, expected.allSatisfy({ $0.isHexDigit }) else {
            return .failure("Invalid expectedHash for \(algorithm). Expected \(expectedLength) hexadecimal characters.")
        }

        let computed: String
        switch algorithm {
        case "sha256":
            guard let hash = runHash(executable: "/usr/bin/shasum", args: ["-a", "256", url.path]) else {
                return .failure("Failed to compute sha256 for \(rawPath).")
            }
            computed = hash
        case "sha1":
            guard let hash = runHash(executable: "/usr/bin/shasum", args: ["-a", "1", url.path]) else {
                return .failure("Failed to compute sha1 for \(rawPath).")
            }
            computed = hash
        case "md5":
            guard let hash = runHash(executable: "/usr/bin/md5", args: ["-q", url.path]) else {
                return .failure("Failed to compute md5 for \(rawPath).")
            }
            computed = hash
        default:
            return .failure("Invalid algorithm '\(algorithm)'.")
        }

        let match = computed.lowercased() == expected
        let relative = relativePath(url, workspaceRoot: context.workspaceRoot)
        let output = match
            ? "Hash match: true. \(algorithm) of \(relative) matches the expected hash."
            : "Hash match: false. \(algorithm) of \(relative) is \(computed), expected \(expected)."
        return .success(output, data: [
            "path": relative,
            "algorithm": algorithm,
            "computedHash": computed,
            "expectedHash": expected,
            "match": match ? "true" : "false"
        ])
    }

    private func runHash(executable: String, args: [String]) -> String? {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = args
        process.standardOutput = pipe
        process.standardError = pipe
        do {
            try process.run()
        } catch {
            return nil
        }
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""
        let token = output.split(separator: " ", omittingEmptySubsequences: true).first.map(String.init) ?? ""
        let cleaned = token.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !cleaned.isEmpty, cleaned.allSatisfy({ $0.isHexDigit }) else { return nil }
        return cleaned
    }

    private func resolveWorkspacePath(_ raw: String, workspaceRoot: URL) -> URL? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains("\0"), !trimmed.hasPrefix("~"), !trimmed.contains("..") else {
            return nil
        }
        let rootPath = workspaceRoot.standardized.path
        let candidate: URL
        if trimmed.hasPrefix("/") {
            candidate = URL(fileURLWithPath: trimmed).standardized
        } else {
            candidate = workspaceRoot.appendingPathComponent(trimmed).standardized
        }
        let candidatePath = candidate.path
        guard candidatePath == rootPath || candidatePath.hasPrefix(rootPath + "/") else {
            return nil
        }
        return candidate
    }

    private func relativePath(_ url: URL, workspaceRoot: URL) -> String {
        let rootPath = workspaceRoot.standardized.path
        let path = url.standardized.path
        if path == rootPath { return "." }
        if path.hasPrefix(rootPath + "/") {
            return String(path.dropFirst(rootPath.count + 1))
        }
        return path
    }
}
