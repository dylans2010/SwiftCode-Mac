import Foundation
import SwiftCodeBuild
import SwiftCodeIDECore

public struct NavigatorItem: Identifiable, Hashable, Sendable {
    public var id: String
    public var name: String
    public var kind: NavigatorNode.Kind
    public var path: String?
    public var children: [NavigatorItem]?

    public init(_ node: NavigatorNode) {
        id = node.expansionKey
        name = node.name
        kind = node.kind
        path = node.path
        children = node.kind == .file ? nil : node.children.map(NavigatorItem.init)
    }

    public static func == (a: Self, b: Self) -> Bool {
        a.id == b.id && a.name == b.name && a.path == b.path && a.children == b.children
    }
    public func hash(into h: inout Hasher) { h.combine(id) }

    public var isFile: Bool { kind == .file }

    public var symbolName: String { WorkspaceChrome.symbol(kind: kind, name: name, path: path) }

    public func idPath(to path: String) -> [String]? {
        if self.path == path { return [id] }
        for c in children ?? [] {
            if let rest = c.idPath(to: path) { return [id] + rest }
        }
        return nil
    }

    public func find(id: String) -> NavigatorItem? {
        if self.id == id { return self }
        for c in children ?? [] { if let f = c.find(id: id) { return f } }
        return nil
    }

    public var allFiles: [NavigatorItem] {
        isFile ? [self] : (children ?? []).flatMap(\.allFiles)
    }
}

public enum ShellSymbols {
    public static func file(named name: String) -> String { WorkspaceChrome.fileSymbol(name) }

    public static func severity(_ s: Diagnostic.Severity) -> String {
        switch s {
        case .error: "xmark.circle.fill"
        case .warning: "exclamationmark.triangle.fill"
        case .note, .remark: "info.circle"
        }
    }
}
