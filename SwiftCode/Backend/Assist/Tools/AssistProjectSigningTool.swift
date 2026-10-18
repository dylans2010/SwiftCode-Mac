import Foundation

public struct AssistProjectSigningTool: AssistTool {
    public let id = "project_signing"
    public let name = "Signing Check"
    public let description = "Checks code-signing build settings and lists installed provisioning profile filenames without parsing profile contents."

    public init() {}

    public var capability: ToolCapability { .diagnostics }
    public var riskLevel: ToolRiskLevel { .safeRead }

    public var parametersSchema: JSONSchema {
        JSONSchema(
            type: "object",
            description: "Checks code-signing settings for the user's project.",
            properties: [
                "scheme": JSONSchema(type: "string", description: "Optional scheme name for -showBuildSettings."),
                "configuration": JSONSchema(type: "string", description: "Build configuration, e.g. Debug or Release. Default: Debug.")
            ],
            required: []
        )
    }

    public func execute(input: [String: Any], context: AssistContext) async throws -> AssistToolResult {
        #if os(macOS)
        let configuration = (input["configuration"] as? String ?? "Debug").trimmingCharacters(in: .whitespacesAndNewlines)
        let scheme = (input["scheme"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !configuration.isEmpty else { return .failure("Missing required parameter: configuration") }
        guard let project = locateProject(in: context.workspaceRoot) else {
            return .failure("No .xcodeproj or .xcworkspace found at the top level of the workspace.")
        }
        var args: [String] = project.isWorkspace
            ? ["-workspace", project.url.path]
            : ["-project", project.url.path]
        if let scheme, !scheme.isEmpty {
            args += ["-scheme", scheme]
        }
        args += ["-configuration", configuration, "-showBuildSettings"]
        let result: (status: Int32, output: String)
        do {
            result = try runProcess(executable: "/usr/bin/xcodebuild", args: args, cwd: context.workspaceRoot.path)
        } catch {
            return .failure("Failed to run xcodebuild -showBuildSettings: \(error.localizedDescription)")
        }
        guard result.status == 0 else {
            return .failure("xcodebuild -showBuildSettings failed: \(result.output)")
        }
        let wanted = ["CODE_SIGN_STYLE", "DEVELOPMENT_TEAM", "PRODUCT_BUNDLE_IDENTIFIER", "CODE_SIGN_IDENTITY", "PROVISIONING_PROFILE_SPECIFIER"]
        var settings: [String: String] = [:]
        for line in result.output.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let equals = trimmed.firstIndex(of: "=") else { continue }
            let name = trimmed[..<equals].trimmingCharacters(in: .whitespaces)
            if wanted.contains(String(name)) {
                let value = trimmed[trimmed.index(after: equals)...].trimmingCharacters(in: .whitespaces)
                settings[String(name)] = String(value)
            }
        }
        let profiles = provisioningProfileNames()
        let summary = """
        Signing for configuration '\(configuration)':
        CODE_SIGN_STYLE = \(settings["CODE_SIGN_STYLE"] ?? "(not set)")
        DEVELOPMENT_TEAM = \(settings["DEVELOPMENT_TEAM"] ?? "(not set)")
        PRODUCT_BUNDLE_IDENTIFIER = \(settings["PRODUCT_BUNDLE_IDENTIFIER"] ?? "(not set)")
        CODE_SIGN_IDENTITY = \(settings["CODE_SIGN_IDENTITY"] ?? "(not set)")
        PROVISIONING_PROFILE_SPECIFIER = \(settings["PROVISIONING_PROFILE_SPECIFIER"] ?? "(not set)")
        Provisioning profiles installed: \(profiles.count)
        """
        var data: [String: String] = [
            "configuration": configuration,
            "codeSignStyle": settings["CODE_SIGN_STYLE"] ?? "",
            "developmentTeam": settings["DEVELOPMENT_TEAM"] ?? "",
            "bundleId": settings["PRODUCT_BUNDLE_IDENTIFIER"] ?? "",
            "codeSignIdentity": settings["CODE_SIGN_IDENTITY"] ?? "",
            "provisioningProfileSpecifier": settings["PROVISIONING_PROFILE_SPECIFIER"] ?? "",
            "provisioningProfileCount": "\(profiles.count)",
            "provisioningProfiles": profiles.joined(separator: ",")
        ]
        if let scheme, !scheme.isEmpty { data["scheme"] = scheme }
        return .success(summary, data: data)
        #else
        return .failure("Signing checks require macOS with xcodebuild.")
        #endif
    }

    private func provisioningProfileNames() -> [String] {
        let profilesDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/MobileDevice/Provisioning Profiles")
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: profilesDir,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return [] }
        return entries
            .filter { $0.pathExtension == "mobileprovision" }
            .map { $0.lastPathComponent }
            .sorted()
    }

    private struct LocatedBundle {
        let url: URL
        let isWorkspace: Bool
    }

    private func locateProject(in workspaceRoot: URL) -> LocatedBundle? {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(
            at: workspaceRoot,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return nil }
        let workspaces = entries.filter { $0.pathExtension == "xcworkspace" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
        if let ws = workspaces.first { return LocatedBundle(url: ws, isWorkspace: true) }
        let projects = entries.filter { $0.pathExtension == "xcodeproj" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
        if let proj = projects.first { return LocatedBundle(url: proj, isWorkspace: false) }
        return nil
    }

    #if os(macOS)
    private func runProcess(executable: String, args: [String], cwd: String) throws -> (status: Int32, output: String) {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = args
        process.currentDirectoryURL = URL(fileURLWithPath: cwd)
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let output = String(data: data, encoding: .utf8) ?? ""
        return (process.terminationStatus, output)
    }
    #endif
}
