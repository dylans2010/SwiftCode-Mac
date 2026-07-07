import SwiftUI

struct HTMLEntityConverterView: View {
    @State private var input = ""
    @State private var output = ""
    @State private var isEncoding = true

    var body: some View {
        VStack(spacing: 20) {
            Picker("Mode", selection: $isEncoding) {
                Text("Encode to Entities").tag(true)
                Text("Decode from Entities").tag(false)
            }
            .pickerStyle(.segmented)
            .padding([.top, .horizontal])

            VStack(alignment: .leading) {
                Text("Input")
                    .font(.headline)
                TextEditor(text: $input)
                    .font(.system(.body, design: .monospaced))
                    .frame(height: 150)
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                    )
                    .onChange(of: input) { process() }
            }
            .padding(.horizontal)

            VStack(alignment: .leading) {
                Text("Output")
                    .font(.headline)
                TextEditor(text: .constant(output))
                    .font(.system(.body, design: .monospaced))
                    .frame(height: 150)
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                    )
            }
            .padding([.bottom, .horizontal])
        }
        .navigationTitle("HTML Entity Converter")
    }

    func process() {
        if isEncoding {
            // Simple mock encoding
            output = input
                .replacingOccurrences(of: "&", with: "&amp;")
                .replacingOccurrences(of: "<", with: "&lt;")
                .replacingOccurrences(of: ">", with: "&gt;")
                .replacingOccurrences(of: "\"", with: "&quot;")
        } else {
            // Simple mock decoding
            output = input
                .replacingOccurrences(of: "&amp;", with: "&")
                .replacingOccurrences(of: "&lt;", with: "<")
                .replacingOccurrences(of: "&gt;", with: ">")
                .replacingOccurrences(of: "&quot;", with: "\"")
        }
    }
}
