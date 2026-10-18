//
//  AssistTestCoverageReporterTool.swift
//  SwiftCode
//

import Foundation

public struct AssistTestCoverageReporterTool: AssistTool {
    public let id = "test_coverage_reporter"
    public let name = "Test Coverage Reporter"
    public let description = "Extracts line and target test coverage metrics from build and test artifacts via xccov."

    public init() {}

    public var capability: ToolCapability { .diagnostics }
    public var riskLevel: ToolRiskLevel { .safeRead }

    public var parametersSchema: JSONSchema {
        JSONSchema(
            type: "object",
            description: "Parses test coverage data (.xccovreport) in DerivedData or workspace test results.",
            properties: [
                "reportPath": JSONSchema(type: "string", description: "Optional explicit path to an .xccovreport file.")
            ],
            required: []
        )
    }

    public func execute(input: [String: Any], context: AssistContext) async throws -> AssistToolResult {
        let derivedData = URL(fileURLWithPath: ("~/Library/Developer/Xcode/DerivedData" as NSString).expandingTildeInPath)
        var coverageURL: URL?

        if let explicit = input["reportPath"] as? String, !explicit.isEmpty {
            coverageURL = URL(fileURLWithPath: explicit)
        } else {
            // Find most recent .xccovreport or .xccovarchive
            if let enumerator = FileManager.default.enumerator(at: derivedData, includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles]) {
                var candidates: [(url: URL, date: Date)] = []
                while let item = enumerator.nextObject() as? URL {
                    if item.pathExtension == "xccovreport" || item.pathExtension == "xccovarchive" {
                        let date = (try? item.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? Date.distantPast
                        candidates.append((url: item, date: date))
                    }
                }
                coverageURL = candidates.sorted(by: { $0.date > $1.date }).first?.url
            }
        }

        guard let targetReport = coverageURL, FileManager.default.fileExists(atPath: targetReport.path) else {
            return .success("No active .xccovreport or coverage archive found in DerivedData. Ensure 'Code Coverage' is enabled in your Xcode Scheme test settings.")
        }

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        proc.arguments = ["xccov", "view", "--report", targetReport.path]

        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = pipe

        do {
            try proc.run()
            proc.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)

            if output.isEmpty {
                return .success("Coverage report found at \(targetReport.lastPathComponent), but yielded no text metrics.")
            }

            let lines = output.components(separatedBy: .newlines)
            let snippet = lines.prefix(40).joined(separator: "\n")
            return .success("### Test Coverage Report (\(targetReport.lastPathComponent)):\n\n```\n\(snippet)\n```")
        } catch {
            return .failure("Failed to execute xccov: \(error.localizedDescription)")
        }
    }
}
