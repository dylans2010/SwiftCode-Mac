import SwiftUI

struct HTMLEntityConverterView: View {
    @State private var input = "Hello & World > <"
    @State private var output = ""
    @State private var isEncoding = true

    var body: some View {
        VStack(spacing: 20) {
            Picker("Mode", selection: $isEncoding) {
                Text("Encode").tag(true)
                Text("Decode").tag(false)
            }
            .pickerStyle(.segmented)
            .padding()

            TextEditor(text: $input)
                .border(Color.secondary.opacity(0.2))
                .padding()

            Button(isEncoding ? "Encode Entities" : "Decode Entities") { process() }
                .buttonStyle(.borderedProminent)

            TextEditor(text: .constant(output))
                .border(Color.secondary.opacity(0.2))
                .padding()

            Spacer()
        }
        .navigationTitle("HTML Entity Converter")
    }

    func process() {
        if isEncoding {
            output = input.replacingOccurrences(of: "&", with: "&amp;")
                          .replacingOccurrences(of: "<", with: "&lt;")
                          .replacingOccurrences(of: ">", with: "&gt;")
                          .replacingOccurrences(of: "\"", with: "&quot;")
                          .replacingOccurrences(of: "'", with: "&apos;")
        } else {
            output = input.replacingOccurrences(of: "&amp;", with: "&")
                          .replacingOccurrences(of: "&lt;", with: "<")
                          .replacingOccurrences(of: "&gt;", with: ">")
                          .replacingOccurrences(of: "&quot;", with: "\"")
                          .replacingOccurrences(of: "&apos;", with: "'")
        }
    }
}
