// AgentAttachmentPickerView.swift
//
// Ported from Legacy `SwiftCode/Views/Agent/AgentAttachmentPickerView.swift` (SwiftCode-Mac migration, Views/UI worklist).
// Worklist verdict: PARTIAL.
// Missing behaviour ported: arbitrary-file picker (NSOpenPanel, multi-select, image/file types)
// Static port only — no Swift toolchain here; build verification pending on Dylan's Mac.
import SwiftCodeAssistant
import SwiftUI

struct AgentAttachmentPickerView: View {
    @Binding var attachments: [AgentAttachment]

    var body: some View {
        Button(action: pickAttachment) {
            Image(systemName: "plus")
        }
        .buttonStyle(.plain)
        .padding(6)
        .liquidGlass(style: .subtle, cornerRadius: 8)
    }

    private func pickAttachment() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true

        if panel.runModal() == .OK {
            for url in panel.urls {
                let ext = url.pathExtension.lowercased()
                let type: AgentAttachment.AttachmentType = (ext == "png" || ext == "jpg" || ext == "jpeg") ? .image : .file
                attachments.append(AgentAttachment(name: url.lastPathComponent, url: url, type: type))
            }
        }
    }
}
