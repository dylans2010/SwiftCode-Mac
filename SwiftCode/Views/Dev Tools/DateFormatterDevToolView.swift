import SwiftUI
import os.log

@Observable
@MainActor
final class DateFormatterDevToolViewModel {
    var rawInput: String = "2026-07-13T14:22:10Z"
    var formattedDate: String = ""
    var formatPattern: String = "yyyy-MM-dd HH:mm:ss"
    var errorMessage: String?

    private let logger = Logger(subsystem: "com.swiftcode.devtools", category: "DateFormatter")

    func parseAndFormat() {
        errorMessage = nil
        formattedDate = ""

        let isoFormatter = ISO8601DateFormatter()
        guard let date = isoFormatter.date(from: rawInput) else {
            // Try standard date fallback
            let fallbackFormatter = DateFormatter()
            fallbackFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
            if let fDate = fallbackFormatter.date(from: rawInput) {
                formatDate(fDate)
            } else {
                errorMessage = "Invalid ISO 8601 Date String format."
            }
            return
        }

        formatDate(date)
    }

    private func formatDate(_ date: Date) {
        let formatter = DateFormatter()
        formatter.dateFormat = formatPattern
        formattedDate = formatter.string(from: date)
        logger.info("Successfully parsed and reformatted date string")
    }
}

struct DateFormatterDevToolView: View {
    @State private var viewModel = DateFormatterDevToolViewModel()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Validate, parse, and experiment with standard DateFormatter formats on active timestamp strings.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 8) {
                    Text("ISO 8601 Date String Input")
                        .font(.headline)
                    TextField("e.g. 2026-07-13T14:22:10Z", text: $viewModel.rawInput)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Formatter Pattern (dateFormat)")
                        .font(.headline)
                    TextField("yyyy-MM-dd HH:mm:ss", text: $viewModel.formatPattern)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                }

                Button("Format Date") {
                    viewModel.parseAndFormat()
                }
                .buttonStyle(.borderedProminent)

                if let error = viewModel.errorMessage {
                    Text(error)
                        .foregroundColor(.red)
                }

                if !viewModel.formattedDate.isEmpty {
                    Divider()

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Formatted Local Output")
                            .font(.headline)
                            .foregroundColor(.blue)

                        Text(viewModel.formattedDate)
                            .font(.system(.title3, design: .monospaced))
                            .bold()
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(NSColor.controlBackgroundColor))
                            .cornerRadius(8)
                    }
                }
            }
            .padding()
        }
        .navigationTitle("Date Formatter")
        .onAppear {
            viewModel.parseAndFormat()
        }
    }
}
