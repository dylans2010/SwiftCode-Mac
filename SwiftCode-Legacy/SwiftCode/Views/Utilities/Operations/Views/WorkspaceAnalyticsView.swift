import SwiftUI

struct WorkspaceAnalyticsView: View {
    @State private var wa = WorkspaceAnalytics.shared
    @State private var wi = WorkspaceIntelligence.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Workspace Analytics & Intelligence")
                            .font(.title2)
                            .fontWeight(.bold)
                        Text("Analyze development patterns, codebase sizes, and intelligence metrics from local project files.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        wi.analyze()
                        wa.refresh()
                    } label: {
                        Label("Re-Analyze Codebases", systemImage: "sparkles")
                    }
                    .buttonStyle(.bordered)
                }
                .padding(.bottom, 10)

                // Intelligence summary card
                GroupBox(label: Text("Workspace Intelligence Insights").font(.headline)) {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 24) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Documentation Coverage")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(String(format: "%.1f%%", wi.docCoverageRatio * 100.0))
                                    .font(.title2)
                                    .fontWeight(.bold)
                                    .foregroundStyle(.blue)
                            }

                            VStack(alignment: .leading, spacing: 4) {
                                Text("Test Coverage Profile")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(String(format: "%.1f%%", wi.testCoverageRatio * 100.0))
                                    .font(.title2)
                                    .fontWeight(.bold)
                                    .foregroundStyle(.purple)
                            }

                            VStack(alignment: .leading, spacing: 4) {
                                Text("Build Trend Pattern")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(wi.buildTrends)
                                    .font(.title2)
                                    .fontWeight(.bold)
                                    .foregroundStyle(.green)
                            }

                            VStack(alignment: .leading, spacing: 4) {
                                Text("Monthly Storage Growth")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(ByteCountFormatter.string(fromByteCount: wi.storageGrowthBytes, countStyle: .file))
                                    .font(.title2)
                                    .fontWeight(.bold)
                                    .foregroundStyle(.orange)
                            }
                        }
                        .padding(.vertical, 8)

                        Divider()

                        // Lists of duplicate sources and shared packages
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Redundancy & Sharing Audits:")
                                .font(.subheadline)
                                .fontWeight(.bold)

                            HStack(alignment: .top, spacing: 20) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Duplicate Swift Files (\(wi.duplicateSourceFiles.count))")
                                        .font(.caption)
                                        .fontWeight(.bold)
                                        .foregroundStyle(.secondary)
                                    if wi.duplicateSourceFiles.isEmpty {
                                        Text("None (Excellent!)")
                                            .font(.caption)
                                            .foregroundStyle(.green)
                                    } else {
                                        ForEach(wi.duplicateSourceFiles.prefix(3), id: \.self) { file in
                                            Text("• \(file)").font(.system(.caption, design: .monospaced))
                                        }
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)

                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Shared Packages Linked (\(wi.sharedPackages.count))")
                                        .font(.caption)
                                        .fontWeight(.bold)
                                        .foregroundStyle(.secondary)
                                    if wi.sharedPackages.isEmpty {
                                        Text("None (No package reuse)")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    } else {
                                        ForEach(wi.sharedPackages.prefix(3), id: \.self) { pkg in
                                            Text("• \(pkg)").font(.system(.caption, design: .monospaced))
                                        }
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                    .padding(6)
                }
                .groupBoxStyle(ModernGroupBoxStyle())

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
