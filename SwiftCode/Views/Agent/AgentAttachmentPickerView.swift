import SwiftUI

struct AgentAttachmentPickerView: View {
    @Binding var attachments: [AgentAttachment]

    var body: some View {
        Button(action: pickAttachment) {
            Image(systemName: "plus")
        }
        .buttonStyle(.plain)
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
