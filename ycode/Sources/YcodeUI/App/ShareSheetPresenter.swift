import AppKit

/// Share sheet — Legacy's `ShareSheet` (`NSViewRepresentable` wrapper around
/// `NSSharingServicePicker`), ported in Ycode's AppKit form.
///
/// Ycode's macOS shell is AppKit-first, so the SwiftUI representable becomes
/// a plain presenter the AppKit code calls directly: hand it the items and
/// the view to anchor to, and it shows the system share picker. The picker
/// is dismissed by the system when a service is chosen, as in Legacy.
public enum ShareSheetPresenter {
    @MainActor
    public static func show(items: [Any], relativeTo view: NSView, preferredEdge: NSRectEdge = .minY) {
        let picker = NSSharingServicePicker(items: items)
        picker.show(relativeTo: view.bounds, of: view, preferredEdge: preferredEdge)
    }
}
