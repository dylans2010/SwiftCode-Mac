import Foundation
import YcodeDebug

public struct WorkspaceSymbol: Equatable, Sendable {
    public var name: String
    public var kind: Int
    public var containerName: String?
    public var location: Location
    public init(name: String, kind: Int, containerName: String? = nil, location: Location) {
        self.name = name
        self.kind = kind
        self.containerName = containerName
        self.location = location
    }
    init?(_ j: JSON) {
        guard let name = j["name"]?.string, let loc = j["location"].flatMap(Location.init) else { return nil }
        self.name = name
        kind = j["kind"]?.int ?? 0
        containerName = j["containerName"]?.string
        location = loc
    }

    public var isType: Bool { [5, 10, 11, 23, 26].contains(kind) }
    public var isCallable: Bool { [6, 9, 12, 25].contains(kind) }
}

public struct TypeHierarchyItem: Equatable, Sendable {
    public var name: String
    public var kind: Int
    public var detail: String?
    public var url: URL
    public var selection: Position
    public var raw: JSON
    public init(name: String, kind: Int, detail: String? = nil, url: URL, selection: Position, raw: JSON = .null) {
        self.name = name
        self.kind = kind
        self.detail = detail
        self.url = url
        self.selection = selection
        self.raw = raw
    }
    init?(_ j: JSON) {
        guard let name = j["name"]?.string, let uri = j["uri"]?.string, let url = URL(string: uri) else { return nil }
        self.name = name
        kind = j["kind"]?.int ?? 0
        detail = j["detail"]?.string
        self.url = url
        selection = Position((j["selectionRange"] ?? j["range"])?["start"])
        raw = j
    }
}

extension Location {
    public init(url: URL, start: Position, end: Position) {
        self.url = url
        self.start = start
        self.end = end
    }
}

extension CallHierarchyItem {
    public init(name: String, detail: String? = nil, url: URL, selection: Position, raw: JSON = .null) {
        self.name = name
        self.detail = detail
        self.url = url
        self.selection = selection
        self.raw = raw
    }
}

extension LSPClient {
    static var findTextDocumentCapabilities: [String: JSON] { ["typeHierarchy": [:]] }
    static var findWorkspaceCapabilities: [String: JSON] { ["symbol": ["symbolKind": ["valueSet": .array((1...26).map { .number(Double($0)) })]]] }

    public func provides(_ name: String) -> Bool {
        switch capabilities["\(name)Provider"] {
        case nil, .null?, .bool(false)?: false
        default: true
        }
    }

    public func workspaceSymbols(_ query: String) async throws -> [WorkspaceSymbol] {
        let r = try await request("workspace/symbol", ["query": .string(query)])
        return (r.array ?? []).compactMap(WorkspaceSymbol.init)
    }

    public func prepareTypeHierarchy(_ url: URL, at p: Position) async throws -> [TypeHierarchyItem] {
        (try await request("textDocument/prepareTypeHierarchy", Self.position(url, p))).array?.compactMap(TypeHierarchyItem.init) ?? []
    }

    public func supertypes(_ item: TypeHierarchyItem) async throws -> [TypeHierarchyItem] {
        (try await request("typeHierarchy/supertypes", ["item": item.raw])).array?.compactMap(TypeHierarchyItem.init) ?? []
    }

    public func subtypes(_ item: TypeHierarchyItem) async throws -> [TypeHierarchyItem] {
        (try await request("typeHierarchy/subtypes", ["item": item.raw])).array?.compactMap(TypeHierarchyItem.init) ?? []
    }
}
