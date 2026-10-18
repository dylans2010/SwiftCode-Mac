//
//  AssistXCResultParserTool.swift
//  SwiftCode
//

import Foundation

public struct AssistXCResultParserTool: AssistTool {
    public let id = "xcresult_parser"
    public let name = "XCResult Bundle Parser"
    public let description = "Locates and parses .xcresult bundles to extract test failures, warnings, and compilation diagnostics."

    public init() {}

    public var capability: ToolCapability { .diagnostics }
    public var riskLevel: ToolRiskLevel { .safeRead }

    public var parametersSchema: JSONSchema {
        JSONSchema(
            type: "object",
            description: "Parses Xcode .xcresult test and build results for structured logs and test failure locations.",
            properties: [
                "bundlePath": JSONSchema(type: "string", description: "Optional specific path to an .xcresult bundle. If omitted, the latest result bundle in DerivedData is used.")
            ],
            required: []
        )
    }

    public func execute(input: [String: Any], context: AssistContext) async throws -> AssistToolResult {
        var targetURL: URL?

        if let customPath = input["bundlePath"] as? String, !customPath.isEmpty {
            let u = customPath.hasPrefix("/") ? URL(fileURLWithPath: customPath) : context.workspaceRoot.appendingPathComponent(customPath)
            if FileManager.default.fileExists(atPath: u.path) {
                targetURL = u
            }
        }

        // Search in DerivedData
        if targetURL == nil {
            let derivedData = URL(fileURLWithPath: ("~/Library/Developer/Xcode/DerivedData" as NSString).expandingTildeInPath)
            if let enumerator = FileManager.default.enumerator(at: derivedData, includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles]) {
                var candidateResults: [(url: URL, date: Date)] = []
                while let item = enumerator.nextObject() as? URL {
                    if item.pathExtension == "xcresult" {
                        let date = (try? item.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? Date.distantPast
                        candidateResults.append((url: item, date: date))
                    }
                }
                targetURL = candidateResults.sorted(by: { $0.date > $1.date }).first?.url
            }
        }

        guard let xcresultURL = targetURL else {
            return .success("No .xcresult bundle found. Run a build or test suite first.")
        }

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        proc.arguments = ["xcresulttool", "get", "--format", "json", "--path", xcresultURL.path]

        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = pipe

        do {
            try proc.run()
            proc.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return .success("Parsed .xcresult at \(xcresultURL.lastPathComponent), but output is non-JSON or bundle is empty.")
            }

            var report = "### XCResult Summary (\(xcresultURL.lastPathComponent)):\n\n"
            if let issues = json["issues"] as? [String: Any] {
                if let errors = issues["errorSummaries"] as? [String: Any], let val = errors["_values"] as? [[String: Any]] {
                    report += "#### Errors (\(val.count)):\n"
                    for err in val.prefix(10) {
                        if let msg = (err["message"] as? [String: Any])?["_value"] as? String {
                            report += "- ❌ \(msg)\n"
                        }
                    }
                }
                if let warnings = issues["warningSummaries"] as? [String: Any], let val = warnings["_values"] as? [[String: Any]] {
                    report += "#### Warnings (\(val.count)):\n"
                    for warn in val.prefix(10) {
                        if let msg = (warn["message"] as? [String: Any])?["_value"] as? String {
                            report += "- ⚠️ \(msg)\n"
                        }
                    }
                }
            } else {
                report += "No compile errors or test failure summaries recorded in bundle."
            }

            return .success(report)
        } catch {
            return .failure("Failed to parse .xcresult via xcresulttool: \(error.localizedDescription)")
        }
    }
}
