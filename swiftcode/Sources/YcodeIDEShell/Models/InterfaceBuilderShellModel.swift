#if canImport(CoreGraphics)
import CoreGraphics
#endif
import Foundation
import Observation
import YcodeIDECore

@MainActor
@Observable
public final class InterfaceBuilderShellModel {
    public let path: String
    @ObservationIgnored public let session: IBEditorSession
    public private(set) var revision = 0

    public var zoom: CGFloat {
        get { zoomValue }
        set { zoomValue = IBCanvasLayout.clampZoom(newValue) }
    }
    private var zoomValue: CGFloat = 1
    public var isOutlineShown = true
    public var inspectorTab: IBInspectorTab? = .attributes
    public var canvasIsDark = false
    public var isLandscape = false
    public var device: String
    public var isLibraryShown = false
    public var libraryFilter = "" {
        didSet { if libraryFilter != oldValue { librarySelection = libraryObjects.first } }
    }
    public var libraryTab: IBLibraryTab = .objects
    public var libraryIsIconView = false
    public var libraryShowsDetails = true
    public var librarySelection: IBDocument.NewObject? = .label
    public var isAddConstraintsShown = false
    public private(set) var collapsed: Set<String> = []
    @ObservationIgnored private var drag: IBCanvasDrag?
    public private(set) var dragPreview: CGRect?

    public init(path: String) throws {
        self.path = path
        session = try IBEditorSession(url: URL(fileURLWithPath: path))
        device = session.document.isFlippedRuntime ? Self.iOSDevices[0] : "Mac"
    }

    public static let iOSDevices = ["iPhone 16", "iPhone 16 Pro", "iPhone 16 Pro Max", "iPhone SE (3rd generation)", "iPad (A16)", "iPad Pro 11-inch", "iPad Pro 13-inch"]
    public var deviceChoices: [String] { document.isFlippedRuntime ? Self.iOSDevices : ["Mac"] }

    private func changed() { revision = session.revision }

    public var document: IBDocument { _ = revision; return session.document }
    public var layout: IBCanvasLayout { _ = revision; return session.layout }
    public var selectedID: String? { _ = revision; return session.selectedID }
    public var selected: IBDocument.Object? { _ = revision; return session.selected }
    public var selectedConstraint: String? { _ = revision; return session.selectedConstraint }
    public var jumpBarPath: [String] { _ = revision; return session.jumpBarPath }
    public var canUndo: Bool { _ = revision; return session.canUndo }
    public var canRedo: Bool { _ = revision; return session.canRedo }
    public var saveCount: Int { _ = revision; return session.saveCount }
    public var problem: String? { _ = revision; return session.problem }
    public var controlState: IBControlState? { _ = revision; return session.controlState }
    public var zoomText: String { "\(Int((zoom * 100).rounded()))%" }

    public func inspectorSections(_ t: IBInspectorTab) -> [IBInspectorSection] { _ = revision; return session.inspectorSections(t) }

    public var outlineFilter: String {
        get { _ = revision; return session.outlineFilter }
        set { session.outlineFilter = newValue; revision &+= 1 }
    }

    public struct VisibleRow: Identifiable, Equatable {
        public var row: IBOutlineRow
        public var depth: Int
        public var isExpanded: Bool
        public var id: String { row.id }
    }

    public var visibleRows: [VisibleRow] {
        _ = revision
        var out: [VisibleRow] = []
        let filtering = !session.outlineFilter.isEmpty
        func walk(_ r: IBOutlineRow, _ d: Int) {
            let open = filtering || !collapsed.contains(r.id)
            out.append(VisibleRow(row: r, depth: d, isExpanded: open && !r.children.isEmpty))
            if open { r.children.forEach { walk($0, d + 1) } }
        }
        session.outlineRows.forEach { walk($0, 0) }
        return out
    }

    public func setExpanded(_ id: String, _ open: Bool) {
        if open { collapsed.remove(id) } else { collapsed.insert(id) }
    }

    public func isSelected(_ r: IBOutlineRow) -> Bool {
        _ = revision
        if let c = r.constraintID { return c == session.selectedConstraint }
        return session.selectedConstraint == nil && r.objectID != nil && r.objectID == session.selectedID
    }

    public func select(id: String?) { session.select(id: id); changed() }
    public func select(row: IBOutlineRow) { session.select(row: row); changed() }

    public func moveSelection(_ d: Int) {
        let rows = visibleRows.filter { $0.row.objectID != nil || $0.row.constraintID != nil }
        guard !rows.isEmpty else { return }
        let i = rows.firstIndex { isSelected($0.row) } ?? (d > 0 ? -1 : rows.count)
        select(row: rows[min(max(i + d, 0), rows.count - 1)].row)
    }

    public func pointerDown(at p: CGPoint) {
        let (hit, d) = IBCanvasDrag.begin(at: p, selected: session.selectedID, in: session.layout)
        if let hit, hit.id != session.selectedID || d?.handle == nil { select(id: hit.id) }
        drag = d
        dragPreview = nil
    }

    public func pointerDragged(to p: CGPoint) {
        guard let d = drag else { return }
        dragPreview = d.preview(at: p)
    }

    public func pointerUp(at p: CGPoint) {
        defer { drag = nil; dragPreview = nil }
        guard let d = drag, let r = d.result(at: p) else { return }
        session.setRootFrame(r, of: d.id)
        changed()
    }

