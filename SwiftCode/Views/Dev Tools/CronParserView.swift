import SwiftUI

struct CronParserView: View {
    @State private var cronExpression = "0 0 * * *"
    @State private var description = "Every day at midnight"

    var body: some View {
        VStack(spacing: 20) {
            TextField("0 0 * * *", text: $cronExpression)
                .font(.system(.title2, design: .monospaced))
                .textFieldStyle(.roundedBorder)
                .padding()
                .onChange(of: cronExpression) { parse() }

            VStack(alignment: .leading, spacing: 10) {
                Text("Human Readable Description:")
                    .font(.headline)
                Text(description)
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.secondary.opacity(0.1))
                    .cornerRadius(8)
            }
            .padding()

            Spacer()
        }
        .navigationTitle("Cron Parser")
    }

    func parse() {
        // In a real app, use a cron descriptor library.
        // Here we provide a basic logic for simple expressions.
        let parts = cronExpression.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
        if parts.count == 5 {
            description = "At minute \(parts[0]), hour \(parts[1]), day of month \(parts[2]), month \(parts[3]), day of week \(parts[4])"
        } else {
            description = "Invalid cron expression"
        }
    }
}
