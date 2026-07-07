import SwiftUI

struct TimezoneConverterView: View {
    @State private var selectedDate = Date()
    @State private var sourceTimezone = TimeZone.current.identifier
    @State private var targetTimezone = "UTC"
    @State private var result = ""

    var body: some View {
        VStack(spacing: 20) {
            DatePicker("Select Time", selection: $selectedDate)
                .padding()

            Form {
                TextField("Source Timezone", text: $sourceTimezone)
                TextField("Target Timezone", text: $targetTimezone)
            }
            .padding()

            Button("Compare") { compare() }
                .buttonStyle(.borderedProminent)

            Text(result)
                .font(.headline)
                .padding()

            Spacer()
        }
        .navigationTitle("Timezone Converter")
    }

    func compare() {
        result = "Time in \(targetTimezone) is..."
    }
}
