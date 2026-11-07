import Foundation

public struct BuildRequest: Equatable, Sendable {
    public enum Container: Equatable, Sendable {
        case project(String)
        case workspace(String)
        case package(String)

        public init(path: String) {
            switch URL(fileURLWithPath: path).pathExtension {
            case "xcworkspace": self = .workspace(path)
            case "xcodeproj": self = .project(path)
            default:
                self = .package(path.hasSuffix("Package.swift") ? URL(fileURLWithPath: path).deletingLastPathComponent().path : path)
            }
        }

        public var path: String {
            switch self { case .project(let p), .workspace(let p), .package(let p): p }
        }
    }

    public enum Action: String, Sendable, CaseIterable {
        case build, clean, test, analyze
        case buildForTesting = "build-for-testing"
        case testWithoutBuilding = "test-without-building"
    }

    public var container: Container
    public var scheme: String?
    public var configuration: String?
    public var destination: String?
    public var action: Action
    public var derivedDataPath: String?
    public var settings: [(String, String)]

    public init(container: Container, scheme: String? = nil, configuration: String? = nil, destination: String? = nil,
                action: Action = .build, derivedDataPath: String? = nil, settings: [(String, String)] = []) {
        self.container = container
        self.scheme = scheme
        self.configuration = configuration
        self.destination = destination
        self.action = action
        self.derivedDataPath = derivedDataPath
        self.settings = settings
    }

    public static func == (a: Self, b: Self) -> Bool {
        a.container == b.container && a.scheme == b.scheme && a.configuration == b.configuration
            && a.destination == b.destination && a.action == b.action && a.derivedDataPath == b.derivedDataPath
            && a.settings.elementsEqual(b.settings, by: ==)
    }
}

public enum BuildStatus: Equatable, Sendable {
    case succeeded, failed, cancelled
}

public struct BuildResult: Equatable, Sendable {
    public var status: BuildStatus
    public var exitCode: Int32
    public var issues: [Diagnostic]
    public var errorCount: Int { issues.filter { $0.severity == .error }.count }
    public var warningCount: Int { issues.filter { $0.severity == .warning }.count }
    public init(status: BuildStatus, exitCode: Int32, issues: [Diagnostic]) {
        self.status = status
        self.exitCode = exitCode
        self.issues = issues
    }
}

public enum BuildEvent: Equatable, Sendable {
    case output(String)
    case issue(Diagnostic)
    case activity(String)
    case planning
    case progress(done: Int, total: Int)
    case finished(BuildResult)
}

public protocol BuildEngine: Sendable {
    var name: String { get }
    func start(_ request: BuildRequest) -> BuildOperation
    func executablePath(for request: BuildRequest) -> String?
}

extension BuildEngine {
    public func executablePath(for request: BuildRequest) -> String? { nil }
}

public struct BuildOperation: Sendable {
    public let events: AsyncStream<BuildEvent>
    public let cancel: @Sendable () -> Void
    public init(events: AsyncStream<BuildEvent>, cancel: @escaping @Sendable () -> Void) {
        self.events = events
        self.cancel = cancel
    }

    public func run(_ handler: (BuildEvent) -> Void = { _ in }) async -> BuildResult {
        for await e in events {
            handler(e)
            if case .finished(let r) = e { return r }
        }
        return BuildResult(status: .cancelled, exitCode: -1, issues: [])
    }

    public func runBlocking(_ handler: @escaping @Sendable (BuildEvent) -> Void) -> BuildResult {
        final class Box: @unchecked Sendable { var result = BuildResult(status: .cancelled, exitCode: -1, issues: []) }
        let box = Box()
        let done = DispatchSemaphore(value: 0)
        let events = self.events
        Task.detached {
            for await e in events {
                handler(e)
                if case .finished(let r) = e { box.result = r }
            }
            done.signal()
        }
        done.wait()
        return box.result
    }
}

public struct LineBuffer: Sendable {
    private var buffer = Data()
    public init() {}

    public mutating func append(_ data: Data) -> [String] {
        buffer.append(data)
        var lines: [String] = []
        while let nl = buffer.firstIndex(of: 0x0A) {
            var line = buffer[buffer.startIndex..<nl]
            if line.last == 0x0D { line = line.dropLast() }
            lines.append(String(decoding: line, as: UTF8.self))
            buffer = Data(buffer[(nl + 1)...])
        }
        return lines
    }

    public mutating func flush() -> String? {
        defer { buffer = Data() }
        return buffer.isEmpty ? nil : String(decoding: buffer, as: UTF8.self)
    }
}
