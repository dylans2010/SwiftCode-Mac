import Foundation
import SwiftCodeDebug

public struct TextEdit: Equatable, Sendable {
    public var start: Position
    public var end: Position
    public var newText: String
    public init(start: Position, end: Position, newText: String) {
        self.start = start
        self.end = end
        self.newText = newText
    }
    init(_ j: JSON) {
        start = Position(j["range"]?["start"])
        end = Position(j["range"]?["end"])
        newText = j["newText"]?.string ?? ""
    }
}

public struct DocumentHighlight: Equatable, Sendable {
    public var start: Position
    public var end: Position
    public var kind: Int?
    public init(start: Position, end: Position, kind: Int? = nil) {
        self.start = start
        self.end = end
        self.kind = kind
    }
    init?(_ j: JSON) {
        guard let range = j["range"], range["start"] != nil else { return nil }
        start = Position(range["start"])
        end = Position(range["end"])
        kind = j["kind"]?.int
    }
}

public struct WorkspaceEdit: Equatable, Sendable {
    public var changes: [URL: [TextEdit]]
    public init(changes: [URL: [TextEdit]]) { self.changes = changes }
    public init(_ j: JSON?) {
        var out: [URL: [TextEdit]] = [:]
        for (uri, edits) in j?["changes"]?.object ?? [:] {
            if let u = URL(string: uri) { out[u, default: []] += (edits.array ?? []).map(TextEdit.init) }
        }
        for dc in j?["documentChanges"]?.array ?? [] {
            if let uri = dc["textDocument"]?["uri"]?.string, let u = URL(string: uri) {
                out[u, default: []] += (dc["edits"]?.array ?? []).map(TextEdit.init)
            }
        }
        changes = out
    }
    public var isEmpty: Bool { changes.values.allSatisfy(\.isEmpty) }
    public var files: [URL] { changes.keys.sorted { $0.path < $1.path } }
}

public struct CodeAction: Equatable, Sendable {
    public var title: String
    public var kind: String?
    public var edit: WorkspaceEdit?
    public var command: JSON?
    public init(title: String, kind: String? = nil, edit: WorkspaceEdit? = nil, command: JSON? = nil) {
        self.title = title
        self.kind = kind
        self.edit = edit
        self.command = command
    }
    init?(_ j: JSON) {
        guard let title = j["title"]?.string else { return nil }
        self.title = title
        if j["command"]?.string != nil && j["edit"] == nil && j["kind"] == nil {
            kind = nil
            edit = nil
            command = j
            return
        }
        kind = j["kind"]?.string
        edit = j["edit"].map { WorkspaceEdit($0) }
        command = j["command"]
    }
}

public struct CallHierarchyItem: Equatable, Sendable {
    public var name: String
    public var detail: String?
    public var url: URL
    public var selection: Position
    public var raw: JSON
    init?(_ j: JSON) {
        guard let name = j["name"]?.string, let uri = j["uri"]?.string, let url = URL(string: uri) else { return nil }
        self.name = name
        detail = j["detail"]?.string
        self.url = url
        selection = Position((j["selectionRange"] ?? j["range"])?["start"])
        raw = j
    }
}

extension LSPClient {
    static var refactoringCapabilities: [String: JSON] {
        ["rename": ["prepareSupport": true],
         "references": [:],
         "callHierarchy": [:],
         "declaration": [:],
         "codeAction": ["codeActionLiteralSupport": ["codeActionKind": ["valueSet": [
             "quickfix", "refactor", "refactor.extract", "refactor.inline", "refactor.rewrite", "source", "source.organizeImports"]]]]]
    }

    static func range(_ start: Position, _ end: Position) -> JSON {
        ["start": ["line": .number(Double(start.line)), "character": .number(Double(start.character))],
         "end": ["line": .number(Double(end.line)), "character": .number(Double(end.character))]]
    }

    public func prepareRename(_ url: URL, at p: Position) async throws -> (start: Position, end: Position, placeholder: String?)? {
        let r = try await request("textDocument/prepareRename", Self.position(url, p))
        guard r != .null else { return nil }
        let range = r["range"] ?? r
        guard range["start"] != nil else { return nil }
        return (Position(range["start"]), Position(range["end"]), r["placeholder"]?.string)
    }

    public func rename(_ url: URL, at p: Position, to newName: String) async throws -> WorkspaceEdit {
        guard case .object(var params) = Self.position(url, p) else { return WorkspaceEdit(changes: [:]) }
        params["newName"] = .string(newName)
        return WorkspaceEdit(try await request("textDocument/rename", .object(params)))
    }

    public func references(_ url: URL, at p: Position) async throws -> [Location] {
        guard case .object(var params) = Self.position(url, p) else { return [] }
        params["context"] = ["includeDeclaration": true]
        return (try await request("textDocument/references", .object(params))).array?.compactMap(Location.init) ?? []
    }

    public func documentHighlights(_ url: URL, at p: Position) async throws -> [DocumentHighlight] {
        let r = try await request("textDocument/documentHighlight", Self.position(url, p))
        return (r.array ?? []).compactMap(DocumentHighlight.init)
    }

    public func declaration(_ url: URL, at p: Position) async throws -> [Location] {
        let r = try await request("textDocument/declaration", Self.position(url, p))
        return (r.array ?? (r == .null ? [] : [r])).compactMap(Location.init)
    }

    public func prepareCallHierarchy(_ url: URL, at p: Position) async throws -> [CallHierarchyItem] {
        (try await request("textDocument/prepareCallHierarchy", Self.position(url, p))).array?.compactMap(CallHierarchyItem.init) ?? []
    }

    public func incomingCalls(_ item: CallHierarchyItem) async throws -> [(caller: CallHierarchyItem, ranges: [Position])] {
        let r = try await request("callHierarchy/incomingCalls", ["item": item.raw])
        return (r.array ?? []).compactMap { c in
            guard let from = c["from"].flatMap(CallHierarchyItem.init) else { return nil }
            return (from, (c["fromRanges"]?.array ?? []).map { Position($0["start"]) })
        }
    }

    public func codeActions(_ url: URL, start: Position, end: Position, diagnostics: [JSON] = []) async throws -> [CodeAction] {
        let r = try await request("textDocument/codeAction", [
            "textDocument": ["uri": .string(url.absoluteString)],
            "range": Self.range(start, end),
            "context": ["diagnostics": .array(diagnostics)],
        ])
        return (r.array ?? []).compactMap(CodeAction.init)
    }

    public func executeCommand(_ command: JSON) async throws {
        var params: [String: JSON] = ["command": command["command"] ?? .string("")]
        if let a = command["arguments"] { params["arguments"] = a }
        _ = try await request("workspace/executeCommand", .object(params))
    }
}
