import Foundation

public struct NavigatorBarSpec: Equatable, Sendable {
    public enum LeftButton: Equatable, Sendable {
        case none
        case add(String?)
        case more
        case pullDown
    }

    public struct Toggle: Equatable, Sendable {
        public var title: String
        public var toolTip: String
        public var symbol: String
        public var menuTitle: String
        public var defaultOn: Bool
        public init(_ title: String, _ toolTip: String, _ symbol: String, menu: String, on: Bool = false) {
            self.title = title
            self.toolTip = toolTip
            self.symbol = symbol
            self.menuTitle = menu
            self.defaultOn = on
        }
    }

    public var left: LeftButton
    public var toggles: [Toggle]
    public var emptyState: [String]
}
public enum NavigatorBars {
    public static let selectorToolTips = [
        "Show the Project navigator", "Show the Source Control navigator", "Show the Bookmark navigator", "Show the Find navigator",
        "Show the Issue navigator", "Show the Test navigator", "Show the Debug Navigator", "Show the Breakpoints Navigator",
        "Show the Report navigator",
    ]

    public static let filterPlaceholder = "Filter"

    public static let specs: [NavigatorBarSpec] = {
        typealias T = NavigatorBarSpec.Toggle
        return [
            .init(left: .add(nil), toggles: [
                T("Recent files", "Show only recent files", "clock", menu: "Show Only Recent Files"),
                T("Files with source-control status", "Show only files with source-control status", "plusminus.circle",
                  menu: "Show Only Files with Source-Control Status"),
            ], emptyState: []),
            .init(left: .none, toggles: [], emptyState: ["No Repository"]),
            .init(left: .more, toggles: [
                T("Incomplete Items", "Show only incomplete items", "checklist", menu: "Show Only Incomplete Items"),
            ], emptyState: ["No Bookmarks", "Click the '…' button to add bookmarks"]),
            .init(left: .none, toggles: [], emptyState: []),
            .init(left: .none, toggles: [
                T("Show only latest issues", "Show only issues from open documents and recently built sources", "clock",
                  menu: "Show Only Latest Issues"),
                T("Only errors", "Show only errors", "xmark.octagon", menu: "Show Only Errors"),
            ], emptyState: ["No Issues"]),
            .init(left: .add("Add a new test target or class"), toggles: [
                T("Show Only Included Tests", "Show Only Included Tests", "checkmark.circle", menu: "Show Only Included Tests"),
                T("Recent Tests", "Show only recent tests and open documents", "clock", menu: "Show Only Recent Tests"),
            ], emptyState: ["No Tests", "Click the \u{2295} button to add test targets"]),
            .init(left: .none, toggles: [
                T("Show compressed stack frames", "Show only stack frames with debug symbols and between libraries",
                  "arrow.down.right.and.arrow.up.left", menu: "Show Compressed Stack Frames", on: true),
                T("Show only interesting content", "Show only crashed threads and threads with debug symbols", "star.circle",
                  menu: "Show Only Interesting Content"),
                T("Show only running blocks", "Show only running blocks when in Queues view", "play.circle",
                  menu: "Show Only Running Blocks", on: true),
            ], emptyState: ["No Debug Session"]),
            .init(left: .add("Create a breakpoint"), toggles: [
                T("Modified breakpoints", "Show only modified breakpoints", "slider.horizontal.3", menu: "Show Only Modified Breakpoints"),
                T("Enabled breakpoints", "Show only enabled breakpoints", "checkmark.circle", menu: "Show Only Enabled Breakpoints"),
            ], emptyState: ["No Breakpoints"]),
            .init(left: .pullDown, toggles: [
                T("Recent reports filter", "Show only recent reports", "clock", menu: "Show Only Recent Reports"),
            ], emptyState: ["No Logs"]),
        ]
    }()

    public static let reportScopeToolTips = ["Show Local Reports", "Show Cloud Reports"]
    public static let testModes = ["Group by Test Hierarchy", "Group by Tags"]
    public static let testPlanPopUpWidth: CGFloat = 194
    public static let untaggedTests = "Untagged Tests"
}
public enum TestTags {
    public static func names(inAttribute attribute: String) -> [String] {
        guard let r = attribute.range(of: ".tags(") else { return [] }
        var depth = 1
        var inside = ""
        for c in attribute[r.upperBound...] {
            if c == "(" { depth += 1 } else if c == ")" { depth -= 1; if depth == 0 { break } }
            inside.append(c)
        }
        return inside.split(separator: ",").compactMap { part in
            let t = part.trimmingCharacters(in: .whitespacesAndNewlines)
            let name = t.split(separator: ".").last.map(String.init) ?? t
            return name.isEmpty || !name.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" }) ? nil : name
        }
    }

    static func attributes(above line: Int, in lines: [Substring]) -> String {
        guard line >= 1, line <= lines.count else { return "" }
        var out: [Substring] = [lines[line - 1]]
        var i = line - 2
        while i >= 0 {
            let t = lines[i].trimmingCharacters(in: .whitespaces)
            guard t.hasPrefix("@") || t.hasPrefix(".") || t.hasPrefix(")") || t.hasSuffix(",") || t.hasSuffix("(") else { break }
            out.insert(lines[i], at: 0)
            i -= 1
        }
        return out.joined(separator: "\n")
    }

    public static func tags(of test: DiscoveredTest, text: String) -> [String] {
        guard test.kind == .swiftTesting else { return [] }
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        var out: [String] = []
        for l in [test.suiteLine, test.line].compactMap({ $0 }) {
            for n in names(inAttribute: attributes(above: l, in: lines)) where !out.contains(n) { out.append(n) }
        }
        return out
    }
}
