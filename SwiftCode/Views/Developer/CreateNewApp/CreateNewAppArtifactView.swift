import SwiftUI

public struct CreateNewAppArtifactView: View {
    public let summaryContent: String
    @Environment(\.dismiss) private var dismiss

    public init(summaryContent: String) {
        self.summaryContent = summaryContent
    }

    public var body: some View {
        VStack(spacing: 0) {
            HStack {
                Label("App Summary", systemImage: "doc.text.fill")
                    .font(.headline)
                Spacer()
                Button("Done") {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding()
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(summaryContent.isEmpty ? "No application summary available." : summaryContent)
                        .font(.system(.body, design: .default))
                        .textSelection(.enabled)
                        .padding()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(minWidth: 600, minHeight: 500)
    }
}
