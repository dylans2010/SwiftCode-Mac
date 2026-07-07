import SwiftUI

struct CronGeneratorView: View {
    @State private var minute = "*"
    @State private var hour = "*"
    @State private var dayOfMonth = "*"
    @State private var month = "*"
    @State private var dayOfWeek = "*"
    @State private var cronExpression = "* * * * *"

    var body: some View {
        VStack(spacing: 20) {
            Form {
                TextField("Minute (0-59)", text: $minute)
                TextField("Hour (0-23)", text: $hour)
                TextField("Day of Month (1-31)", text: $dayOfMonth)
                TextField("Month (1-12)", text: $month)
                TextField("Day of Week (0-6)", text: $dayOfWeek)
            }
            .padding()
            .onChange(of: minute) { update() }
            .onChange(of: hour) { update() }
            .onChange(of: dayOfMonth) { update() }
            .onChange(of: month) { update() }
            .onChange(of: dayOfWeek) { update() }

            VStack(spacing: 10) {
                Text("Generated Cron Expression:")
                Text(cronExpression)
                    .font(.system(.title, design: .monospaced))
                    .padding()
                    .background(Color.accentColor.opacity(0.1))
                    .cornerRadius(8)
            }

            Spacer()
        }
        .navigationTitle("Cron Generator")
    }

    func update() {
        cronExpression = "\(minute) \(hour) \(dayOfMonth) \(month) \(dayOfWeek)"
    }
}
