import Foundation
import YcodeWorkspace

typealias XNode = SwiftCodeWorkspace.XMLNode

public struct BreakpointList: Equatable, Sendable {
    public static let fileBreakpointID = "Xcode.Breakpoint.FileBreakpoint"
    public static let noColumn = "9223372036854775807"
    public static let functionLandmark = "7"

    public struct Entry: Equatable, Sendable {
        public var uuid: String
        public var breakpoint: BreakpointStore.Breakpoint
    }

    public private(set) var bucket: SwiftCodeWorkspace.XMLNode

    public init() {
        bucket = XNode("Bucket", attributes: [("uuid", Self.newUUID()), ("type", "1"), ("version", "2.0")],
                         children: [XNode("Breakpoints")])
    }

    public init(text: String) throws {
        let root = try XcodeXML.parse(text)
        guard root.name == "Bucket" else { throw FormatError(message: "the root element is \(root.name), not Bucket") }
        bucket = root
    }

    public struct FormatError: Error, Equatable {
        public var message: String
    }

    public static func newUUID() -> String { UUID().uuidString.uppercased() }

    public var text: String { XcodeXML.write(bucket) }

    public static func fileURL(container: URL, isPackage: Bool, user: String = NSUserName()) -> URL {
        userDataFolder(container: container, isPackage: isPackage, user: user)
            .appendingPathComponent("xcdebugger/Breakpoints_v2.xcbkptlist")
    }

    public static func extrasURL(container: URL, isPackage: Bool, user: String = NSUserName()) -> URL {
        userDataFolder(container: container, isPackage: isPackage, user: user).appendingPathComponent("swiftcode-breakpoints.json")
    }

    static func userDataFolder(container: URL, isPackage: Bool, user: String) -> URL {
        (isPackage ? container.appendingPathComponent(".swiftpm/xcode") : container)
            .appendingPathComponent("xcuserdata/\(user).xcuserdatad")
    }

    public static func baseFolder(container: URL, isPackage: Bool) -> URL {
        isPackage ? container : container.deletingLastPathComponent()
    }

    private var proxies: [XNode] { bucket.child("Breakpoints")?.children ?? [] }

    public func entries(base: URL) -> [Entry] {
        proxies.compactMap { Self.entry($0, base: base) }
    }

    static func entry(_ proxy: XNode, base: URL) -> Entry? {
        guard proxy.name == "BreakpointProxy", proxy["BreakpointExtensionID"] == fileBreakpointID,
              let c = proxy.child("BreakpointContent"), let uuid = c["uuid"], let path = c["filePath"],
              let line = c["startingLineNumber"].flatMap(Int.init), line > 0 else { return nil }
        var b = BreakpointStore.Breakpoint(file: absolute(path, base: base), line: line, isEnabled: c["shouldBeEnabled"] != "No")
        if let col = c["startingColumnNumber"], col != noColumn, let n = Int(col), n > 0 { b.column = n }
        b.ignoreCount = c["ignoreCount"].flatMap(Int.init) ?? 0
        b.autoContinue = c["continueAfterRunningActions"] == "Yes"
        return Entry(uuid: uuid, breakpoint: b)
    }

    static func absolute(_ path: String, base: URL) -> String {
        path.hasPrefix("/") ? URL(fileURLWithPath: path).standardizedFileURL.path
            : base.appendingPathComponent(path).standardizedFileURL.path
    }

    static func relative(_ path: String, base: URL) -> String {
        let p = URL(fileURLWithPath: path).standardizedFileURL.pathComponents
        let b = base.standardizedFileURL.pathComponents
        var n = 0
        while n < p.count, n < b.count, p[n] == b[n] { n += 1 }
        if n <= 1 { return URL(fileURLWithPath: path).standardizedFileURL.path }
        return (Array(repeating: "..", count: b.count - n) + p[n...]).joined(separator: "/")
    }

    public mutating func update(_ breakpoints: [BreakpointStore.Breakpoint], base: URL, uuids: inout [String: String],
                                landmark: (String, Int) -> String?) {
        var wanted: [String: BreakpointStore.Breakpoint] = [:]
        var order: [String] = []
        for b in breakpoints {
            let key = Self.key(b)
            let uuid = uuids[key] ?? Self.newUUID()
            uuids[key] = uuid
            if wanted[uuid] == nil { order.append(uuid) }
            wanted[uuid] = b
        }
        var out: [XNode] = []
        var written = Set<String>()
        for proxy in proxies {
            guard Self.entry(proxy, base: base) != nil, var content = proxy.child("BreakpointContent"), let uuid = content["uuid"] else {
                out.append(proxy)
                continue
            }
            guard let b = wanted[uuid], !written.contains(uuid) else { continue }
            Self.fill(&content, b, base: base, landmark: landmark(b.file, b.line), keepLandmark: true)
            var p = proxy
            if let i = p.children.firstIndex(where: { $0.name == "BreakpointContent" }) { p.children[i] = content }
            out.append(p)
            written.insert(uuid)
        }
        for uuid in order where !written.contains(uuid) {
            let b = wanted[uuid]!
            var content = XNode("BreakpointContent", attributes: [("uuid", uuid)])
            Self.fill(&content, b, base: base, landmark: landmark(b.file, b.line), keepLandmark: false)
            out.append(XNode("BreakpointProxy", attributes: [("BreakpointExtensionID", Self.fileBreakpointID)], children: [content]))
        }
        if let i = bucket.children.firstIndex(where: { $0.name == "Breakpoints" }) {
            bucket.children[i].children = out
        } else {
            bucket.children.append(XNode("Breakpoints", children: out))
        }
        let live = Set(order)
        uuids = uuids.filter { live.contains($0.value) }
    }

