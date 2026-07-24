import SwiftUI
import AppKit

public struct Base64ImageDecoderView: View {
    @State private var base64Input = ""
    @State private var decodedImage: NSImage? = nil
    @State private var errorMessage: String? = nil

    public init() {}

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Base64 Image Decoder")
                        .font(.title.bold())
                    Text("Paste a Base64 string payload to instantly decode and display the underlying binary graphic image.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                GroupBox {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Base64 Image Payload String")
                            .font(.caption.bold())
                            .foregroundColor(.secondary)

                        TextEditor(text: $base64Input)
                            .font(.system(.body, design: .monospaced))
                            .frame(height: 120)
                            .padding(6)
                            .background(Color.black.opacity(0.15))
                            .cornerRadius(6)

                        HStack {
                            Button("Clear") {
                                base64Input = ""
                                decodedImage = nil
                                errorMessage = nil
                            }
                            .buttonStyle(.bordered)

                            Spacer()

                            Button("Decode and Display Image") {
                                performDecoding()
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.orange)
                        }
                    }
                    .padding(8)
                }
                .groupBoxStyle(ModernGroupBoxStyle())

                if let error = errorMessage {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.red)
                        Text(error)
                            .foregroundColor(.red)
                            .font(.subheadline)
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.red.opacity(0.08))
                    .cornerRadius(8)
                }

                if let image = decodedImage {
                    GroupBox {
                        VStack(alignment: .center, spacing: 14) {
                            Text("Decoded Visual Representation")
                                .font(.headline)
                                .foregroundColor(.green)

                            Image(nsImage: image)
                                .resizable()
                                .scaledToFit()
                                .frame(maxHeight: 350)
                                .cornerRadius(8)
                                .shadow(radius: 4)

                            HStack {
                                Text("Dimensions: \(Int(image.size.width)) x \(Int(image.size.height)) pixels")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Spacer()
                            }
                        }
                        .padding(10)
                    }
                    .groupBoxStyle(ModernGroupBoxStyle())
                }
            }
            .padding(24)
        }
        .background(Color(NSColor.windowBackgroundColor))
    }

    private func performDecoding() {
        errorMessage = nil
        decodedImage = nil

        let trimmed = base64Input
            .trimmingCharacters(in: .whitespacesAndNewlines)
            // Strip common prefix wrappers (like 'data:image/png;base64,')
            .replacingOccurrences(of: "data:image/png;base64,", with: "")
            .replacingOccurrences(of: "data:image/jpeg;base64,", with: "")
            .replacingOccurrences(of: "data:image/gif;base64,", with: "")

        guard !trimmed.isEmpty else {
            errorMessage = "Please enter or paste a valid non-empty Base64 payload."
            return
        }

        guard let data = Data(base64Encoded: trimmed) else {
            errorMessage = "Failure: Decoded sequence is not a valid base64 representation."
            return
        }

        guard let nsImg = NSImage(data: data) else {
            errorMessage = "Failure: Decoded binary buffer could not be instantiated as an image catalog."
            return
        }

        decodedImage = nsImg
    }
}
