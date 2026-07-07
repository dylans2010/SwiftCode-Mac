import SwiftUI

struct CronParserView: View {
    @State private var cronExpression = "*/5 * * * *"
    @State private var description = "Every 5 minutes"
    @State private var nextOccurrences: [String] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Enter a CRON expression to see its description and next run times.")
                .foregroundColor(.secondary)

            TextField("e.g. 0 0 * * *", text: $cronExpression)
                .font(.system(.title3, design: .monospaced))
                .textFieldStyle(.roundedBorder)
                .onChange(of: cronExpression) { parse() }

            VStack(alignment: .leading, spacing: 8) {
                Text("Description")
                    .font(.headline)
                Text(description)
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.accentColor.opacity(0.1))
                    .cornerRadius(8)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Next 5 Occurrences")
                    .font(.headline)
                ForEach(nextOccurrences, id: \.self) { time in
                    Text(time)
                        .font(.system(.body, design: .monospaced))
                        .padding(.vertical, 2)
                }
            }

            Spacer()
        }
        .padding()
        .navigationTitle("Cron Parser")
        .onAppear { parse() }
    }

    func parse() {
        // Simple mock parser for demo purposes
        if cronExpression == "*/5 * * * *" {
            description = "Every 5 minutes"
        } else if cronExpression == "0 0 * * *" {
            description = "At 12:00 AM every day"
        } else if cronExpression == "0 * * * *" {
            description = "Every hour at minute 0"
        } else {
            description = "Custom CRON expression: \(cronExpression)"
        }

        // Mock next occurrences
        let now = Date()
        nextOccurrences = (1...5).map { i in
            let date = now.addingTimeInterval(TimeInterval(i * 300))
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
            return formatter.string(from: date)
        }
    }
}
