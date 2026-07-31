import SwiftUI

struct DatabaseDashboard: View {
    @Binding var selectedSection: DatabaseSection
    @EnvironmentObject var connManager: DatabaseConnectionManager

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header Hero
                VStack(alignment: .leading, spacing: 4) {
                    Text("Database Management Studio")
                        .font(.title.bold())
                    Text("Visually build schemas, trace connections, run SQL analyses, and generate models directly inside SwiftCode.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                // Statistics Summary Grid
                HStack(spacing: 16) {
                    DashboardMetricCard(title: "Active Connections", value: "\(connManager.connections.count)", icon: "cylinder.split.1x2", color: .blue)
                    DashboardMetricCard(title: "Saved Templates", value: "2", icon: "square.stack.3d.up", color: .purple)
                    DashboardMetricCard(title: "Migrations Generated", value: "1", icon: "arrow.triangle.2.circlepath", color: .green)
                }

                // Quick Actions
                GroupBox("Quick Launch Studio Views") {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 180))], spacing: 12) {
                        QuickActionLaunchBtn(title: "Open Tables spreadsheet", icon: "tablecells", color: .blue) {
                            selectedSection = .tables
                        }
                        QuickActionLaunchBtn(title: "Visual Schema canvas", icon: "point.topleft.down.to.point.bottomright.curvepath", color: .orange) {
                            selectedSection = .schemaDesigner
                        }
                        QuickActionLaunchBtn(title: "Interactive SQL Terminal", icon: "terminal", color: .green) {
                            selectedSection = .sqlEditor
                        }
                        QuickActionLaunchBtn(title: "Ask Co-Pilot Architect", icon: "sparkles", color: .purple) {
                            selectedSection = .aiAssistant
                        }
                    }
                    .padding(8)
                }

                // Health Summary Card
                GroupBox("System Status & Cloud Sync") {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.title)
                            .foregroundColor(.green)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Database Engines Operational")
                                .font(.headline)
                            Text("Apple SQLite API binding and PostgREST protocol pipelines are fully connected and functional.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                    }
                    .padding(8)
                }
            }
            .padding(24)
        }
    }
}

struct DashboardMetricCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(value)
                    .font(.title.bold())
            }
            Spacer()
            Image(systemName: icon)
                .font(.title)
                .foregroundColor(color)
        }
        .padding()
        .frame(minWidth: 160)
        .background(Color.secondary.opacity(0.08))
        .cornerRadius(10)
    }
}

struct QuickActionLaunchBtn: View {
    let title: String
    let icon: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(.white)
                    .padding(6)
                    .background(color, in: RoundedRectangle(cornerRadius: 6))

                Text(title)
                    .font(.subheadline)
                    .foregroundColor(.primary)
                Spacer()
            }
            .padding(8)
            .background(Color.secondary.opacity(0.06))
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
    }
}
