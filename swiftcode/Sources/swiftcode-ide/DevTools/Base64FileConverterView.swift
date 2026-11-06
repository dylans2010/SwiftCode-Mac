// Ported from SwiftCode-Legacy `SwiftCode/Views/Dev Tools/Base64FileConverterView.swift` (Dylan's own code; direct port authorised under MIT).
// V10 (independent verification): confirmed genuinely missing from production at bc28f653.
// Verbatim port: no references to Legacy-only types; `import SwiftCodeUI` added for .liquidGlass.
// File encode/decode capability — prod's Base64ConverterView does text-only.
import SwiftUI
import SwiftCodeUI

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
        .liquidGlass(style: .subtle, cornerRadius: 12)
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
