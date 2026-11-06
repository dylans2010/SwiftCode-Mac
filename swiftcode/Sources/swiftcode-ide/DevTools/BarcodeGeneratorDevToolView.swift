// Ported from SwiftCode-Legacy `SwiftCode/Views/Dev Tools/BarcodeGeneratorDevToolView.swift` (Dylan's own code; direct port authorised under MIT).
// V10 (independent verification): confirmed genuinely missing from production at bc28f653.
// Verbatim port: no references to Legacy-only types; `import SwiftCodeUI` added for .liquidGlass.
//
// CLEANUP (2026-11-06, A1): the ported view drew 45 fixed-width
// rectangles whose widths depended only on the bar index — decoration
// that encoded nothing and never changed with the input. Replaced with
// real barcode generation: CoreImage's CICode128BarcodeGenerator /
// CICode39BarcodeGenerator encode the user's actual input (inputMessage),
// rendered through CIContext to an NSImage (same pattern as the sibling
// QRCodeGeneratorView). Code 39 input is validated against its real
// character set; input the chosen symbology cannot encode is reported as
// an error instead of producing a plausible-looking fake barcode.
import SwiftUI
import SwiftCodeUI
import CoreImage
import os.log

@Observable
@MainActor
final class BarcodeGeneratorViewModel {
    var content: String = "SWIFTCODE123"
    var type: String = "Code 128"
    var errorMessage: String?
    /// The real barcode image for `content` in `type`, or nil when the
    /// input cannot be encoded.
    var barcodeImage: NSImage?

    private let context = CIContext()
    private let logger = Logger(subsystem: "com.swiftcode.devtools", category: "BarcodeGenerator")

    func generate() {
        errorMessage = nil
        barcodeImage = nil
        guard !content.isEmpty else {
            errorMessage = "Please enter some string content."
            return
        }
        let filterName = type == "Code 39" ? "CICode39BarcodeGenerator" : "CICode128BarcodeGenerator"
        if type == "Code 39", let invalid = content.first(where: { !"ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-. $/+%".contains($0) }) {
            errorMessage = "Code 39 cannot encode “\(invalid)”. It only encodes A–Z, 0–9 and - . space $ / + %. Use Code 128 for other characters."
            return
        }
        guard let filter = CIFilter(name: filterName) else {
            errorMessage = "Barcode filter \(filterName) is unavailable on this system."
            return
        }
        filter.setValue(Data(content.utf8), forKey: "inputMessage")
        filter.setValue(10, forKey: "inputQuietSpace")
        guard let outputImage = filter.outputImage else {
            errorMessage = "Could not encode “\(content)” as \(type)."
            return
        }
        // Barcode output is one unit tall; scale it to a readable size.
        let extent = outputImage.extent
        guard extent.width > 0, extent.height > 0 else {
            errorMessage = "Could not encode “\(content)” as \(type)."
            return
        }
        let scaled = outputImage.transformed(by: CGAffineTransform(scaleX: 400 / extent.width, y: 120 / extent.height))
        guard let cgImage = context.createCGImage(scaled, from: scaled.extent) else {
            errorMessage = "Could not render the \(type) barcode image."
            return
        }
        barcodeImage = NSImage(cgImage: cgImage, size: NSSize(width: 400, height: 120))
        logger.info("Generated real \(self.type) barcode for content: \(self.content)")
    }
}

struct BarcodeGeneratorDevToolView: View {
    @State private var viewModel = BarcodeGeneratorViewModel()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Generate Code 128 and Code 39 developer bar code layouts from input string content.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Barcode Content")
                        .font(.headline)
                    TextField("Enter value", text: $viewModel.content)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                        .onChange(of: viewModel.content) { viewModel.generate() }
                }

                Picker("Barcode Standard", selection: $viewModel.type) {
                    Text("Code 128").tag("Code 128")
                    Text("Code 39").tag("Code 39")
                }
                .pickerStyle(.radioGroup)
                .onChange(of: viewModel.type) { viewModel.generate() }

                Button("Re-generate Barcode") {
                    viewModel.generate()
                }
                .buttonStyle(.borderedProminent)

                if let error = viewModel.errorMessage {
                    Text(error)
                        .foregroundColor(.red)
                        .font(.caption.bold())
                }

                Divider()

                VStack(alignment: .center, spacing: 12) {
                    Text("Barcode Graphic")
                        .font(.headline)
                        .foregroundColor(.secondary)

                    if let image = viewModel.barcodeImage {
                        Image(nsImage: image)
                            .interpolation(.none)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 400, height: 120)
                            .padding()
                            .background(Color.white)
                            .cornerRadius(4)
                    } else {
                        Text("No barcode — enter content that \(viewModel.type) can encode.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .frame(width: 400, height: 120)
                            .background(Color.white)
                            .cornerRadius(4)
                    }

                    Text(viewModel.content)
                        .font(.system(.body, design: .monospaced))
                        .foregroundColor(.primary)
                }
                .frame(maxWidth: .infinity)
                .padding()
                .liquidGlass(style: .standard, cornerRadius: 10)
            }
            .padding()
        }
        .navigationTitle("Barcode Generator")
        .onAppear {
            viewModel.generate()
        }
    }
}
