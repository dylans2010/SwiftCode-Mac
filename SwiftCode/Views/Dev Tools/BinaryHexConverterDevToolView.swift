import SwiftUI
import os.log

@Observable
@MainActor
final class BinaryHexConverterViewModel {
    var binaryInput: String = ""
    var hexOutput: String = ""
    var errorMessage: String?

    private let logger = Logger(subsystem: "com.swiftcode.devtools", category: "BinaryHexConverter")

    func convertBinaryToHex() {
        errorMessage = nil
        let cleaned = binaryInput.replacingOccurrences(of: " ", with: "")

        guard cleaned.allSatisfy({ $0 == "0" || $0 == "1" }) else {
            errorMessage = "Binary string must only contain 0 and 1."
            return
        }

        guard cleaned.count % 4 == 0 else {
            errorMessage = "Binary string length must be a multiple of 4."
            return
        }

        var hexResult = ""
        var startIndex = cleaned.startIndex
        while startIndex < cleaned.endIndex {
            let endIndex = cleaned.index(startIndex, offsetBy: 4)
            let sub = String(cleaned[startIndex..<endIndex])
            if let val = Int(sub, radix: 2) {
                hexResult.append(String(val, radix: 16).uppercased())
            }
            startIndex = endIndex
        }

        hexOutput = hexResult
        logger.info("Successfully converted binary string to Hex")
    }

    func convertHexToBinary() {
        errorMessage = nil
        let cleaned = hexOutput.replacingOccurrences(of: " ", with: "")
                               .replacingOccurrences(of: "0x", with: "")
                               .replacingOccurrences(of: "0X", with: "")

        guard cleaned.allSatisfy({ $0.isHexDigit }) else {
            errorMessage = "Hex string must only contain hexadecimal characters (0-9, A-F)."
            return
        }

        var binResult = ""
        for char in cleaned {
            if let val = Int(String(char), radix: 16) {
                let binStr = String(val, radix: 2)
                let padded = String(repeating: "0", count: 4 - binStr.count) + binStr
                binResult.append(padded + " ")
            }
        }

        binaryInput = binResult.trimmingCharacters(in: .whitespaces)
        logger.info("Successfully converted Hex string to binary")
    }
}

struct BinaryHexConverterDevToolView: View {
    @State private var viewModel = BinaryHexConverterViewModel()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Perform direct binary bitstream to hexadecimal conversions and vice versa.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Binary Stream (e.g., 0100 1001)")
                        .font(.headline)
                    TextField("Enter binary", text: $viewModel.binaryInput)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))

                    Button("Convert Binary ➔ Hex") {
                        viewModel.convertBinaryToHex()
                    }
                    .buttonStyle(.borderedProminent)
                }

                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    Text("Hexadecimal Bytes")
                        .font(.headline)
                    TextField("Enter hex", text: $viewModel.hexOutput)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))

                    Button("Convert Hex ➔ Binary") {
                        viewModel.convertHexToBinary()
                    }
                    .buttonStyle(.bordered)
                }

                if let error = viewModel.errorMessage {
                    Text(error)
                        .foregroundColor(.red)
                        .font(.caption.bold())
                }
            }
            .padding()
        }
        .navigationTitle("Binary Hex Converter")
    }
}
