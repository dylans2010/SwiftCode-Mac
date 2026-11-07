import AppKit
import YcodeIDECore

@MainActor
public struct ProjectNavigatorHooks {
    public var rowMenu: (() -> [NSMenuItem])?
    public var delete: (() -> Void)?
    public var rename: ((OutlineItem, String) -> Void)?
    public var cut: (() -> Void)?
    public var move: (([OutlineItem], OutlineItem, Int?) -> Void)?
    public var addFiles: (([URL], OutlineItem, Int?) -> Void)?
    public init() {}
}

final class NavigatorOutlineView: NSOutlineView {
    var onReturn: (() -> Bool)?
    var onDeleteKey: (() -> Bool)?
    var onReload: (() -> Void)?

    override func reloadData() {
        super.reloadData()
        onReload?()
    }

    override func keyDown(with event: NSEvent) {
        let mods = event.modifierFlags.intersection([.command, .option, .control, .shift])
        switch event.keyCode {
        case 36, 76 where mods.isEmpty:
            if onReturn?() == true { return }
        case 51, 117 where mods.isEmpty:
            if onDeleteKey?() == true { return }
        default: break
        }
        super.keyDown(with: event)
    }
}

@MainActor
final class NavigatorRenameDelegate: NSObject, NSTextFieldDelegate {
    var item: OutlineItem?
    var original = ""
    var cancelled = false
    var onCommit: ((OutlineItem, String) -> Void)?
    var onEnd: (() -> Void)?

    func control(_ control: NSControl, textView: NSTextView, doCommandBy sel: Selector) -> Bool {
        guard sel == #selector(NSResponder.cancelOperation(_:)) else { return false }
        cancelled = true
        (control as? NSTextField)?.stringValue = original
        control.window?.makeFirstResponder(nil)
        return true
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        guard let field = obj.object as? NSTextField, let item else { return }
        self.item = nil
        field.isEditable = false
        field.isSelectable = false
        field.delegate = nil
        let name = field.stringValue
        if cancelled || name == original || name.isEmpty {
            field.stringValue = item.title
        } else {
            onCommit?(item, name)
        }
        cancelled = false
        onEnd?()
    }
}

extension NavigatorAreaController {
    static let projectRowType = NSPasteboard.PasteboardType("org.swiftcode.navigator.project-row")

    func configureProjectOperations(_ index: Int) {
        projectOutline.allowsMultipleSelection = index == 0
        if index == 0 {
            projectOutline.registerForDraggedTypes([Self.projectRowType, .fileURL])
            projectOutline.setDraggingSourceOperationMask(.move, forLocal: true)
            projectOutline.setDraggingSourceOperationMask(.copy, forLocal: false)
        } else {
            projectOutline.unregisterDraggedTypes()
        }
        projectOutline.onReturn = { [weak self] in
            guard let self, self.selectedIndex == 0, self.projectOutline.selectedRowIndexes.count == 1, let item = self.selectedItem,
                  item.nodeKind != .container else { return false }
            self.beginRename(item)
            return true
        }
        projectOutline.onDeleteKey = { [weak self] in
            guard let self, self.selectedIndex == 0, !self.selectedProjectRows.isEmpty, let delete = self.projectOps.delete else { return false }
            delete()
            return true
        }
    }

    private var projectOutline: NavigatorOutlineView { navigatorOutline }

    public var selectedProjectRows: [OutlineItem] {
        guard isViewLoaded, selectedIndex == 0 else { return [] }
        return projectOutline.selectedRowIndexes.compactMap { projectOutline.item(atRow: $0) as? OutlineItem }
    }

    public func parentRow(of item: OutlineItem) -> OutlineItem? { projectOutline.parent(forItem: item) as? OutlineItem }

    public func projectPath(of item: OutlineItem) -> String? {
        var cur: OutlineItem? = item
        while let c = cur {
            if c.nodeKind == .container, let p = c.nodePath, p.hasSuffix(".xcodeproj") { return p }
            cur = parentRow(of: c)
        }
        return nil
    }

    @objc public func cut(_ sender: Any?) {
        guard selectedIndex == 0, !selectedProjectRows.isEmpty, let cut = projectOps.cut else { return NSSound.beep() }
        cut()
    }

    @objc public func delete(_ sender: Any?) {
        guard selectedIndex == 0, !selectedProjectRows.isEmpty, let delete = projectOps.delete else { return NSSound.beep() }
        delete()
    }

    @discardableResult
    public func selectProjectRows(_ match: (OutlineItem) -> Bool) -> [OutlineItem] {
        guard isViewLoaded, selectedIndex == 0 else { return [] }
        var found: [OutlineItem] = []
        func walk(_ items: [OutlineItem], _ ancestors: [OutlineItem]) {
            for i in items {
                if match(i) {
                    found.append(i)
                    for a in ancestors { projectOutline.expandItem(a) }
                }
                walk(i.children, ancestors + [i])
            }
        }
        walk(rows(0), [])
        let rows = IndexSet(found.map { projectOutline.row(forItem: $0) }.filter { $0 >= 0 })
        selectionFromOpen.value = true
        defer { selectionFromOpen.value = false }
        projectOutline.selectRowIndexes(rows, byExtendingSelection: false)
        if let first = rows.first { projectOutline.scrollRowToVisible(first) }
        return found
    }

