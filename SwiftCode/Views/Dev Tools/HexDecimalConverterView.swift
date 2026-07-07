import SwiftUI

struct HexDecimalConverterView: View {
    @State private var hex = "FF"
    @State private var decimal = "255"

    var body: some View {
        VStack(spacing: 30) {
            VStack(alignment: .leading) {
                Text("Hexadecimal")
                    .font(.headline)
                TextField("e.g. 1A", text: $hex)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
                    .onChange(of: hex) { fromHex() }
            }

            VStack(alignment: .leading) {
                Text("Decimal")
                    .font(.headline)
                TextField("e.g. 26", text: $decimal)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: decimal) { fromDecimal() }
            }

            Spacer()
        }
        .padding()
        .navigationTitle("Hex to Decimal Converter")
    }

    func fromHex() {
        if let d = Int(hex, radix: 16) {
            decimal = "\(d)"
        }
    }

    func fromDecimal() {
        if let d = Int(decimal) {
            hex = String(d, radix: 16).uppercased()
        }
    }
}
