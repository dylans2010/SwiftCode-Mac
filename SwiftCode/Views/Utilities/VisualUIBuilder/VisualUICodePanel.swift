import SwiftUI

/// Sidebar code viewing workspace displaying real-time standard Swift code generated from active canvas configurations.
public struct VisualUICodePanel: View {
    let document: VisualUIDocument

    @State private var showingCopiedLabel = false

    public var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("GENERATED SOURCE CODE")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)

                Spacer()

                Button {
                    copyCodeToClipboard()
                } label: {
                    Label(showingCopiedLabel ? "Copied" : "Copy", systemImage: "doc.on.doc")
                }
                .buttonStyle(.plain)
                .font(.caption)
            }
            .padding(8)
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            // Source View
            ScrollView {
                Text(generatedCode)
                    .font(.system(.caption, design: .monospaced))
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Color.secondary.opacity(0.01))
        }
    }

    private var generatedCode: String {
        let generator = VisualUICodeGenerator()
        return generator.generateCode(for: document.scene, targetFramework: document.scene.currentFramework)
    }

    private func copyCodeToClipboard() {
        let pasteboard = NSPasteboard.general
        pasteboard.declareTypes([.string], owner: nil)
        pasteboard.setString(generatedCode, forType: .string)

        withAnimation {
            showingCopiedLabel = true
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            showingCopiedLabel = false
        }
        VisualUISettings.shared.addLog("Copied source code from side Code panel.")
    }
}