    static func fill(_ c: inout XNode, _ b: BreakpointStore.Breakpoint, base: URL, landmark: String?, keepLandmark: Bool) {
        let column = b.column.map(String.init) ?? noColumn
        c["shouldBeEnabled"] = b.isEnabled ? "Yes" : "No"
        c["ignoreCount"] = String(b.ignoreCount)
        c["continueAfterRunningActions"] = b.autoContinue ? "Yes" : "No"
        c["filePath"] = relative(b.file, base: base)
        c["startingColumnNumber"] = column
        c["endingColumnNumber"] = column
        c["startingLineNumber"] = String(b.line)
        c["endingLineNumber"] = String(b.line)
        if let landmark {
            c["landmarkName"] = landmark
            c["landmarkType"] = functionLandmark
        } else if !keepLandmark {
            c["landmarkName"] = nil
            c["landmarkType"] = nil
        }
    }

    static func key(_ b: BreakpointStore.Breakpoint) -> String { "\(b.file):\(b.line):\(b.column ?? 0)" }
}

public struct BreakpointExtras: Codable, Equatable, Sendable {
    public struct Symbolic: Codable, Equatable, Sendable {
        public var name: String
        public var condition: String?
        public var enabled: Bool?
    }
    public struct LineOptions: Codable, Equatable, Sendable {
        public var condition: String?
        public var actions: [[String: String]]?
    }
    public var symbolic: [Symbolic]?
    public var exceptionFilters: [String]?
    public var lineOptions: [String: LineOptions]?
    public var active: Bool?

    public init() {}

    public var isEmpty: Bool { self == BreakpointExtras() }
}

@MainActor
public final class BreakpointPersistence {
    public let fileURL: URL
    public let extrasURL: URL
    public let base: URL
    private var list: BreakpointList
    private var uuids: [String: String] = [:]
    private var saved: BreakpointStore
    var landmark: (String, Int) -> String? = { file, line in
        SourceSymbolLocator.symbol(file: file, line: line)?.name
    }

    public init(container: URL, isPackage: Bool, user: String = NSUserName()) {
        fileURL = BreakpointList.fileURL(container: container, isPackage: isPackage, user: user)
        extrasURL = BreakpointList.extrasURL(container: container, isPackage: isPackage, user: user)
        base = BreakpointList.baseFolder(container: container, isPackage: isPackage)
        list = (try? String(contentsOf: fileURL, encoding: .utf8)).flatMap { try? BreakpointList(text: $0) } ?? BreakpointList()
        saved = BreakpointStore()
        saved = load()
    }

    public func load() -> BreakpointStore {
        var store = BreakpointStore()
        let extras = (try? Data(contentsOf: extrasURL)).flatMap { try? JSONDecoder().decode(BreakpointExtras.self, from: $0) } ?? BreakpointExtras()
        uuids = [:]
        for e in list.entries(base: base) {
            var b = e.breakpoint
            if let o = extras.lineOptions?[e.uuid] {
                b.condition = o.condition ?? ""
                b.actions = (o.actions ?? []).compactMap { a in
                    if let t = a["log"] { return .log(t) }
                    if let t = a["command"] { return .debuggerCommand(t) }
                    if let t = a["sound"] { return .sound(t) }
                    return nil
                }
            }
            store.insert(b)
            uuids[BreakpointList.key(b)] = e.uuid
        }
        store.symbolic = (extras.symbolic ?? []).map { .init(name: $0.name, condition: $0.condition ?? "", isEnabled: $0.enabled ?? true) }
        store.exceptionFilters = extras.exceptionFilters ?? []
        store.isActive = extras.active ?? true
        return store
    }

    @discardableResult
    public func save(_ store: BreakpointStore) -> Bool {
        guard store != saved else { return false }
        let fm = FileManager.default
        list.update(store.all, base: base, uuids: &uuids, landmark: landmark)
        let text = list.text
        if (try? String(contentsOf: fileURL, encoding: .utf8)) != text, !store.all.isEmpty || fm.fileExists(atPath: fileURL.path) {
            try? fm.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? text.write(to: fileURL, atomically: true, encoding: .utf8)
        }
        var extras = BreakpointExtras()
        if !store.symbolic.isEmpty {
            extras.symbolic = store.symbolic.map { .init(name: $0.name, condition: $0.condition.isEmpty ? nil : $0.condition, enabled: $0.isEnabled ? nil : false) }
        }
        if !store.exceptionFilters.isEmpty { extras.exceptionFilters = store.exceptionFilters }
        var options: [String: BreakpointExtras.LineOptions] = [:]
        for b in store.all where !b.condition.isEmpty || !b.actions.isEmpty {
            guard let uuid = uuids[BreakpointList.key(b)] else { continue }
            options[uuid] = .init(condition: b.condition.isEmpty ? nil : b.condition, actions: b.actions.isEmpty ? nil : b.actions.map {
                switch $0 {
                case .log(let t): ["log": t]
                case .debuggerCommand(let t): ["command": t]
                case .sound(let t): ["sound": t]
                }
            })
        }
        if !options.isEmpty { extras.lineOptions = options }
        if !store.isActive { extras.active = false }
        if !extras.isEmpty || fm.fileExists(atPath: extrasURL.path) {
            try? fm.createDirectory(at: extrasURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let e = JSONEncoder()
            e.outputFormatting = [.prettyPrinted, .sortedKeys]
            try? e.encode(extras).write(to: extrasURL, options: .atomic)
        }
        saved = store
        return true
    }
}
