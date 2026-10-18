//
//  AssistNetworkSecurityAuditorTool.swift
//  SwiftCode
//

import Foundation

public struct AssistNetworkSecurityAuditorTool: AssistTool {
    public let id = "network_security_auditor"
    public let name = "Network Security & ATS Auditor"
    public let description = "Audits NSAppTransportSecurity in Info.plist for insecure HTTP and ATS exceptions."

    public init() {}

    public var capability: ToolCapability { .diagnostics }
    public var riskLevel: ToolRiskLevel { .safeRead }

    public var parametersSchema: JSONSchema {
        JSONSchema(
            type: "object",
            description: "Audits App Transport Security (ATS) settings in Info.plist for plain HTTP exceptions.",
            properties: [
                "path": JSONSchema(type: "string", description: "Optional path to Info.plist. Defaults to searching workspace.")
            ],
            required: []
        )
    }

    public func execute(input: [String: Any], context: AssistContext) async throws -> AssistToolResult {
        let root = context.workspaceRoot
        var plistURL: URL?

        if let explicit = input["path"] as? String, !explicit.isEmpty {
            plistURL = explicit.hasPrefix("/") ? URL(fileURLWithPath: explicit) : root.appendingPathComponent(explicit)
        } else {
            let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles, .skipsPackageDescendants])
            while let item = enumerator?.nextObject() as? URL {
                if item.lastPathComponent == "Info.plist" {
                    plistURL = item
                    break
                }
            }
        }

        guard let targetPlist = plistURL, FileManager.default.fileExists(atPath: targetPlist.path),
              let data = try? Data(contentsOf: targetPlist),
              let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any] else {
            return .success("No valid Info.plist found in workspace.")
        }

        guard let ats = plist["NSAppTransportSecurity"] as? [String: Any] else {
            return .success("✅ NSAppTransportSecurity is in default secure mode (all plain HTTP requests blocked, TLS 1.2+ required).")
        }

        var report = "### App Transport Security (ATS) Audit (`\(targetPlist.lastPathComponent)`):\n\n"
        let allowsArbitrary = ats["NSAllowsArbitraryLoads"] as? Bool ?? false
        let allowsLocal = ats["NSAllowsLocalNetworking"] as? Bool ?? false
        let exceptionDomains = ats["NSExceptionDomains"] as? [String: Any] ?? [:]

        report += "- **Allows Arbitrary HTTP Loads**: \(allowsArbitrary ? "⚠️ YES (Potential App Store Review Risk)" : "✅ NO")\n"
        report += "- **Allows Local Networking**: \(allowsLocal ? "YES" : "NO")\n"
        report += "- **Exception Domains**: \(exceptionDomains.count) configured\n\n"

        if !exceptionDomains.isEmpty {
            report += "#### Configured Domain Exceptions:\n"
            for (domain, config) in exceptionDomains {
                report += "- **\(domain)**: `\(config)`\n"
            }
        }

        return .success(report)
    }
}
