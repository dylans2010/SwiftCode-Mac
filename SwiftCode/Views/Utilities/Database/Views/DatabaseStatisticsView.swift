import SwiftUI

struct DatabaseStatisticsView: View {
    let databaseName: String
    let tableCount: Int
    let databaseSizeMB: Double

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Database Metrics")
                    .font(.title2.bold())

                HStack(spacing: 16) {
                    MetricStatCard(title: "Database Name", value: databaseName)
                    MetricStatCard(title: "Tables Count", value: "\(tableCount)")
                    MetricStatCard(title: "Size On Disk", value: DatabaseFormatter.formatMB(databaseSizeMB))
                }
            }
            .padding()
        }
    }
}

struct MetricStatCard: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            Text(value)
                .font(.title3.bold())
        }
        .padding()
        .frame(minWidth: 150, alignment: .leading)
        .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
    }
}
