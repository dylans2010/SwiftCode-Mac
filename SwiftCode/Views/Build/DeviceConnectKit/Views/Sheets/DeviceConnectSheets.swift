import SwiftUI

struct DeviceDiagnosticsSheet: View {
    @Environment(\.dismiss) private var dismiss
    let reportText: String

    var body: some View {
        NavigationStack {
            VStack {
                ScrollView {
                    Text(reportText)
                        .font(.system(.body, design: .monospaced))
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .background(Color(NSColor.textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .padding()

                HStack {
                    Button("Copy to Clipboard") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(reportText, forType: .string)
                    }
                    .buttonStyle(.bordered)

                    Spacer()

                    Button("Done") {
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(.horizontal)
                .padding(.bottom)
            }
            .navigationTitle("Diagnostics Analyzer")
        }
        .frame(width: 500, height: 600)
    }
}
