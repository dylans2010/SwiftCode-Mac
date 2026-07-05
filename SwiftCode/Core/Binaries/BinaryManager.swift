import Foundation

struct BinaryExecutionResult {
    let command: String
    let stdout: String
    let stderr: String
    let exitCode: Int32

    var mergedOutput: String {
        [stdout, stderr]
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }

    var isSuccess: Bool { exitCode == 0 }
}

actor BinaryManager {
    static let shared = BinaryManager()

    enum Binary: String, CaseIterable {
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

    func validate(binary: Binary) async -> Bool {
        (try? await binaryURL(for: binary)) != nil
    }

    func runSwiftLint(at projectPath: String) async throws -> BinaryExecutionResult {
        try await run(.swiftLint, arguments: ["lint", "--quiet", projectPath])
    }

    func runSwiftFormat(at fileOrDirectoryPath: String) async throws -> BinaryExecutionResult {
        try await run(.swiftFormat, arguments: [fileOrDirectoryPath])
    }

    func runRipgrepSearch(
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

    func generateDependencyGraph(dotSource: String, outputPath: String) async throws -> BinaryExecutionResult {
        let dotURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("swiftcode-deps-\(UUID().uuidString).dot")
        try dotSource.write(to: dotURL, atomically: true, encoding: .utf8)
        return try await run(.graphviz, arguments: ["-Tsvg", dotURL.path, "-o", outputPath])
    }

    func runTreeSitterParser(filePath: String) async throws -> BinaryExecutionResult {
        try await run(.treeSitter, arguments: ["parse", filePath])
    }

    func runSourceKitLSP(arguments: [String]) async throws -> BinaryExecutionResult {
        try await run(.sourceKitLSP, arguments: arguments)
    }

    func runJQ(arguments: [String]) async throws -> BinaryExecutionResult {
        try await run(.jq, arguments: arguments)
    }

    func runGitCommand(arguments: [String], in directoryPath: String? = nil) async throws -> BinaryExecutionResult {
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
        // iOS/iPadOS do not support subprocess execution.
        // Return a clear error explaining that CLI tools are only available on macOS.
        throw NSError(domain: "BinaryManager", code: 501, userInfo: [
            NSLocalizedDescriptionKey: "Command line tools (including git, npm, and xcodebuild) are not supported on iOS/iPadOS. Please use the integrated API-based features instead."
        ])
    }
}
