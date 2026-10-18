//
//  AssistXcodeDeviceDestinationTool.swift
//  SwiftCode
//

import Foundation

public struct AssistXcodeDeviceDestinationTool: AssistTool {
    public let id = "xcode_device_destination_finder"
    public let name = "Xcode Device Destination Finder"
    public let description = "Lists connected physical Apple devices and available simulator runtimes for building and testing."

    public init() {}

    public var capability: ToolCapability { .diagnostics }
    public var riskLevel: ToolRiskLevel { .safeRead }

    public var parametersSchema: JSONSchema {
        JSONSchema(
            type: "object",
            description: "Finds available simulators (iOS, watchOS, tvOS, visionOS) and build destination identifiers.",
            properties: [
                "platform": JSONSchema(type: "string", description: "Optional platform filter (e.g. 'iOS', 'watchOS', 'macOS').")
            ],
            required: []
        )
    }

    public func execute(input: [String: Any], context: AssistContext) async throws -> AssistToolResult {
        let platformFilter = (input["platform"] as? String)?.lowercased()

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        proc.arguments = ["simctl", "list", "devices", "available", "-j"]

        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = pipe

        do {
            try proc.run()
            proc.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let devicesDict = json["devices"] as? [String: [[String: Any]]] else {
                return .failure("Unable to parse simctl JSON response.")
            }

            var report = "### Available Simulator Destinations:\n\n"
            var count = 0

            for (runtime, devices) in devicesDict {
                if let filter = platformFilter, !runtime.lowercased().contains(filter) {
                    continue
                }
                let cleanRuntime = runtime.replacingOccurrences(of: "com.apple.CoreSimulator.SimRuntime.", with: "")
                report += "#### \(cleanRuntime)\n"

                for dev in devices.prefix(6) {
                    let name = dev["name"] as? String ?? "Device"
                    let udid = dev["udid"] as? String ?? ""
                    let state = dev["state"] as? String ?? "Shutdown"
                    report += "- **\(name)** (`\(state)`) — UDID: `\(udid)`\n"
                    count += 1
                }
                report += "\n"
            }

            if count == 0 {
                return .success("No available simulators matching the requested filter.")
            }
            return .success(report)
        } catch {
            return .failure("Failed to query simulator devices via simctl: \(error.localizedDescription)")
        }
    }
}
