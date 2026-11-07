import Foundation
import YcodeProject
import YcodeWorkspace
import YcodeBuild
import YcodeDebug

public struct BreakpointStore: Equatable, Sendable {
    public struct Breakpoint: Equatable, Hashable, Sendable {
        public var file: String
        public var line: Int
        public var isEnabled: Bool
        public var column: Int?
        public var condition = ""
        public var ignoreCount = 0
        public var actions: [BreakpointAction] = []
        public var autoContinue = false

        public var isCustomized: Bool { !condition.isEmpty || ignoreCount > 0 || !actions.isEmpty || autoContinue }

        public var dap: SourceBreakpoint {
            SourceBreakpoint(line: line, column: column, condition: condition.isEmpty ? nil : condition,
                             hitCondition: ignoreCount > 0 ? String(ignoreCount) : nil, logMessage: adapterLogMessage)
        }

        public var adapterLogMessage: String? {
            guard autoContinue, actions.count == 1, case .log(let m) = actions[0], !BreakpointMessage.needsIDE(m) else { return nil }
            return BreakpointMessage.dapLogMessage(m)
        }

        public var runsActionsInIDE: Bool { adapterLogMessage == nil && (!actions.isEmpty || autoContinue) }
    }

    public enum BreakpointAction: Equatable, Hashable, Sendable {
        case log(String)
        case debuggerCommand(String)
        case sound(String)
    }

    public struct Symbolic: Equatable, Hashable, Sendable {
        public var name: String
        public var condition = ""
        public var isEnabled = true
        public init(name: String, condition: String = "", isEnabled: Bool = true) {
            self.name = name
            self.condition = condition
            self.isEnabled = isEnabled
        }
    }

    public var exceptionFilters: [String] = []
    public var symbolic: [Symbolic] = []

    public mutating func edit(file: String, line: Int, _ change: (inout Breakpoint) -> Void) {
        guard let i = index(file: file, line: line) else { return }
        change(&all[i])
    }

    public var effectiveBreakpoints: [String: [SourceBreakpoint]] {
        var out: [String: [SourceBreakpoint]] = [:]
        for b in all { out[b.file, default: []] += (isActive && b.isEnabled) ? [b.dap] : [] }
        return out
    }

    public var effectiveFunctionBreakpoints: [FunctionBreakpoint] {
        guard isActive else { return [] }
        return symbolic.compactMap { s in
            let name = s.name.trimmingCharacters(in: .whitespaces), condition = s.condition.trimmingCharacters(in: .whitespaces)
            return s.isEnabled && !name.isEmpty ? FunctionBreakpoint(name: name, condition: condition.isEmpty ? nil : condition) : nil
        }
    }

    public private(set) var all: [Breakpoint] = []
    public var isActive = true

    public init() {}

    public var isEmpty: Bool { all.isEmpty && symbolic.isEmpty && exceptionFilters.isEmpty }

    public func breakpoint(file: String, line: Int) -> Breakpoint? {
        index(file: file, line: line).map { all[$0] }
    }

    private func index(file: String, line: Int) -> Int? {
        all.firstIndex { $0.file == file && $0.line == line && $0.column == nil }
            ?? all.firstIndex { $0.file == file && $0.line == line }
    }

    public func breakpoints(file: String, line: Int) -> [Breakpoint] {
        all.filter { $0.file == file && $0.line == line }
    }

    private mutating func sortAll() {
        all.sort { ($0.file, $0.line, $0.column ?? 0) < ($1.file, $1.line, $1.column ?? 0) }
    }

    public mutating func click(file: String, line: Int) {
        if let i = index(file: file, line: line) {
            let on = !all[i].isEnabled
            for j in all.indices where all[j].file == file && all[j].line == line { all[j].isEnabled = on }
        } else {
            all.append(Breakpoint(file: file, line: line, isEnabled: true))
            sortAll()
        }
    }

    public mutating func toggleExistence(file: String, line: Int) {
        if breakpoint(file: file, line: line) != nil { remove(file: file, line: line) } else { click(file: file, line: line) }
    }

    public mutating func remove(file: String, line: Int) {
        all.removeAll { $0.file == file && $0.line == line }
    }

    public mutating func move(file: String, from: Int, to: Int) {
        guard from != to, let i = index(file: file, line: from) else { return }
        let enabled = all[i].isEnabled
        all.remove(at: i)
        remove(file: file, line: to)
        all.append(Breakpoint(file: file, line: to, isEnabled: enabled))
        sortAll()
    }

    public func lineIsEnabled(file: String, line: Int) -> Bool? {
        let list = breakpoints(file: file, line: line)
        return list.isEmpty ? nil : list.allSatisfy(\.isEnabled)
    }

    public mutating func toggleEnabled(file: String, line: Int) {
        guard let on = lineIsEnabled(file: file, line: line) else { return }
        for j in all.indices where all[j].file == file && all[j].line == line { all[j].isEnabled = !on }
    }

    public mutating func addColumn(file: String, line: Int, column: Int) {
        guard !all.contains(where: { $0.file == file && $0.line == line && $0.column == column }) else { return }
        all.append(Breakpoint(file: file, line: line, isEnabled: true, column: column))
        sortAll()
    }

