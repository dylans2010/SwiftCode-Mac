import Foundation
import YcodeAssistant
import YcodeBuild
import YcodeIDECore
import YcodeIDEShell

@MainActor
public protocol SwiftCodeMCPHostDelegate: AnyObject {
    func mcpHostText(ofOpenFile path: String) -> String?
    func mcpHostActiveFilePath() -> String?
    func mcpHostSaveAll()
    func mcpHostDidWrite(_ path: String)
}

public extension SwiftCodeMCPHostDelegate {
    func mcpHostActiveFilePath() -> String? { nil }
}

@MainActor
public final class SwiftCodeMCPHost {
    public let server: MCPServer
    public internal(set) var session: WorkspaceSession?
    public weak var delegate: SwiftCodeMCPHostDelegate?
    public var engine: BuildEngine
    public var remoteSimulator: RemoteSimulatorSettings?
    public let sharesIDESession: Bool
    var currentDirectory: URL?
    var runs: [String: HostRun] = [:]
    var runOrder: [String] = []
    var simulatorLog: [String] = []
    var artboards: [ArtboardRecord] = []
    var activeArtboardID: UUID?
    var activityProgress: MCPProgress?
    var activityCount = 0
    var observedSession: ObjectIdentifier?

    public init(server: MCPServer = MCPServer(), engine: BuildEngine = SwiftCodeMCPHost.defaultEngine()) {
        self.server = server
        self.engine = engine
        sharesIDESession = false
        installTools()
        AssistToolRegistry.shared.registerMCPTools()
        ExtV2AssistBridge.installRegistrationHandler()
    }

    public init(server: MCPServer = MCPServer(), session: WorkspaceSession) {
        self.server = server
        self.engine = session.engine
        self.session = session
        sharesIDESession = true
        installTools()
        AssistToolRegistry.shared.registerMCPTools()
        ExtV2AssistBridge.installRegistrationHandler()
        observe(session)
    }

    public nonisolated static func defaultEngine() -> BuildEngine {
        FallbackEngine(primary: PackageBuildEngine(), fallback: ShellBuildSetup.engine()) { r in
            if case .package = r.container { return true }
            return false
        }
    }

    @discardableResult
    public func open(_ url: URL) throws -> WorkspaceSession {
        guard !sharesIDESession else { throw MCPToolError("this server belongs to an open SwiftCode workspace window; open other workspaces in SwiftCode") }
        var model = try WorkspaceModel(url: url)
        model.destinationGroups = Self.destinationGroups(for: model, remote: remoteSimulator)
        let s = WorkspaceSession(model: model)
        s.engine = engine
        s.stopOnFirstError = false
        s.destination = model.destinations.first
        session = s
        currentDirectory = nil
        observe(s)
        return s
    }

    static func destinationGroups(for model: WorkspaceModel, remote: RemoteSimulatorSettings?) -> [DestinationGroup] {
        var groups = ShellBuildSetup.destinationGroups(for: model)
        if let remote, remote.isConfigured {
            groups.append(DestinationGroup(title: "SwiftCode Simulator", destinations: RemoteSimulator.destinations(remote)))
        }
        return groups
    }

    public static func discoverWorkspace(in dir: URL) -> URL? {
        let fm = FileManager.default
        if fm.fileExists(atPath: dir.appendingPathComponent("Package.swift").path) { return dir }
        let items = (try? fm.contentsOfDirectory(atPath: dir.path)) ?? []
        let workspaces = items.filter { $0.hasSuffix(".xcworkspace") }
        if workspaces.count == 1 { return dir.appendingPathComponent(workspaces[0]) }
        let projects = items.filter { $0.hasSuffix(".xcodeproj") }
        if projects.count == 1 { return dir.appendingPathComponent(projects[0]) }
        return nil
    }

    func session(for call: MCPToolCall) throws -> WorkspaceSession {
        if let w = call.string("workspace") {
            let url = URL(fileURLWithPath: (w as NSString).expandingTildeInPath).standardizedFileURL
            if let s = session, s.model.url.standardizedFileURL.path == url.path
                || (url.lastPathComponent == "Package.swift" && s.model.url.path == url.deletingLastPathComponent().path) { return s }
            return try open(url)
        }
        guard let s = session else {
            throw MCPToolError("no workspace is open: call workspace_open with the path of a package folder, an .xcodeproj or an .xcworkspace")
        }
        return s
    }

    public static func folder(of model: WorkspaceModel) -> URL {
        (model.kind == .package ? model.url : model.url.deletingLastPathComponent()).standardizedFileURL
    }

    func resolve(_ path: String, in s: WorkspaceSession) throws -> URL {
        let root = Self.folder(of: s.model)
        let expanded = (path as NSString).expandingTildeInPath
        let url = (expanded.hasPrefix("/") ? URL(fileURLWithPath: expanded) : root.appendingPathComponent(expanded)).standardizedFileURL
        guard Self.isInside(url, root) else { throw MCPToolError("\(path) is outside the workspace folder \(root.path)") }
        return url
    }

    nonisolated static func isInside(_ url: URL, _ root: URL) -> Bool {
        let r = realPath(root), p = realPath(url)
        return p == r || p.hasPrefix(r.hasSuffix("/") ? r : r + "/")
    }

