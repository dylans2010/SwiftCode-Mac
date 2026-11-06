import Foundation
import YcodeDebug
import YcodeLanguage

/// The Ext v2 language client — Legacy's
/// `Backend/Extensions v2/LanguageServices/ExtV2LanguageClient.swift`,
/// ported as a thin adapter over Ycode's own `LSPClient`
/// (`YcodeLanguage`), not a second JSON-RPC implementation.
///
/// Legacy owned its whole stack: stdio pipes, Content-Length
/// framing, request/response matching, and the `initialize` /
/// `didOpen` / `completion` / `hover` calls. `LSPClient` already
/// does all of that over `DAPTransport` / `ProcessTransport`
/// (`YcodeDebug`), so this adapter only translates Legacy's API
/// shape onto it: `ServerInfo`, `start` / `shutdown` / `restart`,
/// document sync, and completion-as-labels / hover-as-text.
///
/// Deviations, recorded:
/// * `didOpen` accepts Legacy's `languageId` for API compatibility,
///   but `LSPClient` derives the language from the file extension,
///   so the argument is ignored.
/// * Bare command names resolve through `PATH` in-process (Legacy
///   shelled out to `/usr/bin/which`); a missing executable fails
///   honestly with `.executableNotFound` before any process starts.
/// * Diagnostics are not drained here: `LSPClient.notifications`
///   carries `publishDiagnostics`, and the IDE's `LanguageService`
///   already consumes that stream. This client exposes the same
///   stream through `notifications` for callers that want it.
/// * `completion` returns labels only, as Legacy did — the full
///   `CompletionItem`s stay available through `client` for callers
///   that need detail or insert text.

public actor ExtV2LanguageClient {
    public struct ServerInfo: Sendable, Equatable {
        public var command: String
        public var arguments: [String]
        public var language: String

        public init(command: String, arguments: [String] = [], language: String) {
            self.command = command
            self.arguments = arguments
            self.language = language
        }
    }

    public enum ClientError: Error, Equatable, Sendable {
        case executableNotFound(String)
        case notStarted
        case invalidURI(String)
    }

    private var client: LSPClient?
    private var server: ServerInfo?

    /// The underlying client, for callers that need more than
    /// labels and hover text (full completion items, definitions,
    /// diagnostics via `notifications`).
    public var underlyingClient: LSPClient? { client }

    public init() {}

    /// Starts the server process and runs `initialize` against the
    /// workspace root. Throws `.executableNotFound` when the
    /// command cannot be resolved, and rethrows the client's
    /// startup / initialize errors (a server that exits
    /// immediately fails here, not on the first completion).
    public func start(server: ServerInfo, workspaceRoot: URL) async throws {
        await shutdown()
        let executable = try Self.resolveExecutable(server.command)
        let transport = ProcessTransport(executable: executable, arguments: server.arguments)
        let client = try LSPClient(transport: transport)
        try await client.initialize(root: workspaceRoot)
        self.client = client
        self.server = server
    }

    /// Shuts the server down (`shutdown` request, then closes the
    /// transport) and forgets it. Safe to call when nothing is
    /// running.
    public func shutdown() async {
        guard let client else { return }
        await client.shutdown()
        client.close()
        self.client = nil
        self.server = nil
    }

    /// Stops the current server (if any) and starts the given one.
    public func restart(server: ServerInfo, workspaceRoot: URL) async throws {
        try await start(server: server, workspaceRoot: workspaceRoot)
    }

    public var isRunning: Bool { client != nil }

    // MARK: - Document sync

    public func didOpen(uri: String, languageId: String, version: Int, text: String) throws {
        // `languageId` is accepted for API compatibility; LSPClient
        // derives it from the file extension.
        _ = languageId
        guard let url = URL(string: uri) else { throw ClientError.invalidURI(uri) }
        guard let client else { throw ClientError.notStarted }
        client.didOpen(url, text: text, version: version)
    }

    public func didChange(uri: String, version: Int, text: String) throws {
        guard let url = URL(string: uri) else { throw ClientError.invalidURI(uri) }
        guard let client else { throw ClientError.notStarted }
        client.didChange(url, text: text, version: version)
    }

    public func didClose(uri: String) throws {
        guard let url = URL(string: uri) else { throw ClientError.invalidURI(uri) }
        guard let client else { throw ClientError.notStarted }
        client.didClose(url)
    }

    // MARK: - Language features

    /// Completion labels at a position, as Legacy returned them.
    public func completion(uri: String, line: Int, character: Int) async throws -> [String] {
        guard let url = URL(string: uri) else { throw ClientError.invalidURI(uri) }
        guard let client else { throw ClientError.notStarted }
        return try await client.completion(url, at: Position(line: line, character: character)).map(\.label)
    }

    /// Hover text at a position, or nil when there is none.
    public func hover(uri: String, line: Int, character: Int) async throws -> String? {
        guard let url = URL(string: uri) else { throw ClientError.invalidURI(uri) }
        guard let client else { throw ClientError.notStarted }
        return try await client.hover(url, at: Position(line: line, character: character))
    }

    // MARK: - Executable resolution

    /// Resolves a command to an executable path: a path containing
    /// a slash is used as-is (and must be executable); a bare name
    /// is looked up in `PATH`, in order. Throws
    /// `.executableNotFound` either way.
    public static func resolveExecutable(_ command: String) throws -> String {
        let fileManager = FileManager.default
        if command.contains("/") {
            guard fileManager.isExecutableFile(atPath: command) else {
                throw ClientError.executableNotFound(command)
            }
            return command
        }
        let path = ProcessInfo.processInfo.environment["PATH"] ?? "/usr/bin:/bin:/usr/local/bin"
        for directory in path.split(separator: ":").map(String.init) {
            let candidate = (directory as NSString).appendingPathComponent(command)
            if fileManager.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }
        throw ClientError.executableNotFound(command)
    }
}
