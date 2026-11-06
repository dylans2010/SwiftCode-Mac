// Ported from SwiftCode-Legacy `SwiftCode/Views/Developer/RealtimeMetricsDashboardView.swift` (Dylan's own code; direct port authorised under MIT).
// Audit A: MISSING at bc28f653. Static port only — no Swift toolchain here; build verification pending on Dylan's Mac.
import SwiftUI
import SwiftCodeUI

struct RealtimeMetricsDashboardView: View {
    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 160))], spacing: 16) {
                MetricTile(title: "Active Users", value: "1,240", icon: "person.2.fill", color: .blue)
                MetricTile(title: "Request Rate", value: "45/s", icon: "arrow.up.right.circle.fill", color: .green)
                MetricTile(title: "Error Rate", value: "0.2%", icon: "exclamationmark.circle.fill", color: .orange)
                MetricTile(title: "Avg Latency", value: "142ms", icon: "clock.fill", color: .purple)
                MetricTile(title: "Storage Used", value: "1.4 GB", icon: "hdd.fill", color: .teal)
                MetricTile(title: "Memory Peak", value: "512 MB", icon: "memorychip", color: .pink)
            }
            .padding()
        }
        .liquidGlass(style: .subtle, cornerRadius: 12)
        .navigationTitle("Metrics Dashboard")
        .background(Color(red: 0.05, green: 0.05, blue: 0.07).ignoresSafeArea())
    }
}

struct MetricTile: View {
    let title: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: icon)
                .font(.headline)
                .foregroundStyle(color)

            VStack(alignment: .leading, spacing: 4) {
                Text(value)
                    .font(.title2.bold())
                    .foregroundStyle(.white)
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 16))
    }
}
