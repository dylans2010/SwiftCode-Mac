import SwiftUI

struct ImageBase64View: View {
    @State private var base64String = ""

    var body: some View {
        VStack(spacing: 20) {
            Text("Convert image to Base64 or vice-versa.")
                .foregroundColor(.secondary)

            HStack {
                Button("Select Image") {
                    // Logic to open file picker
                }
                .buttonStyle(.bordered)

                Spacer()

                Button("Copy Base64") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(base64String, forType: .string)
                }
                .disabled(base64String.isEmpty)
            }
            .padding(.horizontal)

            VStack(alignment: .leading) {
                Text("Base64 Data")
                    .font(.headline)
                TextEditor(text: $base64String)
                    .font(.system(.caption, design: .monospaced))
                    .frame(height: 200)
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                    )
            }
            .padding(.horizontal)

            VStack {
                Text("Image Preview")
                    .font(.headline)
                Rectangle()
                    .fill(Color.secondary.opacity(0.1))
                    .frame(height: 200)
                    .overlay(Text("Preview not available in demo").foregroundColor(.secondary))
            }
            .padding()

            Spacer()
        }
        .navigationTitle("Image to Base64")
    }
}
