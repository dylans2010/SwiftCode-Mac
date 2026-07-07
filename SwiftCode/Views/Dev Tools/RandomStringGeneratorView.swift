import SwiftUI

struct RandomStringGeneratorView: View {
    @State private var length = 16
    @State private var useUppercase = true
    @State private var useLowercase = true
    @State private var useNumbers = true
    @State private var useSymbols = false
    @State private var result = ""

    var body: some View {
        VStack(spacing: 20) {
            Form {
                Section("Settings") {
                    Stepper("Length: \(length)", value: $length, in: 1...256)
                    Toggle("Include Uppercase (A-Z)", isOn: $useUppercase)
                    Toggle("Include Lowercase (a-z)", isOn: $useLowercase)
                    Toggle("Include Numbers (0-9)", isOn: $useNumbers)
                    Toggle("Include Symbols (!@#$)", isOn: $useSymbols)
                }
            }

            Button("Generate Random String") { generate() }
                .buttonStyle(.borderedProminent)

            TextEditor(text: .constant(result))
                .font(.system(.title, design: .monospaced))
                .frame(height: 100)
                .border(Color.secondary.opacity(0.2))
                .padding()

            Button("Copy to Clipboard") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(result, forType: .string)
            }
            .disabled(result.isEmpty)

            Spacer()
        }
        .padding()
        .navigationTitle("Random String Generator")
    }

    func generate() {
        let uppercase = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
        let lowercase = "abcdefghijklmnopqrstuvwxyz"
        let numbers = "0123456789"
        let symbols = "!@#$%^&*()_+-=[]{}|;':\",./<>?"

        var charset = ""
        if useUppercase { charset += uppercase }
        if useLowercase { charset += lowercase }
        if useNumbers { charset += numbers }
        if useSymbols { charset += symbols }

        guard !charset.isEmpty else {
            result = "Select at least one character set."
            return
        }

        result = String((0..<length).map { _ in charset.randomElement()! })
    }
}
