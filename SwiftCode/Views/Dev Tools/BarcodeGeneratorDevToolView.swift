import SwiftUI
import os.log

@Observable
@MainActor
final class BarcodeGeneratorViewModel {
    var content: String = "SWIFTCODE123"
    var type: String = "Code 128"
    var errorMessage: String?

    private let logger = Logger(subsystem: "com.swiftcode.devtools", category: "BarcodeGenerator")

    func generate() {
        errorMessage = nil
        guard !content.isEmpty else {
            errorMessage = "Please enter some string content."
            return
        }
        logger.info("Generating simulated barcode for content: \(self.content) using \(self.type)")
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
                }

                Picker("Barcode Standard", selection: $viewModel.type) {
                    Text("Code 128").tag("Code 128")
                    Text("Code 39").tag("Code 39")
                }
                .pickerStyle(.radioGroup)

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
                    Text("Simulated Barcode Graphic")
                        .font(.headline)
                        .foregroundColor(.secondary)

                    // Barcode simulated drawing using varying-width bars
                    HStack(spacing: 2) {
                        ForEach(0..<45, id: \.self) { index in
                            Rectangle()
                                .fill(Color.primary)
                                .frame(width: (index % 3 == 0) ? 4 : ((index % 5 == 0) ? 1 : 2), height: 100)
                        }
                    }
                    .padding()
                    .background(Color.white)
                    .cornerRadius(4)

                    Text(viewModel.content)
                        .font(.system(.body, design: .monospaced))
                        .foregroundColor(.primary)
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(10)
            }
            .padding()
        }
        .navigationTitle("Barcode Generator")
    }
}
