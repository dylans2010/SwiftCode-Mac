import AppKit
import YcodeIDECore

extension NavigatorAreaController {
    static let modeControlInset = CGFloat(RepositoriesViewStyle.modeControlInset)

    func expandedSourceControlKeys() -> Set<String>? {
        guard isViewLoaded, selectedIndex == 1, outline.numberOfRows > 0, Self.isRepositoriesTree(shownRoots) else { return nil }
        var keys = Set<String>()
        for r in 0..<outline.numberOfRows {
            guard let item = outline.item(atRow: r) as? OutlineItem, outline.isItemExpanded(item) else { continue }
            keys.insert(Self.expansionKey(item))
        }
        return keys
    }

    static func isRepositoriesTree(_ roots: [OutlineItem]) -> Bool {
        roots.contains { $0.children.contains { $0.scmKey == "group:Branches" } }
    }

    static func expansionKey(_ item: OutlineItem) -> String { item.scmKey ?? "title:" + item.title }

    func expandSourceControlRows(keeping kept: Set<String>?) {
        let roots = shownRoots
        guard Self.isRepositoriesTree(roots) else { outline.expandItem(nil, expandChildren: true); return }
        func walk(_ item: OutlineItem) {
            let open = kept.map { $0.contains(Self.expansionKey(item)) } ?? SourceControlNavigatorModel.expandsInitially(item)
            guard open else { return }
            outline.expandItem(item)
            item.children.forEach(walk)
        }
        roots.forEach(walk)
    }
}
