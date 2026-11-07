import SwiftUI
import UniformTypeIdentifiers
import AppKit

struct FileImporterRepresentableView: NSViewRepresentable {
    var allowedContentTypes: [UTType]
    var allowsMultipleSelection: Bool = false
    var onDocumentsPicked: ([URL]) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            let panel = NSOpenPanel()
            panel.allowedContentTypes = allowedContentTypes
            panel.allowsMultipleSelection = allowsMultipleSelection
            panel.canChooseDirectories = true
            panel.canChooseFiles = true

            if let window = view.window {
                panel.beginSheetModal(for: window) { response in
                    if response == .OK {
                        onDocumentsPicked(panel.urls)
                    } else {
                        onDocumentsPicked([])
                    }
                }
            } else {
                panel.begin { response in
                    if response == .OK {
                        onDocumentsPicked(panel.urls)
                    } else {
                        onDocumentsPicked([])
                    }
                }
            }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}