    public func selectOpenFileRow(_ path: String) {
        guard isViewLoaded, selectedIndex == 0 else { return }
        let key = OpenRequestKey.path(URL(fileURLWithPath: path))
        func matches(_ i: OutlineItem) -> Bool { i.path.map { OpenRequestKey.path(URL(fileURLWithPath: $0)) == key } ?? false }
        if projectOutline.selectedRowIndexes.contains(where: { (projectOutline.item(atRow: $0) as? OutlineItem).map(matches) ?? false }) { return }
        var first = true
        selectProjectRows { i in
            guard first, matches(i) else { return false }
            first = false
            return true
        }
    }

    func rebuildProjectRowMenu(_ menu: NSMenu) {
        let clicked = projectOutline.clickedRow
        if clicked >= 0, !projectOutline.selectedRowIndexes.contains(clicked) {
            projectOutline.selectRowIndexes([clicked], byExtendingSelection: false)
        }
        for item in projectOps.rowMenu?() ?? [] { menu.addItem(item) }
    }

    func editableName(_ item: OutlineItem) -> String {
        item.nodeKind == .file ? (item.nodePath.map { ($0 as NSString).lastPathComponent } ?? item.title) : item.title
    }

    public func beginRename(_ item: OutlineItem) {
        let row = projectOutline.row(forItem: item)
        guard row >= 0, let cell = projectOutline.view(atColumn: 0, row: row, makeIfNecessary: true) as? NSTableCellView,
              let field = cell.textField else { return }
        let name = editableName(item)
        renameDelegate.item = item
        renameDelegate.original = name
        renameDelegate.cancelled = false
        renameDelegate.onCommit = { [weak self] item, newName in self?.projectOps.rename?(item, newName) }
        renameDelegate.onEnd = { [weak self] in
            guard let self else { return }
            self.view.window?.makeFirstResponder(self.projectOutline)
        }
        field.stringValue = name
        field.isEditable = true
        field.isSelectable = true
        field.delegate = renameDelegate
        view.window?.makeFirstResponder(field)
        let base = item.nodeKind == .file ? (name as NSString).deletingPathExtension : name
        field.currentEditor()?.selectedRange = NSRange(location: 0, length: (base.isEmpty ? name : base).utf16.count)
    }

    public var renamingRow: OutlineItem? { renameDelegate.item }

    public func commitRename(_ name: String) {
        guard let item = renameDelegate.item else { return }
        let row = projectOutline.row(forItem: item)
        let field = (row >= 0 ? projectOutline.view(atColumn: 0, row: row, makeIfNecessary: false) as? NSTableCellView : nil)?.textField
        field?.stringValue = name
        if let field {
            renameDelegate.controlTextDidEndEditing(Notification(name: NSControl.textDidEndEditingNotification, object: field))
        } else {
            renameDelegate.item = nil
            projectOps.rename?(item, name)
        }
    }

    public func outlineView(_ o: NSOutlineView, pasteboardWriterForItem item: Any) -> NSPasteboardWriting? {
        guard selectedIndex == 0, let item = item as? OutlineItem, item.nodeKind != .container, item.objectID != nil || item.nodePath != nil
        else { return nil }
        let p = NSPasteboardItem()
        p.setString(item.objectID ?? item.nodePath ?? "", forType: Self.projectRowType)
        return p
    }

    public func outlineView(_ o: NSOutlineView, draggingSession session: NSDraggingSession, willBeginAt screenPoint: NSPoint,
                            forItems draggedItems: [Any]) {
        draggedRows = draggedItems.compactMap { $0 as? OutlineItem }
    }

    public func outlineView(_ o: NSOutlineView, draggingSession session: NSDraggingSession, endedAt screenPoint: NSPoint,
                            operation: NSDragOperation) {
        draggedRows = []
    }

    func dropTarget(_ item: Any?, _ index: Int) -> (OutlineItem, Int?)? {
        guard selectedIndex == 0, !projectFilterActive else { return nil }
        guard let row = item as? OutlineItem else { return nil }
        if row.nodeKind == .file {
            guard let parent = parentRow(of: row) else { return nil }
            return (parent, (parent.children.firstIndex { $0 === row } ?? parent.children.count - 1) + 1)
        }
        if row.nodeKind == .container, row.nodePath?.hasSuffix(".xcworkspace") == true { return nil }
        return (row, index == NSOutlineViewDropOnItemIndex ? nil : index)
    }

    public func outlineView(_ o: NSOutlineView, validateDrop info: NSDraggingInfo, proposedItem item: Any?,
                            proposedChildIndex index: Int) -> NSDragOperation {
        guard let (dest, _) = dropTarget(item, index) else { return [] }
        if info.draggingPasteboard.types?.contains(Self.projectRowType) == true {
            var cur: OutlineItem? = dest
            while let c = cur {
                if draggedRows.contains(where: { $0 === c }) { return [] }
                cur = parentRow(of: c)
            }
            return .move
        }
        return info.draggingPasteboard.canReadObject(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) ? .copy : []
    }

    public func outlineView(_ o: NSOutlineView, acceptDrop info: NSDraggingInfo, item: Any?, childIndex index: Int) -> Bool {
        guard let (dest, i) = dropTarget(item, index) else { return false }
        if info.draggingPasteboard.types?.contains(Self.projectRowType) == true {
            guard !draggedRows.isEmpty, let move = projectOps.move else { return false }
            move(draggedRows, dest, i)
            return true
        }
        let urls = info.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        guard !urls.isEmpty, let add = projectOps.addFiles else { return false }
        add(urls, dest, i)
        return true
    }
}

@MainActor final class FlagBox { var value = false }
