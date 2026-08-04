import SwiftUI

struct WorkspaceHealthView: View {
    @State private var health = WorkspaceHealth.shared
    @State private var dm = DiagnosticsManager.shared
    @State private var sec = SecurityManager.shared
    @State private var bhm = BuildHistoryManager.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header
                VStack(alignment: .leading, spacing: 4) {
                    Text("Workspace Health Score")
                        .font(.title2)
                        .fontWeight(.bold)
                    Text("Comprehensive integrity index tracking diagnostic errors, security findings, and compilation telemetry.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.bottom, 10)

                // Large circle dial chart
                GroupBox {
                    HStack(spacing: 30) {
                        ZStack {
                            Circle()
                                .stroke(Color.secondary.opacity(0.15), lineWidth: 16)
                                .frame(width: 130, height: 130)

                            Circle()
                                .trim(from: 0.0, to: CGFloat(health.healthScore) / 100.0)
                                .stroke(colorForScore(health.healthScore), style: StrokeStyle(lineWidth: 16, lineCap: .round))
                                .frame(width: 130, height: 130)
                                .rotationEffect(.degrees(-90))

                            VStack(spacing: 4) {
                                Text("\(health.healthScore)")
                                    .font(.system(size: 34, weight: .bold))
                                Text("Score")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 10)

                        VStack(alignment: .leading, spacing: 10) {
                            Text("Health Status: **\(health.rating)**")
                                .font(.title3)
                                .foregroundStyle(colorForScore(health.healthScore))

                            Text("Computed using real-time factors across all active workspaces. To maximize score, resolve high-severity issues and ensure build success rates remain stable.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(12)
                }
                .groupBoxStyle(ModernGroupBoxStyle())

                // Scoring factors
                GroupBox {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("Scoring Factors Breakdown")
                            .font(.headline)
                            .padding(.bottom, 4)

                        HealthFactorRow(
                            title: "Diagnostics Integrity",
                            detail: "\(dm.issues.count) issues flagged in scan",
                            status: dm.issues.isEmpty ? "Healthy" : "Needs Attention",
                            isHealthy: dm.issues.isEmpty
                        )

                        Divider()

                        let criticalSec = sec.findings.filter { $0.severity == "Critical" }.count
                        HealthFactorRow(
                            title: "Security & Credentials",
                            detail: "\(criticalSec) hardcoded key warnings",
                            status: criticalSec == 0 ? "Secured" : "Vulnerable",
                            isHealthy: criticalSec == 0
                        )

                        Divider()

                        let failedBuilds = bhm.buildRecords.filter { $0.status == "Failed" }.count
                        HealthFactorRow(
                            title: "Build Success Ratio",
                            detail: "\(failedBuilds) failed compilation events recorded",
                            status: failedBuilds == 0 ? "Stable" : "Degraded",
                            isHealthy: failedBuilds == 0
                        )
                    }
                    .padding(8)
                }
                .groupBoxStyle(ModernGroupBoxStyle())
            }
            .padding(24)
        }
        .onAppear {
            health.recompute()
        }
    }

    private func colorForScore(_ score: Int) -> Color {
        if score >= 90 { return .green }
        if score >= 70 { return .orange }
        return .red
    }
}

private struct HealthFactorRow: View {
    let title: String
    let detail: String
    let status: String
    let isHealthy: Bool

    var body: some View {
        HStack {
            Image(systemName: isHealthy ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(isHealthy ? .green : .orange)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text(status)
                .font(.caption)
                .fontWeight(.bold)
                .foregroundStyle(isHealthy ? .green : .orange)
        }
    }
}
