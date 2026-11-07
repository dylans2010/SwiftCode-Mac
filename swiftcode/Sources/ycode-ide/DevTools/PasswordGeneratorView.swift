import SwiftUI

struct PasswordGeneratorView: View {
    @State private var length = 16
    @State private var useUppercase = true
    @State private var useLowercase = true
    @State private var useNumbers = true
    @State private var useSymbols = true
    @State private var password = ""

    var body: some View {
        VStack(spacing: 20) {
            HStack {
                Text(password)
                    .font(.system(.title2, design: .monospaced))
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color.accentColor.opacity(0.1))
                    .cornerRadius(8)

                Button(action: {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(password, forType: .string)
                }) {
                    Image(systemName: "doc.on.doc")
                        .font(.title2)
                }
                .buttonStyle(.plain)
            }
            .padding([.top, .horizontal])

            VStack(spacing: 12) {
                Stepper("Length: \(length)", value: $length, in: 8...64)

                Toggle("Uppercase (A-Z)", isOn: $useUppercase)
                Toggle("Lowercase (a-z)", isOn: $useLowercase)
                Toggle("Numbers (0-9)", isOn: $useNumbers)
                Toggle("Symbols (!@#$)", isOn: $useSymbols)
            }
            .padding(.horizontal)

            Button("Generate Password") { generate() }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

            Spacer()
        }
        .navigationTitle("Password Generator")
        .onAppear { generate() }
    }

    func generate() {
        var charset = ""
        if useUppercase { charset += "ABCDEFGHIJKLMNOPQRSTUVWXYZ" }
        if useLowercase { charset += "abcdefghijklmnopqrstuvwxyz" }
        if useNumbers { charset += "0123456789" }
        if useSymbols { charset += "!@#$%^&*()_+-=[]{}|;:,.<>?" }

        guard !charset.isEmpty else { return }

        password = String((0..<length).map { _ in charset.randomElement()! })
    }
}
