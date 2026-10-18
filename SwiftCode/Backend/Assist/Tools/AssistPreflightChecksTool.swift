import Foundation

public struct AssistPreflightChecksTool: AssistTool {
    public let id = "preflight_checks"
    public let name = "Preflight Checks"
    public let description = "Runs environment preflight checks before a build/task: workspace writable, Xcode tools present, DerivedData reachable, free disk space."

    public init() {}

    public var capability: ToolCapability { .diagnostics }
    public var riskLevel: ToolRiskLevel { .safeRead }

    public var parametersSchema: JSONSchema {
        JSONSchema(type: "object", description: "Runs preflight checks.", properties: [:], required: [])
    }

    public func execute(input: [String: Any], context: AssistContext) async throws -> AssistToolResult {
        let fm = FileManager.default
        let root = context.workspaceRoot
        var checks: [(String, Bool, String)] = []
        // 1. Workspace exists and is writable.
        let writable = fm.isWritableFile(atPath: root.path)
        checks.append(("Workspace writable", writable, root.path))
        // 2. xcodebuild present.
        let xcodebuild = fm.isExecutableFile(atPath: "/usr/bin/xcodebuild")
        checks.append(("xcodebuild available", xcodebuild, "/usr/bin/xcodebuild"))
        // 3. swift present.
        let swift = fm.isExecutableFile(atPath: "/usr/bin/swift")
        checks.append(("swift available", swift, "/usr/bin/swift"))
        // 4. codesign present.
        let codesign = fm.isExecutableFile(atPath: "/usr/bin/codesign")
        checks.append(("codesign available", codesign, "/usr/bin/codesign"))
        // 5. DerivedData parent reachable.
        let dd = fm.homeDirectoryForCurrentUser.appendingPathComponent("Library/Developer/Xcode/DerivedData")
        var ddIsDir: ObjCBool = false
        let ddOk = fm.fileExists(atPath: dd.path, isDirectory: &ddIsDir)
        checks.append(("DerivedData reachable", ddOk, dd.path))
        // 6. Free disk space on the workspace volume.
        var diskGB = -1.0
        var diskOk = false
        if let attrs = try? fm.attributesOfFileSystem(forPath: root.path),
           let free = attrs[.systemFreeSize] as? NSNumber {
            diskGB = free.doubleValue / 1_073_741_824.0
            diskOk = diskGB >= 5.0
        }
        checks.append(("Free disk ≥ 5 GB", diskOk, diskGB < 0 ? "unknown" : String(format: "%.1f GB free", diskGB)))
        // 7. .assist_temp artifact storage: writable if it exists, or creatable.
        let temp = root.appendingPathComponent(".assist_temp")
        var tempIsDir: ObjCBool = false
        let tempExists = fm.fileExists(atPath: temp.path, isDirectory: &tempIsDir)
        let tempOk = (tempExists && tempIsDir.boolValue && fm.isWritableFile(atPath: temp.path)) || (!tempExists && writable)
        checks.append(("Artifact storage writable", tempOk, tempExists ? temp.path : temp.path + " (will be created on demand)"))
        var lines = ["Preflight checks:"]
        for (name, ok, detail) in checks {
            lines.append("- [\(ok ? "PASS" : "FAIL")] \(name) — \(detail)")
        }
        let failures = checks.filter { !$0.1 }.count
        return .success(lines.joined(separator: "\n") + "\nResult: \(failures == 0 ? "all checks passed" : "\(failures) check(s) failed")",
                        data: ["checkCount": "\(checks.count)", "failureCount": "\(failures)"])
    }
}
