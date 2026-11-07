import Foundation

public enum FileAction: String, Sendable, CaseIterable {
    case compile, analyze, preprocess, assemble

    public var title: String { rawValue.prefix(1).uppercased() + rawValue.dropFirst() }

    public func supports(_ language: SourceLanguage) -> Bool {
        switch self {
        case .compile, .assemble: return true
        case .analyze, .preprocess: return language != .swift
        }
    }

    var outputExtension: String {
        switch self {
        case .compile: "o"
        case .analyze: "plist"
        case .preprocess: "i"
        case .assemble: "s"
        }
    }
}

public enum SourceLanguage: String, Sendable {
    case swift, c, objc, cxx, objcxx

    public init?(path: String) {
        switch URL(fileURLWithPath: path).pathExtension.lowercased() {
        case "swift": self = .swift
        case "c": self = .c
        case "m": self = .objc
        case "cc", "cpp", "cxx", "c++": self = .cxx
        case "mm": self = .objcxx
        default: return nil
        }
    }

    var clangName: String {
        switch self {
        case .swift: "swift"
        case .c: "c"
        case .objc: "objective-c"
        case .cxx: "c++"
        case .objcxx: "objective-c++"
        }
    }
}

public struct FileBuildContext: Equatable, Sendable {
    public var moduleName: String
    public var moduleSources: [String] = []
    public var sdkPath: String?
    public var targetTriple: String?
    public var swiftVersion: String?
    public var includePaths: [String] = []
    public var frameworkPaths: [String] = []
    public var defines: [String] = []
    public var outputDirectory: String

    public init(moduleName: String, moduleSources: [String] = [], sdkPath: String? = nil, targetTriple: String? = nil,
                swiftVersion: String? = nil, includePaths: [String] = [], frameworkPaths: [String] = [], defines: [String] = [],
                outputDirectory: String) {
        self.moduleName = moduleName
        self.moduleSources = moduleSources
        self.sdkPath = sdkPath
        self.targetTriple = targetTriple
        self.swiftVersion = swiftVersion
        self.includePaths = includePaths
        self.frameworkPaths = frameworkPaths
        self.defines = defines
        self.outputDirectory = outputDirectory
    }

    public static func swiftLanguageMode(_ setting: String) -> String {
        let parts = setting.split(separator: ".")
        if parts.count >= 2, parts[0] == "4", parts[1] == "2" { return "4.2" }
        return parts.first.map(String.init) ?? setting
    }

    public static func moduleIdentifier(_ name: String) -> String {
        var out = String(name.map { $0.isLetter || $0.isNumber || $0 == "_" ? $0 : "_" })
        if let f = out.first, f.isNumber { out = "_" + out }
        return out.isEmpty ? "main" : out
    }
}

public struct FileActionRunner: Sendable {
    public var swiftc: [String]
    public var clang: [String]

    public init(swiftc: [String]? = nil, clang: [String]? = nil) {
        #if os(macOS)
        self.swiftc = swiftc ?? ["/usr/bin/xcrun", "swiftc"]
        self.clang = clang ?? ["/usr/bin/xcrun", "clang"]
        #else
        self.swiftc = swiftc ?? ["/usr/bin/env", "swiftc"]
        self.clang = clang ?? ["/usr/bin/env", "clang"]
        #endif
    }

    public static func outputPath(_ action: FileAction, file: String, context: FileBuildContext) -> String? {
        guard let lang = SourceLanguage(path: file), action.supports(lang) else { return nil }
        let base = URL(fileURLWithPath: file).deletingPathExtension().lastPathComponent
        return URL(fileURLWithPath: context.outputDirectory).appendingPathComponent("\(base).\(action.outputExtension)").path
    }

    public func command(_ action: FileAction, file: String, context c: FileBuildContext) -> [String]? {
        guard let lang = SourceLanguage(path: file), action.supports(lang),
              let out = Self.outputPath(action, file: file, context: c) else { return nil }
        if lang == .swift {
            var a = swiftc + ["-frontend", action == .assemble ? "-S" : "-c", "-primary-file", file]
            let others = c.moduleSources.filter { URL(fileURLWithPath: $0).standardizedFileURL != URL(fileURLWithPath: file).standardizedFileURL }
            a += others
            if !([file] + others).contains(where: { URL(fileURLWithPath: $0).lastPathComponent == "main.swift" }) {
                a.append("-parse-as-library")
            }
            a += ["-module-name", c.moduleName]
            if let sdk = c.sdkPath { a += ["-sdk", sdk] }
            if let t = c.targetTriple { a += ["-target", t] }
            if let v = c.swiftVersion, !v.isEmpty { a += ["-swift-version", FileBuildContext.swiftLanguageMode(v)] }
            for i in c.includePaths { a += ["-I", i] }
            for f in c.frameworkPaths { a += ["-F", f] }
            for d in c.defines { a += ["-D", d] }
            return a + ["-o", out]
        }
        var a = clang + ["-x", lang.clangName]
        switch action {
        case .compile: a.append("-c")
        case .analyze: a += ["--analyze", "-Xclang", "-analyzer-output=text"]
        case .preprocess: a.append("-E")
        case .assemble: a.append("-S")
        }
        a.append(file)
        if let sdk = c.sdkPath { a += ["-isysroot", sdk] }
        if let t = c.targetTriple { a += ["-target", t] }
        if lang == .objc || lang == .objcxx { a.append("-fobjc-arc") }
        for i in c.includePaths { a += ["-I", i] }
        for f in c.frameworkPaths { a += ["-F", f] }
        for d in c.defines { a += ["-D\(d)"] }
        return a + ["-o", out]
    }

    public func start(_ action: FileAction, file: String, context: FileBuildContext) -> BuildOperation {
        guard let args = command(action, file: file, context: context) else {
            let message = "\(action.title) is not available for \(URL(fileURLWithPath: file).lastPathComponent)"
            let d = Diagnostic(severity: .error, message: message)
            return BuildOperation(events: AsyncStream { c in
                c.yield(.issue(d))
                c.yield(.finished(BuildResult(status: .failed, exitCode: -1, issues: [d])))
                c.finish()
            }, cancel: {})
        }
        try? FileManager.default.createDirectory(atPath: context.outputDirectory, withIntermediateDirectories: true)
        let name = URL(fileURLWithPath: file).lastPathComponent
        let verb = action == .compile ? "Compiling" : action == .analyze ? "Analyzing" : action == .preprocess ? "Preprocessing" : "Assembling"
        let op = ProcessBuild.start(args, currentDirectory: URL(fileURLWithPath: file).deletingLastPathComponent().path)
        let (stream, continuation) = AsyncStream<BuildEvent>.makeStream()
        continuation.yield(.activity("\(verb) \(name)"))
        let events = op.events
        Task {
            for await e in events { continuation.yield(e) }
            continuation.finish()
        }
        return BuildOperation(events: stream, cancel: op.cancel)
    }
}
