import Foundation
import Observation
import SwiftCodeIDECore

public struct CallHierarchyRow: Identifiable, Equatable, Sendable {
    public var id: String
    public var level: Int
    public var name: String
    public var detail: String
    public var path: String
    public var line: Int
    public var isExpandable: Bool
    public var isExpanded: Bool
}

@MainActor
@Observable
public final class CallHierarchyModel {
    public private(set) var tree: CallerTree?
    public var collapsed: Set<String> = []
    public var selection: String? {
        didSet { if selection != oldValue, let id = selection, let r = rows.first(where: { $0.id == id }) { onOpen?(r.path, r.line) } }
    }
    @ObservationIgnored var onOpen: ((String, Int) -> Void)?

    public init() {}

    func show(_ t: CallerTree?) {
        tree = t
        collapsed = []
        selection = nil
    }

    public func setExpanded(_ id: String, _ on: Bool) {
        if on { collapsed.remove(id) } else { collapsed.insert(id) }
    }

    public var rows: [CallHierarchyRow] { tree.map { Self.rows($0, collapsed: collapsed) } ?? [] }

    public static func rows(_ root: CallerTree, collapsed: Set<String>) -> [CallHierarchyRow] {
        var out: [CallHierarchyRow] = []
        func walk(_ t: CallerTree, _ id: String, _ level: Int) {
            let open = !collapsed.contains(id)
            var detail = "\((t.path as NSString).lastPathComponent):\(t.line)"
            if t.sites.count > 1 { detail += "  (\(t.sites.count) calls)" }
            out.append(CallHierarchyRow(id: id, level: level, name: t.name, detail: detail, path: t.path, line: t.line,
                                        isExpandable: !t.callers.isEmpty, isExpanded: open && !t.callers.isEmpty))
            guard open else { return }
            for (i, c) in t.callers.enumerated() { walk(c, "\(id)/\(i)", level + 1) }
        }
        walk(root, "callers", 0)
        return out
    }
}
