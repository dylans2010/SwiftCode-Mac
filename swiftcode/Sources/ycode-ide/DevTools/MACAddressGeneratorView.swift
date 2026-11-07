import SwiftUI

struct MACAddressGeneratorView: View {
    @State private var count = 1
    @State private var result = ""

    var body: some View {
        VStack(spacing: 20) {
            Stepper("Count: \(count)", value: $count, in: 1...100)
                .padding()

            Button("Generate MAC Addresses") { generate() }
                .buttonStyle(.borderedProminent)

            TextEditor(text: .constant(result))
                .font(.system(.body, design: .monospaced))
                .border(Color.secondary.opacity(0.2))
                .padding()

            Spacer()
        }
        .navigationTitle("MAC Address Generator")
    }

    func generate() {
        var addresses: [String] = []
        for _ in 0..<count {
            let mac = (0..<6).map { _ in String(format: "%02X", Int.random(in: 0...255)) }.joined(separator: ":")
            addresses.append(mac)
        }
        result = addresses.joined(separator: "\n")
    }
}
