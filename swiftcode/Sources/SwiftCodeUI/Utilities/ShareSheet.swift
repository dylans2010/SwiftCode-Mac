import SwiftUI
import AppKit

struct ShareSheet: NSViewRepresentable {
    var activityItems: [Any]
    @Environment(\.dismiss) private var dismiss

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        if context.coordinator.shouldShow {
            context.coordinator.shouldShow = false
            let picker = NSSharingServicePicker(items: activityItems)
            picker.delegate = context.coordinator

            DispatchQueue.main.async {
                if let window = nsView.window {
                    picker.show(relativeTo: nsView.bounds, of: nsView, preferredEdge: .minY)
                }
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, NSSharingServicePickerDelegate {
        var parent: ShareSheet
        var shouldShow = true

        init(_ parent: ShareSheet) {
            self.parent = parent
        }

        func sharingServicePicker(_ sharingServicePicker: NSSharingServicePicker, didChoose service: NSSharingService?) {
            sharingServicePicker.delegate = nil
            parent.dismiss()
        }

        func sharingServicePicker(_ sharingServicePicker: NSSharingServicePicker, sharingServicesForItems items: [Any], proposedSharingServices proposedServices: [NSSharingService]) -> [NSSharingService] {
            return proposedServices
        }
    }
}
