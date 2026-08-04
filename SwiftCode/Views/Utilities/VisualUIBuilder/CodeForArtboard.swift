import SwiftUI

public struct CodeForArtboard: View {
    @Environment(\.dismiss) private var dismiss

    let initialSource: String
    let onApply: (String) -> Void

    @State private var draftSource: String

    public init(initialSource: String, onApply: @escaping (String) -> Void) {
        self.initialSource = initialSource
        self.onApply = onApply
        _draftSource = State(initialValue: initialSource)
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Edit Artboard Source")
                        .font(.headline)
                    Text("Changes are kept locally until you click Apply.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Button("Cancel") {
                    dismiss()
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)
            }
            .padding()
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            // Native SwiftUI TextEditor
            TextEditor(text: $draftSource)
                .font(.system(.body, design: .monospaced))
                .scrollContentBackground(.hidden)
                .background(Color(NSColor.windowBackgroundColor))
                .padding(8)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            // Footer
            HStack {
                Spacer()
                Button("Cancel") {
                    dismiss()
                }
                .buttonStyle(.bordered)
                .controlSize(.large)

                Button("Apply") {
                    onApply(draftSource)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
            .padding()
            .background(Color(NSColor.windowBackgroundColor))
        }
        .frame(width: 750, height: 550)
    }
}
