import SwiftUI
import os.log

@Observable
@MainActor
final class Base32ConverterViewModel {
    var rawInput: String = ""
    var base32Output: String = ""
    var errorMessage: String?

    private let logger = Logger(subsystem: "com.swiftcode.devtools", category: "Base32Converter")

    // Simple RFC 4648 base32 alphabet mapping
    private let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ234567")

    func encode() {
        errorMessage = nil
        let bytes = [UInt8](rawInput.utf8)
        guard !bytes.isEmpty else {
            base32Output = ""
            return
        }

        var result = ""
        var i = 0
        while i < bytes.count {
            let byte1 = bytes[i]
            let byte2 = i + 1 < bytes.count ? bytes[i + 1] : 0
            let byte3 = i + 2 < bytes.count ? bytes[i + 2] : 0
            let byte4 = i + 3 < bytes.count ? bytes[i + 3] : 0
            let byte5 = i + 4 < bytes.count ? bytes[i + 4] : 0

            let c1 = byte1 >> 3
            let c2 = ((byte1 & 0x07) << 2) | (byte2 >> 6)
            let c3 = (byte2 >> 1) & 0x1F
            let c4 = ((byte2 & 0x01) << 4) | (byte3 >> 4)
            let c5 = ((byte3 & 0x0F) << 1) | (byte4 >> 7)
            let c6 = (byte4 >> 2) & 0x1F
            let c7 = ((byte4 & 0x03) << 3) | (byte5 >> 5)
            let c8 = byte5 & 0x1F

            result.append(alphabet[Int(c1)])
            result.append(alphabet[Int(c2)])

            if i + 1 < bytes.count {
                result.append(alphabet[Int(c3)])
            } else {
                result.append("=")
            }

            if i + 1 < bytes.count {
                if i + 2 < bytes.count {
                    result.append(alphabet[Int(c4)])
                } else {
                    result.append("=")
                }
            } else {
                result.append("=")
            }

            if i + 2 < bytes.count {
                if i + 3 < bytes.count {
                    result.append(alphabet[Int(c5)])
                } else {
                    result.append("=")
                }
            } else {
                result.append("=")
            }

            if i + 3 < bytes.count {
                result.append(alphabet[Int(c6)])
            } else {
                result.append("=")
            }

            if i + 3 < bytes.count {
                if i + 4 < bytes.count {
                    result.append(alphabet[Int(c7)])
                } else {
                    result.append("=")
                }
            } else {
                result.append("=")
            }

            if i + 4 < bytes.count {
                result.append(alphabet[Int(c8)])
            } else {
                result.append("=")
            }

            i += 5
        }

        base32Output = result
        logger.info("Successfully encoded input to Base32")
    }

    func decode() {
        errorMessage = nil
        let cleaned = base32Output.trimmingCharacters(in: .whitespacesAndNewlines).upperCasedWithoutPadding()
        guard !cleaned.isEmpty else {
            rawInput = ""
            return
        }

        var bits = 0
        var val = 0
        var bytes = [UInt8]()

        for char in cleaned {
            guard let index = alphabet.firstIndex(of: char) else {
                errorMessage = "Invalid Base32 character detected: \(char)"
                return
            }
            val = (val << 5) | index
            bits += 5
            if bits >= 8 {
                bytes.append(UInt8((val >> (bits - 8)) & 0xFF))
                bits -= 8
            }
        }

        if let decodedString = String(bytes: bytes, encoding: .utf8) {
            rawInput = decodedString
            logger.info("Successfully decoded Base32 input")
        } else {
            errorMessage = "Decoded bytes could not be formatted as a UTF-8 string."
        }
    }
}

fileprivate extension String {
    func upperCasedWithoutPadding() -> String {
        self.uppercased().replacingOccurrences(of: "=", with: "")
    }
}

struct Base32ConverterDevToolView: View {
    @State private var viewModel = Base32ConverterViewModel()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Encode and decode string values using RFC 4648 Base32 specification.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 8) {
                    Text("UTF-8 Raw Text")
                        .font(.headline)
                    TextEditor(text: $viewModel.rawInput)
                        .font(.system(.body, design: .monospaced))
                        .frame(height: 100)
                        .border(Color.secondary.opacity(0.2))

                    Button("Encode to Base32") {
                        viewModel.encode()
                    }
                    .buttonStyle(.borderedProminent)
                }

                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    Text("Base32 Output")
                        .font(.headline)
                    TextEditor(text: $viewModel.base32Output)
                        .font(.system(.body, design: .monospaced))
                        .frame(height: 100)
                        .border(Color.secondary.opacity(0.2))

                    Button("Decode Base32") {
                        viewModel.decode()
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
        .navigationTitle("Base32 Converter")
    }
}
