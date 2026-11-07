import AppKit

public enum ShareSheetPresenter {
    @MainActor
    public static func show(items: [Any], relativeTo view: NSView, preferredEdge: NSRectEdge = .minY) {
        let picker = NSSharingServicePicker(items: items)
        picker.show(relativeTo: view.bounds, of: view, preferredEdge: preferredEdge)
    }
}
