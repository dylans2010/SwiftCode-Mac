import Foundation

public enum EditorTabPolicy {
    public enum OpenTarget: Equatable, Sendable {
        case current
        case select(Int)
        case newTab
    }

    public static func openTarget(path: String, currentPath: String?, currentPinned: Bool,
                                  openInTabs: Bool, tabPaths: [[String]]) -> OpenTarget {
        guard let currentPath, currentPath != path, currentPinned || openInTabs else { return .current }
        if let i = tabPaths.firstIndex(where: { $0.contains(path) }) { return .select(i) }
        return .newTab
    }

    public static func isBarVisible(shown: Bool, tabCount: Int) -> Bool { shown || tabCount > 1 }

    public static func title(for url: URL?) -> String {
        url?.deletingPathExtension().lastPathComponent ?? "Untitled"
    }

    public static func toolTip(for url: URL, groupPath: String?) -> String {
        url.lastPathComponent + (groupPath.map { $0.isEmpty ? "" : "\n" + $0 } ?? "")
    }

    public static func showsCloseButton(tab: Int, hovered: Int?) -> Bool { tab == hovered }

    public static func selectionAfterClosing(_ index: Int, selected: Int, count: Int) -> Int {
        let remaining = count - 1
        guard remaining > 0 else { return 0 }
        let s = index < selected ? selected - 1 : selected
        return min(s, remaining - 1)
    }
}

public enum EditorCloseCommand: CaseIterable, Sendable {
    case tab, document, editorPane, window, workspace

    public var shortcut: String {
        switch self {
        case .tab: "⌘W"
        case .document: "⌃⌘W"
        case .editorPane: "⌃⇧⌘W"
        case .window: "⇧⌘W"
        case .workspace: "⌃⌥⌘W"
        }
    }

    public func title(fileName: String?, isPackage: Bool) -> String {
        switch self {
        case .tab: "Close Tab"
        case .document: fileName.map { "Close \u{201C}\($0)\u{201D}" } ?? "Close Document"
        case .editorPane: "Close Editor Pane"
        case .window: "Close Window"
        case .workspace: isPackage ? "Close Package" : "Close Project"
        }
    }

    public func isEnabled(paneCount: Int) -> Bool { self != .editorPane || paneCount > 1 }
}
