import SwiftUI

struct WorkspaceAnalyticsView: View {
    @State private var wa = WorkspaceAnalytics.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header
                VStack(alignment: .leading, spacing: 4) {
                    Text("Workspace Analytics")
                        .font(.title2)
                        .fontWeight(.bold)
                    Text("Analyze trends, codebase sizes, and historical metrics from local project structures.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.bottom, 10)

                // Large cards grid
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                    GroupBox {
                        VStack(alignment: .leading, spacing: 10) {
                            Label("Lines of Code (LOC)", systemImage: "text.alignleft")
                                .font(.headline)
                                .foregroundStyle(.blue)

                            Text("\(wa.totalLinesOfCode)")
                                .font(.system(size: 32, weight: .bold))

                            Text("Scanned recursively across Swift files in active workspace.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(8)
                    }
                    .groupBoxStyle(ModernGroupBoxStyle())

                    GroupBox {
                        VStack(alignment: .leading, spacing: 10) {
                            Label("Build Success Ratio", systemImage: "checkmark.circle")
                                .font(.headline)
                                .foregroundStyle(.green)

                            Text(String(format: "%.1f%%", wa.averageBuildSuccessRate))
                                .font(.system(size: 32, weight: .bold))

                            Text("Percentage of compilation executions returning successful codes.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(8)
                    }
                    .groupBoxStyle(ModernGroupBoxStyle())

                    GroupBox {
                        VStack(alignment: .leading, spacing: 10) {
                            Label("Managed Code Repositories", systemImage: "folder")
                                .font(.headline)
                                .foregroundStyle(.orange)

                            Text("\(wa.totalProjects)")
                                .font(.system(size: 32, weight: .bold))

                            Text("Number of workspaces registered under the Project Registry.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(8)
                    }
                    .groupBoxStyle(ModernGroupBoxStyle())

                    GroupBox {
                        VStack(alignment: .leading, spacing: 10) {
                            Label("App Bundle Archives", systemImage: "shippingbox")
                                .font(.headline)
                                .foregroundStyle(.purple)

                            Text("\(wa.totalArchives)")
                                .font(.system(size: 32, weight: .bold))

                            Text("Total number of release archives created in this environment.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(8)
                    }
                    .groupBoxStyle(ModernGroupBoxStyle())
                }
            }
            .padding(24)
        }
        .onAppear {
            wa.refresh()
        }
    }
}