    public func zoomIn() { zoom *= 1.25 }
    public func zoomOut() { zoom /= 1.25 }
    public func zoomToFit(_ viewport: CGSize) { zoom = layout.zoomToFit(viewport) }

    private func edit(_ f: () -> Void) { f(); changed() }

    public func undo() { edit { session.undo() } }
    public func redo() { edit { session.redo() } }
    public func deleteSelection() { edit { session.deleteSelection() } }
    @discardableResult
    public func move(_ id: String, into parent: String) -> Bool { defer { changed() }; return session.move(id, into: parent) }
    public func setTitle(_ s: String) { edit { session.setTitle(s) } }
    public func setPlaceholder(_ s: String) { edit { session.setPlaceholder(s) } }
    public func setHidden(_ b: Bool) { edit { session.setHidden(b) } }
    public func setEnabled(_ b: Bool) { edit { session.setEnabled(b) } }
    public func setAlignment(_ s: String) { edit { session.setAlignment(s) } }
    public func setAttribute(_ name: String, _ value: String?, of id: String) { edit { session.setAttribute(name, value, of: id) } }
    public func setToggle(_ row: IBInspectorRow, on: Bool) { edit { session.setToggle(row, on: on) } }
    public func setChoice(_ row: IBInspectorRow, _ value: String) { edit { session.setChoice(row, value) } }
    public func setColor(_ row: IBInspectorRow, _ title: String) { edit { session.setColor(row, title) } }
    public func setFrameComponent(_ c: String, _ v: CGFloat, of id: String) { edit { session.setFrameComponent(c, v, of: id) } }
    public func setConstant(_ v: CGFloat, ofConstraint id: String) { edit { session.setConstant(v, ofConstraint: id) } }
    public func addRuntimeAttribute() { edit { session.addRuntimeAttribute(keyPath: session.nextRuntimeKeyPath) } }
    public func removeRuntimeAttribute(_ keyPath: String) { edit { session.removeRuntimeAttribute(keyPath) } }
    public func disconnect(_ id: String) { edit { session.disconnect(id) } }

    @discardableResult
    public func insert(_ kind: IBDocument.NewObject) -> String? {
        defer { changed() }
        return session.insert(kind)
    }

    @discardableResult
    public func addConstraints(_ spec: IBDocument.NewConstraints) -> [String] {
        defer { changed(); isAddConstraintsShown = false }
        return session.addConstraints(spec)
    }

    public var libraryObjects: [IBDocument.NewObject] {
        let d = document
        return IBDocument.NewObject.matching(libraryFilter, in: IBDocument.NewObject.list(for: d), iOS: d.isFlippedRuntime)
    }

    public var libraryDetailParts: (name: String, subtitle: String, description: String)? {
        guard let o = librarySelection, libraryObjects.contains(o) else { return nil }
        return (o.rawValue, o.subtitle(iOS: document.isFlippedRuntime), o.details)
    }

    public var libraryDetail: String {
        guard let p = libraryDetailParts else { return "" }
        return "\(p.name)\n\(p.subtitle)\n\(p.description)"
    }

    @discardableResult
    public func insertFromLibrary(_ o: IBDocument.NewObject? = nil) -> String? {
        guard let kind = o ?? librarySelection else { return nil }
        librarySelection = kind
        return insert(kind)
    }

    public func moveLibrarySelection(_ d: Int) {
        let list = libraryObjects
        guard !list.isEmpty else { return }
        let i = librarySelection.flatMap { list.firstIndex(of: $0) } ?? (d > 0 ? -1 : list.count)
        librarySelection = list[min(max(i + d, 0), list.count - 1)]
    }

    public func actionState(_ action: String, tag: Int) -> (enabled: Bool, checked: Bool)? {
        switch action {
        case "showAddConstraints:": (selected?.parent?.isView == true, false)
        case "zoomCanvasIn:", "zoomCanvasOut:", "zoomCanvasToFit:", "updateCanvasFrames:", "showLibrary:": (true, false)
        case "zoomCanvasToPercent:": (true, Int((zoom * 10000).rounded()) == tag)
        case "toggleDocumentOutline:": (true, isOutlineShown)
        default: nil
        }
    }

    @discardableResult
    public func perform(_ action: String, tag: Int, viewport: CGSize = CGSize(width: 900, height: 600)) -> Bool {
        switch action {
        case "showAddConstraints:":
            guard selected?.parent?.isView == true else { return false }
            isAddConstraintsShown = true
        case "zoomCanvasIn:": zoomIn()
        case "zoomCanvasOut:": zoomOut()
        case "zoomCanvasToFit:": zoomToFit(viewport)
        case "zoomCanvasToPercent:": zoom = CGFloat(tag) / 10000
        case "toggleDocumentOutline:": isOutlineShown.toggle()
        case "updateCanvasFrames:": changed()
        case "showLibrary:": isLibraryShown.toggle()
        default: return false
        }
        return true
    }
}

public enum IBLibraryTab: Int, CaseIterable, Sendable {
    case objects, image, color, symbols
    public var title: String { ["Objects", "Image", "Color", "Symbols"][rawValue] }
    public var symbol: String { ["square.on.circle", "photo", "paintpalette", "star.square"][rawValue] }
}
