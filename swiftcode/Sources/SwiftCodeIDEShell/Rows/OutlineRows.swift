import Foundation
import SwiftCodeBuild
import SwiftCodeIDECore

public struct OutlineRow: Identifiable, Equatable, Sendable {
    public enum Tint: Equatable, Sendable { case accent, secondary, error, warning, success }

    public var id: String
    public var level: Int
    public var title: String
    public var detail: String?
    public var symbol: String
    public var tint: Tint
    public var isBold = false
    public var isExpandable = false
    public var isExpanded = false
    public var match: (before: String, match: String, after: String)?
    public var lineLimit = 1
    public var isDimmed = false
    public var opens = false
    public var isEdited = false
    public var badge: String?
    public var trailing: String?
    public var detailIsSecondary = false
    public var trailingSymbol: String?
    public var trailingTint: Tint = .secondary

    public static func == (a: Self, b: Self) -> Bool {
        a.id == b.id && a.level == b.level && a.title == b.title && a.detail == b.detail && a.symbol == b.symbol && a.tint == b.tint
            && a.isBold == b.isBold && a.isExpandable == b.isExpandable && a.isExpanded == b.isExpanded
            && a.match?.before == b.match?.before && a.match?.match == b.match?.match && a.match?.after == b.match?.after
            && a.lineLimit == b.lineLimit && a.isDimmed == b.isDimmed && a.opens == b.opens && a.isEdited == b.isEdited
            && a.badge == b.badge && a.trailing == b.trailing && a.detailIsSecondary == b.detailIsSecondary
            && a.trailingSymbol == b.trailingSymbol && a.trailingTint == b.trailingTint
    }
}

public enum OutlineRows {
    public static func project(_ root: NavigatorItem, expanded: Set<String>, hideExtensions: Bool, edited: Set<String> = [],
                               badges: [String: String] = [:]) -> [OutlineRow] {
        var out: [OutlineRow] = []
        func walk(_ item: NavigatorItem, _ level: Int) {
            let open = expanded.contains(item.id)
            let title = item.isFile ? WorkspaceChrome.jumpBarFileTitle(item.name, hideExtension: hideExtensions) : item.name
            out.append(OutlineRow(id: item.id, level: level, title: title, detail: nil,
                                  symbol: WorkspaceChrome.symbol(kind: item.kind, name: item.name, path: item.path), tint: .accent,
                                  isExpandable: item.children != nil, isExpanded: open, opens: item.isFile,
                                  isEdited: item.path.map(edited.contains) ?? false,
                                  badge: item.isFile ? item.path.flatMap { badges[$0] } : nil))
            if open { for c in item.children ?? [] { walk(c, level + 1) } }
        }
        walk(root, 0)
        return out
    }

    public static func find(_ files: [FindFileRow], collapsed: Set<String>) -> [OutlineRow] {
        var out: [OutlineRow] = []
        for f in files {
            let open = !collapsed.contains(f.id)
            out.append(OutlineRow(id: f.id, level: 0, title: f.title, symbol: "doc.text", tint: .accent, isBold: true, isExpandable: true,
                                  isExpanded: open))
            guard open else { continue }
            for m in f.matches {
                out.append(OutlineRow(id: m.id, level: 1, title: m.before + m.match + m.after, symbol: "text.magnifyingglass",
                                      tint: .secondary, match: (m.before, m.match, m.after), lineLimit: 2, opens: true))
            }
        }
        return out
    }

    public static func issues(_ groups: [IssueGroupRow], collapsed: Set<String>) -> [OutlineRow] {
        var out: [OutlineRow] = []
        func issue(_ r: IssueRow, _ level: Int) -> OutlineRow {
            OutlineRow(id: r.id, level: level, title: r.message, detail: nil, symbol: r.symbolName,
                       tint: r.severity == .error ? .error : (r.severity == .warning ? .warning : .secondary),
                       lineLimit: r.file == nil ? 8 : 2, isDimmed: r.isStale, opens: true)
        }
        for g in groups {
            let open = !collapsed.contains(g.id)
            out.append(OutlineRow(id: g.id, level: 0, title: g.title, detail: g.countText, symbol: "app.dashed", tint: .accent,
                                  isBold: true, isExpandable: true, isExpanded: open))
            guard open else { continue }
            for f in g.files {
                let fo = !collapsed.contains(f.id)
                out.append(OutlineRow(id: f.id, level: 1, title: f.title, symbol: WorkspaceChrome.fileSymbol(String(f.id.split(separator: "|").last ?? "")), tint: .accent,
                                      isBold: true, isExpandable: true, isExpanded: fo))
                if fo { out += f.issues.map { issue($0, 2) } }
            }
            out += g.issues.map { issue($0, 1) }
        }
        return out
    }
}
