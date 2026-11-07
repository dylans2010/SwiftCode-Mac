import SwiftUI

struct Base64ConverterView: View {
    @State private var textInput = ""
    @State private var base64Output = ""
    @State private var isEncoding = true

    var body: some View {
        VStack(spacing: 20) {
            Picker("Mode", selection: $isEncoding) {
                Text("Text to Base64").tag(true)
                Text("Base64 to Text").tag(false)
            }
            .pickerStyle(.segmented)
            .padding([.top, .horizontal])

            VStack(alignment: .leading) {
                Text(isEncoding ? "Source Text" : "Base64 String")
                    .font(.headline)
                TextEditor(text: $textInput)
                    .font(.system(.body, design: .monospaced))
                    .frame(height: 150)
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                    )
                    .onChange(of: textInput) { convert() }
            }
            .padding(.horizontal)

            VStack(alignment: .leading) {
                HStack {
                    Text(isEncoding ? "Base64 Output" : "Text Output")
                        .font(.headline)
                    Spacer()
                    Button(action: {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(base64Output, forType: .string)
                    }) {
                        Label("Copy", systemImage: "doc.on.doc")
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.accentColor)
                }

                TextEditor(text: .constant(base64Output))
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
        .navigationTitle("Base64 Converter")
    }

    func convert() {
        if isEncoding {
            let data = Data(textInput.utf8)
            base64Output = data.base64EncodedString()
        } else {
            guard let data = Data(base64Encoded: textInput) else {
                base64Output = "Invalid Base64 string"
                return
            }
            base64Output = String(data: data, encoding: .utf8) ?? "Unable to decode as UTF-8 text"
        }
    }
}
