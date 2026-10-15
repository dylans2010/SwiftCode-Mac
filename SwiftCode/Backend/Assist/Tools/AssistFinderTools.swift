//
//  AssistFinderTools.swift
//  SwiftCode
//
//  Native macOS Finder integration tools for SwiftCode Assist.
//  Supports opening and revealing files or folders in Finder with workspace scoping.
//

import Foundation
import AppKit

public struct AssistOpenInFinderTool: AssistTool {
    public let id: String = "open_in_finder"
    public let name: String = "Open in Finder"
    public let description: String = "Opens a file or directory in Finder or its default application."

    public var parametersSchema: JSONSchema {
        JSONSchema(
            type: "object",
            description: "Opens a file or directory in macOS Finder or default application.",
            properties: [
                "path": JSONSchema(type: "string", description: "Workspace-relative or absolute path to the file or directory.")
            ],
            required: ["path"]
        )
    }

    public var capability: ToolCapability { .systemExecution }
    public var riskLevel: ToolRiskLevel { .safeRead }
    public var isReadOnly: Bool { true }
    public var isMutating: Bool { false }

    public init() {}

    public func execute(input: [String: Any], context: AssistContext) async throws -> AssistToolResult {
        guard let path = input["path"] as? String, !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .failure("Missing required argument: 'path'")
        }

        let targetURL: URL
        if path.hasPrefix("/") {
            targetURL = URL(fileURLWithPath: path)
        } else {
            targetURL = context.workspaceRoot.appendingPathComponent(path)
        }

        guard FileManager.default.fileExists(atPath: targetURL.path) else {
            return .failure("Path does not exist: '\(path)' (resolved to \(targetURL.path))")
        }

        let success = await MainActor.run {
            NSWorkspace.shared.open(targetURL)
        }

        if success {
            return .success("Opened in Finder: \(targetURL.lastPathComponent)", data: ["path": targetURL.path])
        } else {
            // Fallback to /usr/bin/open
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            p.arguments = [targetURL.path]
            try? p.run()
            p.waitUntilExit()
            if p.terminationStatus == 0 {
                return .success("Opened in Finder: \(targetURL.lastPathComponent)", data: ["path": targetURL.path])
            }
            return .failure("Failed to open path in Finder: \(targetURL.path)")
        }
    }
}

public struct AssistRevealInFinderTool: AssistTool {
    public let id: String = "reveal_in_finder"
    public let name: String = "Reveal in Finder"
    public let description: String = "Reveals and selects a file or directory in macOS Finder."

    public var parametersSchema: JSONSchema {
        JSONSchema(
            type: "object",
            description: "Reveals and highlights a file or directory in Finder.",
            properties: [
                "path": JSONSchema(type: "string", description: "Workspace-relative or absolute path to the item to reveal.")
            ],
            required: ["path"]
        )
    }

    public var capability: ToolCapability { .systemExecution }
    public var riskLevel: ToolRiskLevel { .safeRead }
    public var isReadOnly: Bool { true }
    public var isMutating: Bool { false }

    public init() {}

    public func execute(input: [String: Any], context: AssistContext) async throws -> AssistToolResult {
        guard let path = input["path"] as? String, !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .failure("Missing required argument: 'path'")
        }

        let targetURL: URL
        if path.hasPrefix("/") {
            targetURL = URL(fileURLWithPath: path)
        } else {
            targetURL = context.workspaceRoot.appendingPathComponent(path)
        }

        guard FileManager.default.fileExists(atPath: targetURL.path) else {
            return .failure("Path does not exist: '\(path)' (resolved to \(targetURL.path))")
        }

        await MainActor.run {
            NSWorkspace.shared.activateFileViewerSelecting([targetURL])
        }

        return .success("Revealed in Finder: \(targetURL.lastPathComponent)", data: ["path": targetURL.path])
    }
}
