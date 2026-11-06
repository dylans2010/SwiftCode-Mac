import Foundation

public struct AssistProvisioningCheckTool: AssistTool {
    public let id = "provisioning_check"
    public let name = "Provisioning Check"
    public let description = "Lists installed provisioning profiles, reports expiration, and compares App IDs against an optional bundle ID."

    public init() {}

    public var capability: ToolCapability { .diagnostics }
    public var riskLevel: ToolRiskLevel { .safeRead }

    public var parametersSchema: JSONSchema {
        JSONSchema(
            type: "object",
            description: "Checks installed provisioning profiles. Optional bundleId filters the App ID comparison.",
            properties: [
                "bundleId": JSONSchema(type: "string", description: "Bundle ID to compare against each profile App ID (optional).")
            ],
            required: []
        )
    }

    public func execute(input: [String: Any], context: AssistContext) async throws -> AssistToolResult {
        let bundleId = (input["bundleId"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let securityPath = "/usr/bin/security"
        guard FileManager.default.fileExists(atPath: securityPath) else {
            return .failure("security tool not found at /usr/bin/security.")
        }
        let profilesDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/MobileDevice/Provisioning Profiles")
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: profilesDir.path, isDirectory: &isDir), isDir.boolValue else {
            return .failure("No provisioning profiles directory found at ~/Library/MobileDevice/Provisioning Profiles. No profiles are installed.")
        }
        let contents = (try? FileManager.default.contentsOfDirectory(at: profilesDir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
        let profiles = contents.filter { $0.pathExtension == "mobileprovision" }.sorted(by: { $0.lastPathComponent < $1.lastPathComponent })
        guard !profiles.isEmpty else {
            return .failure("No .mobileprovision files found in ~/Library/MobileDevice/Provisioning Profiles.")
        }

        var lines: [String] = []
        var expiredCount = 0
        var expiringCount = 0
        var matchCount = 0
        var mismatchCount = 0
        let now = Date()
        let expiringThreshold = now.addingTimeInterval(30 * 24 * 60 * 60)
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium
        dateFormatter.timeStyle = .none

        for profileURL in profiles {
            let (exitCode, stdout, stderr) = runProcess(
                executablePath: securityPath,
                arguments: ["cms", "-D", "-i", profileURL.path],
                workingDirectory: context.workspaceRoot
            )
            guard exitCode == 0, let plistData = stdout.data(using: .utf8) else {
                lines.append("\(profileURL.lastPathComponent) - could not decode: \(stderr.trimmingCharacters(in: .whitespacesAndNewlines).suffix(300))")
                continue
            }
            var format = PropertyListSerialization.PropertyListFormat.xml
            guard let plist = try? PropertyListSerialization.propertyList(from: plistData, options: [], format: &format) as? [String: Any] else {
                lines.append("\(profileURL.lastPathComponent) - could not parse decoded plist.")
                continue
            }
            let name = plist["Name"] as? String ?? profileURL.lastPathComponent
            let team = plist["TeamName"] as? String ?? "(unknown team)"
            let expiration = plist["ExpirationDate"] as? Date
            let expirationText = expiration.map { dateFormatter.string(from: $0) } ?? "(unknown)"
            var status = "valid"
            if let expiration = expiration {
                if expiration < now {
                    status = "EXPIRED"
                    expiredCount += 1
                } else if expiration < expiringThreshold {
                    status = "expiring soon"
                    expiringCount += 1
                }
            }
            var appId = "(unknown)"
            if let entitlements = plist["Entitlements"] as? [String: Any],
               let applicationIdentifier = entitlements["application-identifier"] as? String {
                appId = applicationIdentifier
            } else if let appIDName = plist["AppIDName"] as? String {
                appId = appIDName
            }
            var comparison = "no bundleId given"
            if let bundleId = bundleId, !bundleId.isEmpty {
                let bundlePart: String
                if let dot = appId.firstIndex(of: ".") {
                    bundlePart = String(appId[appId.index(after: dot)...])
                } else {
                    bundlePart = appId
                }
                if bundlePart == bundleId {
                    comparison = "matches \(bundleId)"
                    matchCount += 1
                } else if bundlePart == "*" {
                    comparison = "wildcard - covers \(bundleId)"
                    matchCount += 1
                } else {
                    comparison = "MISMATCH (profile App ID bundle: \(bundlePart))"
                    mismatchCount += 1
                }
            }
            lines.append("\(name) - team: \(team) - AppID: \(appId) - expires: \(expirationText) - \(status) - \(comparison)")
        }

        var header = "Provisioning profiles: \(profiles.count), expired: \(expiredCount), expiring within 30 days: \(expiringCount)"
        if let bundleId = bundleId, !bundleId.isEmpty {
            header += ", bundle \(bundleId): \(matchCount) match(es), \(mismatchCount) mismatch(es)"
        }
        let output = header + "\n" + lines.joined(separator: "\n")
        return .success(output, data: [
            "profile_count": "\(profiles.count)",
            "expired_count": "\(expiredCount)",
            "expiring_count": "\(expiringCount)",
            "match_count": "\(matchCount)",
            "mismatch_count": "\(mismatchCount)",
            "bundle_id": bundleId ?? ""
        ])
    }

    private func runProcess(executablePath: String, arguments: [String], workingDirectory: URL?) -> (exitCode: Int32, stdout: String, stderr: String) {
        AssistToolingSupport.runProcess(executablePath: executablePath, arguments: arguments, workingDirectory: workingDirectory)
    }
}
