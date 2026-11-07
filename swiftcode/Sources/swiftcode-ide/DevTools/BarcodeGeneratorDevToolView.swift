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
