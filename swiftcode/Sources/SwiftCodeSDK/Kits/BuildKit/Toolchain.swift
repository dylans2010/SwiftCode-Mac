import Foundation
import SwiftCodeSubprocess

public struct DeveloperToolInfo: Codable, Sendable {
    public let name: String
    public let path: String
    public let version: String?
    public let isAvailable: Bool

    public init(name: String, path: String, version: String? = nil, isAvailable: Bool = true) {
        self.name = name
        self.path = path
        self.version = version
        self.isAvailable = isAvailable
    }
}

public final class Toolchain: Sendable {
    public init() {}

    public static let standard = Toolchain()

    public func discoverTools() -> [String: DeveloperToolInfo] {
        var tools: [String: DeveloperToolInfo] = [:]
        let names = ["swift", "swiftc", "xcodebuild", "clang", "git", "node", "npm", "python3"]

        for name in names {
            if let path = resolveExecutable(name: name) {
                let ver = queryVersion(toolPath: path)
                tools[name] = DeveloperToolInfo(name: name, path: path, version: ver, isAvailable: true)
            } else {
                tools[name] = DeveloperToolInfo(name: name, path: "", version: nil, isAvailable: false)
            }
        }
        return tools
    }

    public func resolveExecutable(name: String) -> String? {
        let candidatePaths = [
            "/usr/bin/\(name)",
            "/usr/local/bin/\(name)",
            "/opt/homebrew/bin/\(name)",
            "/Library/Developer/CommandLineTools/usr/bin/\(name)"
        ]

        for p in candidatePaths {
            if FileManager.default.isExecutableFile(atPath: p) {
                return p
            }
        }

        // Fall back to `which` via the shared subprocess seam (SwiftCodeSubprocess).
        // Legacy ran /usr/bin/which directly through Process; behaviour is identical.
        let which = "/usr/bin/which"
        guard FileManager.default.isExecutableFile(atPath: which) else { return nil }
        guard let output = try? Subprocess.run(which, [name]),
              output.status == 0 else { return nil }
        let str = output.stdoutText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !str.isEmpty, FileManager.default.isExecutableFile(atPath: str) else { return nil }
        return str
    }

    private func queryVersion(toolPath: String) -> String? {
        // Legacy invoked `<tool> --version` and kept the first line (max 80 chars).
        // SwiftCodeSubprocess reads both pipes concurrently, so a chatty tool
        // cannot deadlock us the way Legacy's sequential reads could.
        guard let output = try? Subprocess.run(toolPath, ["--version"]) else { return nil }
        let combined = output.stdoutText + output.stderrText
        let trimmed = combined.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let firstLine = trimmed.components(separatedBy: .newlines).first ?? trimmed
        return String(firstLine.prefix(80))
    }
}

public struct BuildConfig: Sendable {
    public enum Configuration: String, Sendable {
        case debug = "debug"
        case release = "release"
    }

    public let projectPath: String
    public let configuration: Configuration
    public let target: String?
    public let destination: String?
    public let additionalArguments: [String]
    public let environmentVariables: [String: String]

    public init(
        projectPath: String,
        configuration: Configuration = .release,
        target: String? = nil,
        destination: String? = nil,
        additionalArguments: [String] = [],
        environmentVariables: [String: String] = [:]
    ) {
        self.projectPath = projectPath
        self.configuration = configuration
        self.target = target
        self.destination = destination
        self.additionalArguments = additionalArguments
        self.environmentVariables = environmentVariables
    }
}
