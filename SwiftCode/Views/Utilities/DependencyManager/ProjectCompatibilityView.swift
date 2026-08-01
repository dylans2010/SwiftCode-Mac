import SwiftUI

struct ProjectCompatibilityView: View {
    let packageUrl: String

    @Environment(ProjectSessionStore.self) private var sessionStore
    @State private var platformManager = DependencyPlatformManager.shared

    var body: some View {
        let activeProj = sessionStore.activeProject
        let report = platformManager.analyzeCompatibility(packageUrl: packageUrl, activeProject: activeProj)

        VStack(alignment: .leading, spacing: 18) {
            Label("Active Project Compatibility Score", systemImage: "checklist.checked")
                .font(.headline)
                .foregroundStyle(.blue)

            HStack(spacing: 20) {
                // Circular progress score
                ZStack {
                    Circle()
                        .stroke(Color.secondary.opacity(0.12), lineWidth: 8)
                        .frame(width: 70, height: 70)
                    Circle()
                        .trim(from: 0.0, to: CGFloat(report.healthScore) / 100.0)
                        .stroke(report.healthScore > 80 ? Color.green : Color.orange, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                        .frame(width: 70, height: 70)
                        .rotationEffect(.degrees(-90))
                    Text("\(report.healthScore)%")
                        .font(.subheadline.bold())
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Compatibility Status")
                        .font(.headline)
                    Text("This package complies with your workspace compiler targets and concurrency checking configuration.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding()
            .background(Color.secondary.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))

            Divider()

            // Requirements Checklist
            VStack(alignment: .leading, spacing: 12) {
                Text("Ecosystem Requirements checklist")
                    .font(.subheadline.bold())

                HStack {
                    Image(systemName: report.swiftVersionMatch ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(report.swiftVersionMatch ? .green : .orange)
                    Text("Swift Version Compliance (Strict Concurrency)")
                        .font(.caption)
                    Spacer()
                    Text("Swift 6.0")
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Image(systemName: report.toolsVersionMatch ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(report.toolsVersionMatch ? .green : .orange)
                    Text("Tools Manifest Version Match")
                        .font(.caption)
                    Spacer()
                    Text(">= 5.9")
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Image(systemName: report.platformSupportMatch ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(report.platformSupportMatch ? .green : .orange)
                    Text("Target Deployment Platforms Check")
                        .font(.caption)
                    Spacer()
                    Text("iOS 17.0+ / macOS 14.0+")
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                }
            }

            Divider()

            // Actionable Recommendations
            VStack(alignment: .leading, spacing: 12) {
                Text("Actionable Recommendations")
                    .font(.subheadline.bold())
                    .foregroundStyle(.orange)

                ForEach(report.recommendations, id: \.self) { rec in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "arrow.right.circle.fill")
                            .foregroundStyle(.orange)
                            .font(.caption)
                            .padding(.top, 2)
                        Text(rec)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}
