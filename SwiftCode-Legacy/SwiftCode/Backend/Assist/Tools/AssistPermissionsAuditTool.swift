import Foundation

public struct AssistPermissionsAuditTool: AssistTool {
    public let id = "permissions_audit"
    public let name = "Permissions Audit"
    public let description = "Audits Info.plist usage descriptions, entitlements, and PrivacyInfo.xcprivacy entries, and flags API usage missing a usage description."

    public init() {}

    public var capability: ToolCapability { .diagnostics }
    public var riskLevel: ToolRiskLevel { .safeRead }

    public var parametersSchema: JSONSchema {
        JSONSchema(
            type: "object",
            description: "Audits permissions across the workspace. No parameters.",
            properties: [:],
            required: []
        )
    }

    public func execute(input: [String: Any], context: AssistContext) async throws -> AssistToolResult {
        var usageDescriptions: [String] = []
        var usageFiles: [String] = []
        var entitlementKeys: [String] = []
        var entitlementFiles: [String] = []
        var privacyAPITypes: [String] = []
        var privacyTracking: String = "not declared"
        var privacyFiles: [String] = []

        let allFiles = listAllFiles(under: context.workspaceRoot)
        for fileURL in allFiles {
            let name = fileURL.lastPathComponent
            let relative = relativePath(for: fileURL, workspaceRoot: context.workspaceRoot)
            if name == "Info.plist" {
                if let plist = readPlist(at: fileURL) {
                    for key in plist.keys.sorted() where key.contains("UsageDescription") {
                        usageDescriptions.append(key)
                        if !usageFiles.contains(relative) { usageFiles.append(relative) }
                    }
                }
            } else if fileURL.pathExtension == "entitlements" {
                if let plist = readPlist(at: fileURL) {
                    for key in plist.keys.sorted() {
                        entitlementKeys.append(key)
                    }
                    entitlementFiles.append(relative)
                }
            } else if name == "PrivacyInfo.xcprivacy" {
                if let plist = readPlist(at: fileURL) {
                    if let tracking = plist["NSPrivacyTracking"] as? Bool {
                        privacyTracking = tracking ? "true" : "false"
                    }
                    if let apiTypes = plist["NSPrivacyAccessedAPITypes"] as? [[String: Any]] {
                        for entry in apiTypes {
                            if let apiType = entry["NSPrivacyAccessedAPIType"] as? String {
                                privacyAPITypes.append(apiType)
                            }
                        }
                    }
                    privacyFiles.append(relative)
                }
            }
        }

        // Heuristic: API usage in Swift files that normally needs a usage description.
        let checks: [(marker: String, requiredKey: String)] = [
            (marker: "AVCaptureDevice", requiredKey: "NSCameraUsageDescription"),
            (marker: "CLLocationManager", requiredKey: "NSLocationWhenInUseUsageDescription"),
            (marker: "PHPhotoLibrary", requiredKey: "NSPhotoLibraryUsageDescription"),
            (marker: "CNContactStore", requiredKey: "NSContactsUsageDescription"),
            (marker: "AVAudioRecorder", requiredKey: "NSMicrophoneUsageDescription"),
            (marker: "EKEventStore", requiredKey: "NSCalendarsUsageDescription"),
            (marker: "HKHealthStore", requiredKey: "NSHealthShareUsageDescription"),
            (marker: "SFSpeechRecognizer", requiredKey: "NSSpeechRecognitionUsageDescription")
        ]
        let swiftFiles = allFiles.filter { $0.pathExtension == "swift" }
        var missing: [String] = []
        let usageSet = Set(usageDescriptions)
        for check in checks {
            var usedIn: [String] = []
            for fileURL in swiftFiles {
                guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else { continue }
                if content.contains(check.marker) {
                    usedIn.append(relativePath(for: fileURL, workspaceRoot: context.workspaceRoot))
                }
            }
            if !usedIn.isEmpty && !usageSet.contains(check.requiredKey) {
                // Location also accepts the Always key as an alternative.
                if check.requiredKey == "NSLocationWhenInUseUsageDescription" && usageSet.contains("NSLocationAlwaysUsageDescription") {
                    continue
                }
                missing.append("\(check.marker) used in \(usedIn.prefix(3).joined(separator: ", ")) but \(check.requiredKey) is missing")
            }
        }

        var lines: [String] = []
        lines.append("Usage descriptions (\(usageDescriptions.count)): \(usageDescriptions.sorted().joined(separator: ", "))")
        lines.append("Usage description files: \(usageFiles.joined(separator: ", "))")
        lines.append("Entitlement keys (\(entitlementKeys.count)): \(Array(Set(entitlementKeys)).sorted().joined(separator: ", "))")
        lines.append("Entitlement files: \(entitlementFiles.joined(separator: ", "))")
        lines.append("PrivacyInfo files: \(privacyFiles.joined(separator: ", "))")
        lines.append("NSPrivacyTracking: \(privacyTracking)")
        lines.append("NSPrivacyAccessedAPITypes (\(privacyAPITypes.count)): \(privacyAPITypes.sorted().joined(separator: ", "))")
        if missing.isEmpty {
            lines.append("Missing usage descriptions: none detected by heuristic.")
        } else {
            lines.append("Missing usage descriptions (\(missing.count)):")
            lines.append(contentsOf: missing.map { "  - \($0)" })
        }
        let output = "Permissions audit complete.\n" + lines.joined(separator: "\n")
        return .success(output, data: [
            "usage_description_count": "\(usageDescriptions.count)",
            "entitlement_count": "\(Set(entitlementKeys).count)",
            "privacy_api_count": "\(privacyAPITypes.count)",
            "missing_count": "\(missing.count)",
            "privacy_tracking": privacyTracking
        ])
    }

    private func readPlist(at url: URL) -> [String: Any]? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        var format = PropertyListSerialization.PropertyListFormat.xml
        guard let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: &format) as? [String: Any] else {
            return nil
        }
        return plist
    }

    private func listAllFiles(under root: URL) -> [URL] {
        var found: [URL] = []
        let skipped = Set([".git", "DerivedData", ".build", "Pods", "node_modules", ".swiftpm", "Carthage", "vendor"])
        guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) else {
            return found
        }
        for case let url as URL in enumerator {
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue {
                if skipped.contains(url.lastPathComponent) {
                    enumerator.skipDescendants()
                }
                continue
            }
            found.append(url)
        }
        return found.sorted(by: { $0.path < $1.path })
    }

    private func relativePath(for url: URL, workspaceRoot: URL) -> String {
        let root = workspaceRoot.path
        if url.path == root { return "." }
        if url.path.hasPrefix(root + "/") {
            return String(url.path.dropFirst(root.count + 1))
        }
        return url.lastPathComponent
    }
}
