import Foundation
import YcodeDebug
import YcodeLanguage

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

    public var underlyingClient: LSPClient? { client }

    public init() {}

    public func start(server: ServerInfo, workspaceRoot: URL) async throws {
        await shutdown()
        let executable = try Self.resolveExecutable(server.command)
        let transport = ProcessTransport(executable: executable, arguments: server.arguments)
        let client = try LSPClient(transport: transport)
        try await client.initialize(root: workspaceRoot)
        self.client = client
        self.server = server
    }

    public func shutdown() async {
        guard let client else { return }
        await client.shutdown()
        client.close()
        self.client = nil
        self.server = nil
    }

    public func restart(server: ServerInfo, workspaceRoot: URL) async throws {
        try await start(server: server, workspaceRoot: workspaceRoot)
    }

    public var isRunning: Bool { client != nil }

    public func didOpen(uri: String, languageId: String, version: Int, text: String) throws {
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

    public func completion(uri: String, line: Int, character: Int) async throws -> [String] {
        guard let url = URL(string: uri) else { throw ClientError.invalidURI(uri) }
        guard let client else { throw ClientError.notStarted }
        return try await client.completion(url, at: Position(line: line, character: character)).map(\.label)
    }

    public func hover(uri: String, line: Int, character: Int) async throws -> String? {
        guard let url = URL(string: uri) else { throw ClientError.invalidURI(uri) }
        guard let client else { throw ClientError.notStarted }
        return try await client.hover(url, at: Position(line: line, character: character))
    }

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