    public mutating func removeColumns(file: String, line: Int) {
        all.removeAll { $0.file == file && $0.line == line && $0.column != nil }
    }

    public func hasColumnBreakpoints(file: String, line: Int) -> Bool {
        all.contains { $0.file == file && $0.line == line && $0.column != nil }
    }

    public mutating func removeAll() {
        all = []
        symbolic = []
        exceptionFilters = []
    }

    public mutating func insert(_ b: Breakpoint) {
        all.removeAll { $0.file == b.file && $0.line == b.line && $0.column == b.column }
        all.append(b)
        sortAll()
    }

    public var effectiveLines: [String: [Int]] {
        var out: [String: [Int]] = [:]
        for b in all { out[b.file, default: []] += (isActive && b.isEnabled) ? [b.line] : [] }
        return out
    }
}

public struct WorkspaceModel: Sendable {
    public enum ContainerKind: Sendable, Equatable { case project, workspace, package }

    public var url: URL
    public var kind: ContainerKind
    public var root: NavigatorNode
    public var schemeNames: [String]
    public var destinationGroups: [DestinationGroup] = DestinationCatalog.groups(devices: [], simulators: [])
    public var destinations: [Destination] { destinationGroups.flatMap(\.destinations) }
    public var projects: [String: PBXProj] = [:]

    public var displayName: String {
        kind == .package ? url.lastPathComponent : url.deletingPathExtension().lastPathComponent
    }

    public init(url input: URL) throws {
        var url = input.standardizedFileURL
        if url.lastPathComponent == "Package.swift" { url.deleteLastPathComponent() }
        self.url = url
        switch url.pathExtension {
        case "xcodeproj":
            kind = .project
            let proj = try PBXProj(contentsOf: url)
            projects[url.path] = proj
            root = NavigatorTree.project(proj, xcodeprojURL: url)
            schemeNames = Self.schemes(in: [url], projects: [url.path: proj])
        case "xcworkspace":
            kind = .workspace
            let ws = try Workspace(contentsOf: url.path)
            var rows: [NavigatorNode] = []
            var loaded: [String: PBXProj] = [:]
            for p in ws.projectPaths {
                let pu = URL(fileURLWithPath: p)
                guard let proj = try? PBXProj(contentsOf: pu) else { continue }
                loaded[p] = proj
                rows.append(NavigatorTree.project(proj, xcodeprojURL: pu))
            }
            projects = loaded
            root = NavigatorNode(name: url.deletingPathExtension().lastPathComponent, kind: .container, path: url.path, children: rows)
            schemeNames = Self.schemes(in: [url] + ws.projectPaths.map { URL(fileURLWithPath: $0) }, projects: loaded)
        default:
            guard FileManager.default.fileExists(atPath: url.appendingPathComponent("Package.swift").path) else {
                throw CocoaError(.fileReadUnsupportedScheme, userInfo: [
                    NSFilePathErrorKey: url.path,
                    NSLocalizedDescriptionKey: "“\(url.lastPathComponent)” is not a project, workspace or package.",
                    NSLocalizedRecoverySuggestionErrorKey: "Open an .xcodeproj or .xcworkspace, or a folder with a Package.swift in it.",
                ])
            }
            kind = .package
            root = NavigatorTree.package(at: url)
            schemeNames = [url.lastPathComponent]
        }
    }

    static func schemes(in containers: [URL], projects: [String: PBXProj]) -> [String] {
        var names: [String] = []
        for c in containers {
            let found = Scheme.discover(in: c).map(\.name)
            if found.isEmpty, let proj = projects[c.path] {
                names += proj.targets.compactMap { $0.string("name") }
            } else {
                names += found
            }
        }
        var seen = Set<String>()
        return names.filter { seen.insert($0).inserted }
    }

    public func buildRequest(scheme: String?, destination: Destination?, action: BuildRequest.Action) -> BuildRequest {
        let container: BuildRequest.Container = switch kind {
        case .project: .project(url.path)
        case .workspace: .workspace(url.path)
        case .package: .package(url.path)
        }
        return BuildRequest(container: container, scheme: scheme, destination: destination?.specifier, action: action,
                            settings: diagnostics(scheme: scheme, action: action).buildSettings)
    }

    public func diagnostics(scheme: String?, action: BuildRequest.Action) -> SchemeDiagnostics {
        guard kind != .package, let name = scheme, let element = SchemeDiagnostics.schemeAction(for: action),
              let s = loadSchemes().first(where: { $0.name == name }) else { return SchemeDiagnostics() }
        return s.diagnostics(for: element)
    }

    public func saveProjects() throws {
        for (path, proj) in projects {
            let name = URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
            let file = URL(fileURLWithPath: path).appendingPathComponent("project.pbxproj")
            let text = proj.serialized(projectName: name)
            if (try? String(contentsOf: file, encoding: .utf8)) != text {
                try text.write(to: file, atomically: true, encoding: .utf8)
            }
        }
    }
}
