//
//  AssistFileChecksumVerifierTool.swift
//  SwiftCode
//

import Foundation
import CryptoKit

public struct AssistFileChecksumVerifierTool: AssistTool {
    public let id = "file_checksum_verifier"
    public let name = "File Checksum Verifier"
    public let description = "Computes and verifies SHA-256, SHA-1, or MD5 cryptographic hashes for workspace files."

    public init() {}

    public var capability: ToolCapability { .diagnostics }
    public var riskLevel: ToolRiskLevel { .safeRead }

    public var parametersSchema: JSONSchema {
        JSONSchema(
            type: "object",
            description: "Calculates cryptographic digests (SHA-256, SHA-1, MD5) for file integrity validation.",
            properties: [
                "path": JSONSchema(type: "string", description: "Relative path to file in workspace."),
                "algorithm": JSONSchema(type: "string", description: "Hash algorithm: 'sha256', 'sha1', 'md5'. Defaults to 'sha256'.")
            ],
            required: ["path"]
        )
    }

    public func execute(input: [String: Any], context: AssistContext) async throws -> AssistToolResult {
        guard let path = input["path"] as? String else {
            return .failure("Missing required parameter: path")
        }
        let algorithm = (input["algorithm"] as? String)?.lowercased() ?? "sha256"

        let fileURL = path.hasPrefix("/") ? URL(fileURLWithPath: path) : context.workspaceRoot.appendingPathComponent(path)
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return .failure("File not found at: \(path)")
        }

        guard let data = try? Data(contentsOf: fileURL) else {
            return .failure("Unable to read data from file at: \(path)")
        }

        let hashString: String
        switch algorithm {
        case "sha1":
            let digest = Insecure.SHA1.hash(data: data)
            hashString = digest.map { String(format: "%02hhx", $0) }.joined()
        case "md5":
            let digest = Insecure.MD5.hash(data: data)
            hashString = digest.map { String(format: "%02hhx", $0) }.joined()
        default:
            let digest = SHA256.hash(data: data)
            hashString = digest.map { String(format: "%02hhx", $0) }.joined()
        }

        let fileSize = data.count
        return .success("Checksum for `\(path)`:\n- Algorithm: \(algorithm.uppercased())\n- Digest: `\(hashString)`\n- Byte Size: \(fileSize) bytes")
    }
}
