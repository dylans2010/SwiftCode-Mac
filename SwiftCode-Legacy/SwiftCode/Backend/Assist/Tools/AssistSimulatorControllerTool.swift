//
//  AssistSimulatorControllerTool.swift
//  SwiftCode
//

import Foundation

public struct AssistSimulatorControllerTool: AssistTool {
    public let id = "simulator_controller"
    public let name = "Simulator Controller"
    public let description = "Controls Apple platform simulators (boot, shutdown, install app, open URL) via simctl."

    public init() {}

    public var capability: ToolCapability { .systemExecution }
    public var riskLevel: ToolRiskLevel { .safeMutation }

    public var parametersSchema: JSONSchema {
        JSONSchema(
            type: "object",
            description: "Controls simulator state. Actions: 'boot', 'shutdown', 'install', 'launch', 'openurl'.",
            properties: [
                "action": JSONSchema(type: "string", description: "Action: 'boot', 'shutdown', 'install', 'launch', or 'openurl'."),
                "device": JSONSchema(type: "string", description: "Device name or UDID (e.g. 'booted', 'iPhone 16 Pro', or UUID)."),
                "appPath": JSONSchema(type: "string", description: "Path to .app bundle when action is 'install'."),
                "bundleId": JSONSchema(type: "string", description: "Bundle identifier when action is 'launch'."),
                "url": JSONSchema(type: "string", description: "URL string when action is 'openurl'.")
            ],
            required: ["action"]
        )
    }

    public func execute(input: [String: Any], context: AssistContext) async throws -> AssistToolResult {
        guard let action = input["action"] as? String else {
            return .failure("Missing required parameter: action")
        }
        let device = (input["device"] as? String) ?? "booted"

        var args: [String] = ["simctl"]
        switch action.lowercased() {
        case "boot":
            args.append(contentsOf: ["boot", device])
        case "shutdown":
            args.append(contentsOf: ["shutdown", device])
        case "install":
            guard let appPath = input["appPath"] as? String, !appPath.isEmpty else {
                return .failure("Action 'install' requires 'appPath'.")
            }
            let resolved = appPath.hasPrefix("/") ? appPath : context.workspaceRoot.appendingPathComponent(appPath).path
            args.append(contentsOf: ["install", device, resolved])
        case "launch":
            guard let bundleId = input["bundleId"] as? String, !bundleId.isEmpty else {
                return .failure("Action 'launch' requires 'bundleId'.")
            }
            args.append(contentsOf: ["launch", device, bundleId])
        case "openurl":
            guard let urlStr = input["url"] as? String, !urlStr.isEmpty else {
                return .failure("Action 'openurl' requires 'url'.")
            }
            args.append(contentsOf: ["openurl", device, urlStr])
        default:
            return .failure("Unsupported action '\(action)'. Supported: boot, shutdown, install, launch, openurl.")
        }

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        proc.arguments = args

        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = pipe

        do {
            try proc.run()
            proc.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let out = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)

            if proc.terminationStatus == 0 {
                return .success("Simulator operation '\(action)' succeeded on device '\(device)'. \(out)")
            } else {
                return .failure("Simulator command failed (exit code \(proc.terminationStatus)): \(out)")
            }
        } catch {
            return .failure("Failed to execute simctl: \(error.localizedDescription)")
        }
    }
}