    nonisolated static func realPath(_ url: URL) -> String {
        var existing = url.standardizedFileURL
        var rest: [String] = []
        let fm = FileManager.default
        while !fm.fileExists(atPath: existing.path), existing.path != "/" {
            rest.insert(existing.lastPathComponent, at: 0)
            existing.deleteLastPathComponent()
        }
        var resolved = existing.resolvingSymlinksInPath()
        for c in rest { resolved.appendPathComponent(c) }
        return resolved.standardizedFileURL.path
    }

    func relative(_ path: String, in s: WorkspaceSession) -> String {
        Self.relativePath(path, root: Self.folder(of: s.model).path)
    }

    nonisolated static func relativePath(_ path: String, root: String) -> String {
        let roots = [root, realPath(URL(fileURLWithPath: root))]
        for p in [path, realPath(URL(fileURLWithPath: path))] {
            for r in roots {
                let prefix = r.hasSuffix("/") ? r : r + "/"
                if p.hasPrefix(prefix) { return String(p.dropFirst(prefix.count)) }
            }
        }
        return path
    }

    func text(of url: URL) -> String? {
        if let t = delegate?.mcpHostText(ofOpenFile: url.path) { return t }
        return try? String(contentsOf: url, encoding: .utf8)
    }

    func observe(_ s: WorkspaceSession) {
        let id = ObjectIdentifier(s)
        guard observedSession != id else { return }
        observedSession = id
        s.observe { [weak self, weak s] change in
            guard let self, let s, change == .activity, self.session === s, let p = self.activityProgress else { return }
            let text: String
            switch s.activity {
            case .building(let t): text = t
            case .running(let t): text = t
            case .finished(let t): text = t
            default: return
            }
            self.activityCount += 1
            if let (done, total) = Self.counts(in: text) {
                p.report(Double(done), total: Double(max(done, total)), message: text)
            } else {
                p.report(Double(self.activityCount), message: text)
            }
        }
    }

    nonisolated static func counts(in text: String) -> (Int, Int)? {
        guard let r = text.range(of: #"(\d+)/(\d+)\s*$"#, options: .regularExpression) else { return nil }
        let parts = text[r].trimmingCharacters(in: .whitespaces).split(separator: "/")
        guard parts.count == 2, let a = Int(parts[0]), let b = Int(parts[1]) else { return nil }
        return (a, b)
    }

    nonisolated static func issueJSON(_ d: Diagnostic, relativeTo root: String) -> AnyJSON {
        var o: [String: AnyJSON] = ["severity": .string(d.severity.rawValue), "message": .string(d.message)]
        if let l = d.location {
            o["path"] = .string(relativePath(l.file, root: root))
            o["line"] = .int(l.line)
            if l.column > 0 { o["column"] = .int(l.column) }
        }
        if !d.notes.isEmpty { o["notes"] = .strings(d.notes.map(\.description)) }
        if !d.fixIts.isEmpty {
            o["fixIts"] = .array(d.fixIts.map { ["line": .int($0.start.line), "column": .int($0.start.column), "replacement": .string($0.replacement)] })
        }
        return .object(o)
    }

    nonisolated static func destinationJSON(_ d: Destination) -> AnyJSON {
        ["name": .string(d.name), "id": .optional(d.identifier), "platform": .string(d.platform), "kind": .string(d.kind.rawValue),
         "specifier": .string(d.specifier), "osVersion": .optional(d.osVersion)]
    }

    func destination(named name: String?, in s: WorkspaceSession) throws -> Destination? {
        guard let name else { return nil }
        let all = s.model.destinations
        if let d = all.first(where: { $0.identifier == name || $0.name == name || $0.specifier == name }) { return d }
        if let d = all.first(where: { $0.name.lowercased().hasPrefix(name.lowercased()) }) { return d }
        throw MCPToolError("no destination \"\(name)\"; the workspace offers: \(all.map(\.name).joined(separator: ", "))")
    }

    func applyScheme(_ name: String?, destination: String?, to s: WorkspaceSession) throws {
        if let name {
            guard s.model.schemeNames.contains(name) else {
                throw MCPToolError("no scheme \"\(name)\"; the workspace has: \(s.model.schemeNames.joined(separator: ", "))")
            }
            s.scheme = name
        }
        if let d = try self.destination(named: destination, in: s) { s.destination = d }
    }
}

final class HostRun: @unchecked Sendable {
    let id: String
    let executable: String
    let process: Process
    private let lock = NSLock()
    private var lines: [String] = []
    private var partial = ""
    private(set) var exitStatus: Int32?
    let started = Date()

    init(id: String, executable: String, process: Process) {
        self.id = id
        self.executable = executable
        self.process = process
    }

    func append(_ data: Data) {
        lock.withLock {
            partial += String(decoding: data, as: UTF8.self)
            while let nl = partial.firstIndex(of: "\n") {
                lines.append(String(partial[..<nl]))
                partial = String(partial[partial.index(after: nl)...])
            }
            if lines.count > 5000 { lines.removeFirst(lines.count - 5000) }
        }
    }

    func finish(_ status: Int32) {
        lock.withLock {
            if !partial.isEmpty { lines.append(partial); partial = "" }
            exitStatus = status
        }
    }

    func output(tail: Int) -> [String] { lock.withLock { Array(lines.suffix(tail)) } }
    var status: Int32? { lock.withLock { exitStatus } }
}
