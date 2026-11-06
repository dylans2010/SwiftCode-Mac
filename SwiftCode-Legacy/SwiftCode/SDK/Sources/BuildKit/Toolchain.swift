import Foundation
import DiagnosticsKit

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

        // Try 'which' via Process
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = [name]
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
            if process.terminationStatus == 0 {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                if let str = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !str.isEmpty, FileManager.default.isExecutableFile(atPath: str) {
                    return str
                }
            }
        } catch {}

        return nil
    }

    private func queryVersion(toolPath: String) -> String? {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: toolPath)
        process.arguments = ["--version"]
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) {
                let firstLine = output.components(separatedBy: .newlines).first ?? output
                return String(firstLine.prefix(80))
            }
        } catch {}
        return nil
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
