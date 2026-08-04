import SwiftUI

struct WorkspaceHealthView: View {
    @State private var health = WorkspaceHealth.shared
    @State private var wi = WorkspaceIntelligence.shared
    @State private var dm = DiagnosticsManager.shared
    @State private var sec = SecurityManager.shared
    @State private var bhm = BuildHistoryManager.shared
    @State private var storage = SCOperationsStorageManager.shared
    @State private var sign = SCOperationsSigningManager.shared
    @State private var perf = PerformanceManager.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header
                VStack(alignment: .leading, spacing: 4) {
                    Text("Workspace Health Score")
                        .font(.title2)
                        .fontWeight(.bold)
                    Text("Comprehensive workstation integrity index tracking diagnostic errors, security findings, and compilation telemetry.")
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

                            Text("Computed using real-time factors across all active workspaces. To maximize score, resolve high-severity issues, maintain documentation, and ensure build success rates remain stable.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(12)
                }
                .groupBoxStyle(ModernGroupBoxStyle())

                // 10 Scoring factors breakdown
                GroupBox {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("Scoring Factors Breakdown (10 Core Parameters)")
                            .font(.headline)
                            .padding(.bottom, 4)

                        // 1. Build Health
                        let failedBuilds = bhm.buildRecords.filter { $0.status == "Failed" }.count
                        HealthFactorRow(
                            title: "Build Health",
                            detail: failedBuilds == 0 ? "All compiles succeeded" : "\(failedBuilds) failed builds detected",
                            status: failedBuilds == 0 ? "Excellent" : "Action Required",
                            isHealthy: failedBuilds == 0
                        )

                        Divider()

                        // 2. Package Health
                        let packageIssues = DependencyManager.shared.dependencies.filter { $0.status == "Update Available" }.count
                        HealthFactorRow(
                            title: "Package Health",
                            detail: packageIssues == 0 ? "All Swift packages up-to-date" : "\(packageIssues) package updates available",
                            status: packageIssues == 0 ? "Healthy" : "Updates Available",
                            isHealthy: packageIssues == 0
                        )

                        Divider()

                        // 3. Storage
                        let isStorageLow = storage.totalSystemFreeGB < 10.0
                        HealthFactorRow(
                            title: "Storage Footprint",
                            detail: "Host has \(String(format: "%.1f GB", storage.totalSystemFreeGB)) free disk space",
                            status: isStorageLow ? "Low Space" : "Optimized",
                            isHealthy: !isStorageLow
                        )

                        Divider()

                        // 4. Diagnostics Integrity
                        HealthFactorRow(
                            title: "Diagnostics Integrity",
                            detail: "\(dm.issues.count) compiler reference issues flagged",
                            status: dm.issues.isEmpty ? "Secured" : "Needs Review",
                            isHealthy: dm.issues.isEmpty
                        )

                        Divider()

                        // 5. Security & Credentials
                        let criticalSec = sec.findings.filter { $0.severity == "Critical" }.count
                        HealthFactorRow(
                            title: "Security Scan",
                            detail: "\(criticalSec) hardcoded key risk findings",
                            status: criticalSec == 0 ? "Protected" : "Vulnerable",
                            isHealthy: criticalSec == 0
                        )

                        Divider()

                        // 6. Signing & Certificates
                        let invalidCerts = sign.certificates.filter { !$0.isValid }.count
                        HealthFactorRow(
                            title: "Signing Profiles",
                            detail: invalidCerts == 0 ? "Developer certificates valid" : "Certificates expired",
                            status: invalidCerts == 0 ? "Valid" : "Expired",
                            isHealthy: invalidCerts == 0
                        )

                        Divider()

                        // 7. Documentation
                        let docHealthy = wi.docCoverageRatio >= 0.6
                        HealthFactorRow(
                            title: "Documentation Coverage",
                            detail: String(format: "%.1f%% documentation coverage ratio", wi.docCoverageRatio * 100.0),
                            status: docHealthy ? "Compliant" : "Needs Docs",
                            isHealthy: docHealthy
                        )

                        Divider()

                        // 8. Testing Integrity
                        let testHealthy = wi.testCoverageRatio >= 0.5
                        HealthFactorRow(
                            title: "Testing Integrity",
                            detail: String(format: "%.1f%% test coverage profile mapped", wi.testCoverageRatio * 100.0),
                            status: testHealthy ? "Stable" : "Incomplete",
                            isHealthy: testHealthy
                        )

                        Divider()

                        // 9. Build Stability
                        HealthFactorRow(
                            title: "Build Stability",
                            detail: "Tracked compile success profiles across targets",
                            status: failedBuilds < 2 ? "High Stability" : "Degraded",
                            isHealthy: failedBuilds < 2
                        )

                        Divider()

                        // 10. Compile Performance
                        let perfHealthy = perf.averageBuildDuration < 8.0
                        HealthFactorRow(
                            title: "Workstation Performance",
                            detail: String(format: "Average build speed: %.1f seconds", perf.averageBuildDuration),
                            status: perfHealthy ? "Excellent" : "Slow Builds",
                            isHealthy: perfHealthy
                        )
                    }
                    .padding(8)
                }
                .groupBoxStyle(ModernGroupBoxStyle())
            }
            .padding(24)
        }
        .onAppear {
            wi.analyze()
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
