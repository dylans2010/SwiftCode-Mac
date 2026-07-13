import SwiftUI
import os.log

@Observable
@MainActor
final class EpochConverterViewModel {
    var rawEpoch: String = ""
    var formattedDate: String = ""
    var rawDateString: String = ""
    var convertedEpoch: String = ""
    var errorMessage: String?

    private let logger = Logger(subsystem: "com.swiftcode.devtools", category: "EpochConverter")

    func convertToDate() {
        errorMessage = nil
        formattedDate = ""

        guard let seconds = Double(rawEpoch) else {
            errorMessage = "Please enter a valid numeric epoch timestamp."
            return
        }

        let date = Date(timeIntervalSince1970: seconds)
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS 'UTC'"
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formattedDate = formatter.string(from: date)
        logger.info("Successfully converted Epoch to Date string")
    }

    func convertToEpoch() {
        errorMessage = nil
        convertedEpoch = ""

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        formatter.timeZone = TimeZone(secondsFromGMT: 0)

        guard let date = formatter.date(from: rawDateString) else {
            errorMessage = "Invalid date string. Expected: yyyy-MM-dd HH:mm:ss"
            return
        }

        convertedEpoch = String(Int(date.timeIntervalSince1970))
        logger.info("Successfully converted Date string to Epoch timestamp")
    }
}

struct EpochConverterDevToolView: View {
    @State private var viewModel = EpochConverterViewModel()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Bidirectional conversion between Unix epoch timestamps and human readable date strings.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Unix Epoch Timestamp (seconds)")
                        .font(.headline)
                    HStack {
                        TextField("e.g. 1783854130", text: $viewModel.rawEpoch)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(.body, design: .monospaced))

                        Button("Convert ➔ Date") {
                            viewModel.convertToDate()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }

                if !viewModel.formattedDate.isEmpty {
                    Text("Resulting UTC Date: \(viewModel.formattedDate)")
                        .font(.system(.headline, design: .monospaced))
                        .foregroundColor(.green)
                        .padding(.vertical, 4)
                }

                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    Text("Date String (yyyy-MM-dd HH:mm:ss UTC)")
                        .font(.headline)
                    HStack {
                        TextField("e.g. 2026-07-13 14:22:10", text: $viewModel.rawDateString)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(.body, design: .monospaced))

                        Button("Convert ➔ Epoch") {
                            viewModel.convertToEpoch()
                        }
                        .buttonStyle(.bordered)
                    }
                }

                if !viewModel.convertedEpoch.isEmpty {
                    Text("Resulting Epoch: \(viewModel.convertedEpoch)")
                        .font(.system(.headline, design: .monospaced))
                        .foregroundColor(.blue)
                        .padding(.vertical, 4)
                }

                if let error = viewModel.errorMessage {
                    Text(error)
                        .foregroundColor(.red)
                        .font(.caption.bold())
                }
            }
            .padding()
        }
        .navigationTitle("Epoch Unix Converter")
        .onAppear {
            let nowEpoch = String(Int(Date().timeIntervalSince1970))
            viewModel.rawEpoch = nowEpoch
            viewModel.rawDateString = "2026-07-13 14:22:10"
            viewModel.convertToDate()
        }
    }
}
