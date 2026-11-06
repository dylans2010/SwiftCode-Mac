// Adapted from SwiftCode-Legacy SwiftCode/Core/Binaries/BinaryManager.swift (Dylan's own code;
// direct port authorised under MIT). See bulk/core-dispositions.tsv.
// Adaptation note: Legacy-internal types made public; the iOS-only #else throw is dropped — Foundation.Process runs on macOS and Linux alike.
import Foundation

public struct BinaryExecutionResult {
    public let command: String
    public let stdout: String
    public let stderr: String
    public let exitCode: Int32

    public var mergedOutput: String {
        [stdout, stderr]
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }

    public var isSuccess: Bool { exitCode == 0 }
}

public actor BinaryManager {
    public static let shared = BinaryManager()

    public enum Binary: String, CaseIterable {
        case swiftLint = "swiftlint"
        case swiftFormat = "swiftformat"
        case sourceKitLSP = "sourcekit-lsp"
        case ripgrep = "rg"
        case treeSitter = "tree-sitter"
        case graphviz = "dot"
        case jq = "jq"
        case git = "git"
    }

    private var binaryCache: [Binary: URL] = [:]

    public func validate(binary: Binary) async -> Bool {
        (try? await binaryURL(for: binary)) != nil
    }

    public func runSwiftLint(at projectPath: String) async throws -> BinaryExecutionResult {
        try await run(.swiftLint, arguments: ["lint", "--quiet", projectPath])
    }

    public func runSwiftFormat(at fileOrDirectoryPath: String) async throws -> BinaryExecutionResult {
        try await run(.swiftFormat, arguments: [fileOrDirectoryPath])
    }

    public func runRipgrepSearch(
        query: String,
        in directoryPath: String,
        caseSensitive: Bool,
        useRegex: Bool,
        fileExtension: String?
    ) async throws -> BinaryExecutionResult {
        var args = ["--line-number", "--with-filename", "--color", "never"]
        if !caseSensitive { args.append("--ignore-case") }
        if !useRegex { args.append("--fixed-strings") }
        if let fileExtension, !fileExtension.isEmpty {
            args.append(contentsOf: ["-g", "*.\(fileExtension)"])
        }
        args.append(contentsOf: [query, directoryPath])
        return try await run(.ripgrep, arguments: args)
    }

    public func generateDependencyGraph(dotSource: String, outputPath: String) async throws -> BinaryExecutionResult {
        let dotURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("swiftcode-deps-\(UUID().uuidString).dot")
        try dotSource.write(to: dotURL, atomically: true, encoding: .utf8)
        return try await run(.graphviz, arguments: ["-Tsvg", dotURL.path, "-o", outputPath])
    }

    /// Outcome of the Graphviz availability check / install attempt.
    public enum GraphvizAvailability: Sendable {
        /// `dot` was already on PATH (or bundled).
        case available
        /// `dot` was missing and Homebrew just installed it successfully.
        case installedNow
        /// `dot` is missing and Homebrew itself is not installed, so we cannot
        /// install it automatically. Carries install guidance for the UI.
        case brewMissing
        /// `dot` is missing and the `brew install graphviz` attempt failed.
        case installFailed(String)
    }

    /// Ensures Graphviz (`dot`) is usable, installing it via Homebrew when it
    /// is missing. Never shells out through /bin/sh — brew is launched with a
    /// fixed executable path and an argv array.
    public func ensureGraphvizAvailable() async -> GraphvizAvailability {
        if await validate(binary: .graphviz) { return .available }

        // Drop any stale negative cache entry before re-probing.
        binaryCache[.graphviz] = nil

        let brewCandidates = ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"]
        guard let brewPath = brewCandidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else {
            return .brewMissing
        }

        do {
            let result = try await runExecutable(brewPath, arguments: ["install", "graphviz"], workingDirectory: nil)
            binaryCache[.graphviz] = nil
            if result.isSuccess, await validate(binary: .graphviz) {
                return .installedNow
            }
            let detail = result.mergedOutput.trimmingCharacters(in: .whitespacesAndNewlines)
            return .installFailed(detail.isEmpty ? "brew install graphviz exited with code \(result.exitCode)." : detail)
        } catch {
            return .installFailed(error.localizedDescription)
        }
    }

    public func runTreeSitterParser(filePath: String) async throws -> BinaryExecutionResult {
        try await run(.treeSitter, arguments: ["parse", filePath])
    }

    public func runSourceKitLSP(arguments: [String]) async throws -> BinaryExecutionResult {
        try await run(.sourceKitLSP, arguments: arguments)
    }

    public func runJQ(arguments: [String]) async throws -> BinaryExecutionResult {
        try await run(.jq, arguments: arguments)
    }

    public func runGitCommand(arguments: [String], in directoryPath: String? = nil) async throws -> BinaryExecutionResult {
        try await run(.git, arguments: arguments, workingDirectory: directoryPath)
    }

    private func binaryURL(for binary: Binary) async throws -> URL {
        if let cached = binaryCache[binary] { return cached }

        let bundledPath = Bundle.main.bundleURL
            .appendingPathComponent("Binaries", isDirectory: true)
            .appendingPathComponent(binary.rawValue)
        if FileManager.default.isExecutableFile(atPath: bundledPath.path) {
            binaryCache[binary] = bundledPath
            return bundledPath
        }

        let result = try await runExecutable("/usr/bin/env", arguments: ["which", binary.rawValue], workingDirectory: nil)
        let resolved = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        guard result.isSuccess, !resolved.isEmpty else {
            throw NSError(domain: "BinaryManager", code: 404, userInfo: [
                NSLocalizedDescriptionKey: "\(binary.rawValue) binary could not be located."
            ])
        }

        let url = URL(fileURLWithPath: resolved)
        binaryCache[binary] = url
        return url
    }

    private func run(
        _ binary: Binary,
        arguments: [String],
        workingDirectory: String? = nil
    ) async throws -> BinaryExecutionResult {
        let executableURL = try await binaryURL(for: binary)
        return try await runExecutable(executableURL.path, arguments: arguments, workingDirectory: workingDirectory)
    }

    private func runExecutable(
        _ executablePath: String,
        arguments: [String],
        workingDirectory: String?
    ) async throws -> BinaryExecutionResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments
        if let workingDirectory {
            process.currentDirectoryURL = URL(fileURLWithPath: workingDirectory)
        }

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        try process.run()

        var stdoutData = Data()
        var stderrData = Data()

        if let outData = try? stdoutPipe.fileHandleForReading.readToEnd() {
            stdoutData = outData
        }
        if let errData = try? stderrPipe.fileHandleForReading.readToEnd() {
            stderrData = errData
        }

        process.waitUntilExit()

        return BinaryExecutionResult(
            command: ([executablePath] + arguments).joined(separator: " "),
            stdout: String(data: stdoutData, encoding: .utf8) ?? "",
            stderr: String(data: stderrData, encoding: .utf8) ?? "",
            exitCode: process.terminationStatus
        )
    }
}
