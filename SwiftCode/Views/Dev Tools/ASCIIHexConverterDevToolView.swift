import SwiftUI
import os.log

@Observable
@MainActor
final class ASCIIHexConverterDevToolViewModel {
    var asciiInput: String = ""
    var hexInput: String = ""
    var errorMessage: String?

    private let logger = Logger(subsystem: "com.swiftcode.devtools", category: "ASCIIHexConverter")

    func convertASCIIToHex() {
        errorMessage = nil
        let bytes = [UInt8](asciiInput.utf8)
        hexInput = bytes.map { String(format: "%02X", $0) }.joined(separator: " ")
        logger.info("Converted ASCII to Hex string")
    }

    func convertHexToASCII() {
        errorMessage = nil
        let cleanedHex = hexInput.replacingOccurrences(of: " ", with: "")
                                 .replacingOccurrences(of: "0x", with: "")
                                 .replacingOccurrences(of: "0X", with: "")

        guard cleanedHex.count % 2 == 0 else {
            errorMessage = "Hex string length must be even (multiple of 2)."
            return
        }

        var bytes = [UInt8]()
        var startIndex = cleanedHex.startIndex
        while startIndex < cleanedHex.endIndex {
            let endIndex = cleanedHex.index(startIndex, offsetBy: 2)
            let sub = cleanedHex[startIndex..<endIndex]
            if let byte = UInt8(sub, radix: 16) {
                bytes.append(byte)
            } else {
                errorMessage = "Invalid hexadecimal character detected: \(sub)"
                return
            }
            startIndex = endIndex
        }

        if let decoded = String(bytes: bytes, encoding: .utf8) {
            asciiInput = decoded
        } else {
            errorMessage = "Could not decode decoded bytes into UTF8 string."
        }
        logger.info("Converted Hex to ASCII string")
    }
}

struct ASCIIHexConverterDevToolView: View {
    @State private var viewModel = ASCIIHexConverterDevToolViewModel()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Convert ASCII text strings to Hexadecimal representations, and vice versa.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 8) {
                    Text("ASCII Plaintext")
                        .font(.headline)
                    TextEditor(text: $viewModel.asciiInput)
                        .font(.system(.body, design: .monospaced))
                        .frame(height: 100)
                        .border(Color.secondary.opacity(0.2))

                    Button("Convert ASCII ➔ Hex") {
                        viewModel.convertASCIIToHex()
                    }
                    .buttonStyle(.borderedProminent)
                }

                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    Text("Hexadecimal Bytes (space-separated or contiguous)")
                        .font(.headline)
                    TextEditor(text: $viewModel.hexInput)
                        .font(.system(.body, design: .monospaced))
                        .frame(height: 100)
                        .border(Color.secondary.opacity(0.2))

                    Button("Convert Hex ➔ ASCII") {
                        viewModel.convertHexToASCII()
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
        .navigationTitle("ASCII Hex Converter")
    }
}
