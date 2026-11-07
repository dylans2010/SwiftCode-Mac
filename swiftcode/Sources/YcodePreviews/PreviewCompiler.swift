import Foundation
import YcodeBuild
import YcodeSubprocess

public struct PreviewIssue: Equatable, Sendable, CustomStringConvertible {
    public var file: URL?
    public var line: Int
    public var column: Int
    public var message: String
    public init(file: URL?, line: Int = 0, column: Int = 0, message: String) {
        self.file = file
        self.line = line
        self.column = column
        self.message = message
    }

    public var description: String {
        guard let file else { return message }
        return "\(file.lastPathComponent):\(line): \(message)"
    }
}

public enum PreviewFailure: Error, Equatable, Sendable, CustomStringConvertible {
    case compile([PreviewIssue])
    case unsupported(String)
    case host(String)

    public var description: String {
        switch self {
        case .compile(let issues): issues.first?.description ?? "Compiling the preview failed"
        case .unsupported(let m): "Unsupported target kind: \(m)"
        case .host(let m): m
        }
    }

    public var issues: [PreviewIssue] {
        if case .compile(let i) = self { return i }
        return []
    }
}

public struct PreviewCompiler: Sendable {
    public var platform: PreviewPlatform
    public var deploymentTarget: String
    public var moduleName: String
    public var moduleCache: URL
    public var xcrun = "/usr/bin/xcrun"
    public var extraFlags: [String] = []

    public init(platform: PreviewPlatform, deploymentTarget: String, moduleName: String, moduleCache: URL) {
        self.platform = platform
        self.deploymentTarget = deploymentTarget
        self.moduleName = moduleName
        self.moduleCache = moduleCache.standardizedFileURL
    }

    public func payloadArguments(sources: [URL], output: URL) -> [String] {
        ["--sdk", platform.sdk, "swiftc",
         "-target", platform.targetTriple(deploymentTarget: deploymentTarget),
         "-emit-library", "-module-name", moduleName, "-parse-as-library", "-wmo", "-Onone", "-gnone",
         "-D", "DEBUG", "-D", "SWIFTCODE_PREVIEW",
         "-module-cache-path", moduleCache.path,
         "-Xlinker", "-install_name", "-Xlinker", "@rpath/\(output.lastPathComponent)",
         "-o", output.path]
            + (extraFlags.contains("-swift-version") ? [] : ["-swift-version", "5"])
            + extraFlags + sources.map(\.path)
    }

    public func compilePayload(_ sources: PreviewPayloadGenerator.Sources, output: URL) throws(PreviewFailure) {
        try? FileManager.default.createDirectory(at: moduleCache, withIntermediateDirectories: true)
        try? FileManager.default.removeItem(at: output)
        let out: Subprocess.Output
        do { out = try Subprocess.run(xcrun, payloadArguments(sources: sources.files, output: output)) } catch {
            throw .host("could not run xcrun: \(error)")
        }
        guard out.status == 0, FileManager.default.fileExists(atPath: output.path) else {
            throw .compile(Self.issues(from: out.stdoutText + "\n" + out.stderrText, lineMaps: sources.lineMaps))
        }
    }

    public static func issues(from log: String, lineMaps: [String: PreviewPayloadGenerator.LineMap]) -> [PreviewIssue] {
        let errors = DiagnosticParser.parse(log).filter { $0.severity == .error }
        var out: [PreviewIssue] = []
        for d in errors {
            if let l = d.location, let map = lineMaps[l.file] ?? lineMaps[URL(fileURLWithPath: l.file).standardizedFileURL.path] {
                out.append(PreviewIssue(file: map.original, line: map.fileLine(l.line), column: l.column, message: d.message))
            } else {
                out.append(PreviewIssue(file: nil, message: d.message))
            }
        }
        if out.isEmpty {
            let last = log.split(separator: "\n").last(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }).map(String.init)
            out.append(PreviewIssue(file: nil, message: last ?? "Compiling the preview failed"))
        }
        return out.filter { $0.file != nil } + out.filter { $0.file == nil }
    }
}
