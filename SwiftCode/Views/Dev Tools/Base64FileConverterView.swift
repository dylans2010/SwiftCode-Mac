import SwiftUI

struct Base64FileConverterView: View {
    @State private var base64String = ""
    @State private var fileName = ""

    var body: some View {
        VStack(spacing: 20) {
            Button("Select File to Encode") { selectFile() }
                .buttonStyle(.bordered)

            if !fileName.isEmpty {
                Text("File: \(fileName)").font(.caption)
            }

            TextEditor(text: $base64String)
                .font(.system(.caption, design: .monospaced))
                .border(Color.secondary.opacity(0.2))
                .padding()

            HStack {
                Button("Decode to File") { decodeFile() }
                Button("Copy Base64") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(base64String, forType: .string)
                }
            }
            .padding(.bottom)
        }
        .navigationTitle("Base64 File Converter")
    }

    func selectFile() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        if panel.runModal() == .OK {
            if let url = panel.url {
                fileName = url.lastPathComponent
                if let data = try? Data(contentsOf: url) {
                    base64String = data.base64EncodedString()
                }
            }
        }
    }

    func decodeFile() {
        guard let data = Data(base64Encoded: base64String) else { return }
        let panel = NSSavePanel()
        if panel.runModal() == .OK {
            if let url = panel.url {
                try? data.write(to: url)
            }
        }
    }
}
