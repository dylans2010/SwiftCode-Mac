import SwiftUI

struct TimestampConverterView: View {
    @State private var timestamp = String(Int(Date().timeIntervalSince1970))
    @State private var date = Date()
    @State private var formattedDate = ""

    var body: some View {
        VStack(spacing: 30) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Unix Timestamp to Date")
                    .font(.headline)
                HStack {
                    TextField("1600000000", text: $timestamp)
                        .textFieldStyle(.roundedBorder)
                    Button("Convert") {
                        if let t = Double(timestamp) {
                            date = Date(timeIntervalSince1970: t)
                            updateFormattedDate()
                        }
                    }
                }
                Text("Result: \(formattedDate)")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            Divider()

            VStack(alignment: .leading, spacing: 10) {
                Text("Date to Unix Timestamp")
                    .font(.headline)
                DatePicker("Select Date", selection: $date)
                HStack {
                    Text("Timestamp:")
                    Text("\(Int(date.timeIntervalSince1970))")
                        .font(.system(.body, design: .monospaced))
                        .fontWeight(.bold)
                    Spacer()
                    Button("Copy") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString("\(Int(date.timeIntervalSince1970))", forType: .string)
                    }
                }
            }

            Spacer()
        }
        .padding()
        .navigationTitle("Timestamp Converter")
        .onAppear { updateFormattedDate() }
    }

    func updateFormattedDate() {
        let formatter = DateFormatter()
        formatter.dateStyle = .full
        formatter.timeStyle = .medium
        formattedDate = formatter.string(from: date)
    }
}
