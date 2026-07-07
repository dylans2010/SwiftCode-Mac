import SwiftUI

struct BinaryConverterView: View {
    @State private var decimalInput = "255"
    @State private var binaryOutput = "11111111"

    var body: some View {
        VStack(spacing: 30) {
            VStack(alignment: .leading) {
                Text("Decimal Number")
                    .font(.headline)
                TextField("e.g. 42", text: $decimalInput)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: decimalInput) { convert() }
            }

            VStack(alignment: .leading) {
                Text("Binary Representation")
                    .font(.headline)
                HStack {
                    Text(binaryOutput)
                        .font(.system(.title2, design: .monospaced))
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.secondary.opacity(0.1))
                        .cornerRadius(8)

                    Button(action: {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(binaryOutput, forType: .string)
                    }) {
                        Image(systemName: "doc.on.doc")
                    }
                    .buttonStyle(.plain)
                }
            }

            Spacer()
        }
        .padding()
        .navigationTitle("Binary Converter")
    }

    func convert() {
        if let decimal = Int(decimalInput) {
            binaryOutput = String(decimal, radix: 2)
        } else {
            binaryOutput = "Invalid Input"
        }
    }
}
