//
//  AssistSigningCertificateInspectorTool.swift
//  SwiftCode
//

import Foundation

public struct AssistSigningCertificateInspectorTool: AssistTool {
    public let id = "signing_certificate_inspector"
    public let name = "Code Signing Certificate Inspector"
    public let description = "Inspects valid Apple Development and Distribution code signing certificates in the keychain."

    public init() {}

    public var capability: ToolCapability { .diagnostics }
    public var riskLevel: ToolRiskLevel { .safeRead }

    public var parametersSchema: JSONSchema {
        JSONSchema(
            type: "object",
            description: "Lists valid code signing identities from the macOS Keychain via security find-identity.",
            properties: [:],
            required: []
        )
    }

    public func execute(input: [String: Any], context: AssistContext) async throws -> AssistToolResult {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        proc.arguments = ["find-identity", "-p", "codesigning", "-v"]

        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = pipe

        do {
            try proc.run()
            proc.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)

            if output.isEmpty {
                return .success("No valid code-signing identities found in macOS Keychain.")
            }

            let lines = output.components(separatedBy: .newlines)
            var report = "### Available Code Signing Certificates:\n\n"
            for l in lines {
                report += "- `\(l.trimmingCharacters(in: .whitespaces))`\n"
            }
            return .success(report)
        } catch {
            return .failure("Failed to execute security find-identity: \(error.localizedDescription)")
        }
    }
}
