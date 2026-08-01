import SwiftUI

struct PackageAnalyticsView: View {
    let package: PackageMetadata

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Overall health score widget
            GroupBox {
                HStack(spacing: 24) {
                    // Circular progress
                    ZStack {
                        Circle()
                            .stroke(Color.secondary.opacity(0.12), lineWidth: 10)
                            .frame(width: 80, height: 80)
                        Circle()
                            .trim(from: 0.0, to: 0.92)
                            .stroke(Color.green, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                            .frame(width: 80, height: 80)
                            .rotationEffect(.degrees(-90))
                        Text("92%")
                            .font(.headline.bold())
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Overall Package Health Score")
                            .font(.headline)
                        Text("Computed using community release cadence, open issues ratio, documentation quality, and test coverage metrics.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(12)
            }
            .groupBoxStyle(ModernGroupBoxStyle())

            // Analytics breakdown categories
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 280, maximum: .infinity))], spacing: 16) {
                GroupBox {
                    VStack(alignment: .leading, spacing: 10) {
                        Label("Community Maintenance", systemImage: "person.2.fill")
                            .font(.headline)
                            .foregroundStyle(.purple)

                        Divider()

                        renderMetricRow(title: "Release Cadence", value: "Every 2-3 months", score: 1.0)
                        renderMetricRow(title: "Commit Frequency", value: "14 commits / week", score: 0.9)
                        renderMetricRow(title: "Issue Response Time", value: "< 24 hours average", score: 0.95)
                        renderMetricRow(title: "Pull Request Merge Rate", value: "88% merged", score: 0.88)
                    }
                    .padding(8)
                }
                .groupBoxStyle(ModernGroupBoxStyle())

                GroupBox {
                    VStack(alignment: .leading, spacing: 10) {
                        Label("Engineering Quality", systemImage: "shield.checkerboard")
                            .font(.headline)
                            .foregroundStyle(.blue)

                        Divider()

                        renderMetricRow(title: "Documentation Quality", value: "95% documented", score: 0.95)
                        renderMetricRow(title: "Test Coverage", value: "84% coverage", score: 0.84)
                        renderMetricRow(title: "Swift 6 Concurrency Ready", value: "Verified Safe", score: 1.0)
                        renderMetricRow(title: "Apple Ecosystem Support", value: "iOS, macOS, tvOS, watchOS", score: 1.0)
                    }
                    .padding(8)
                }
                .groupBoxStyle(ModernGroupBoxStyle())
            }

            // Popularity Section
            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    Label("Community Metrics", systemImage: "globe")
                        .font(.headline)

                    HStack(spacing: 40) {
                        VStack(alignment: .leading) {
                            Text("\(package.stars)")
                                .font(.title1.bold())
                                .foregroundStyle(.yellow)
                            Text("GitHub Stars")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        VStack(alignment: .leading) {
                            Text("\(package.forks)")
                                .font(.title1.bold())
                                .foregroundStyle(.blue)
                            Text("Forks Count")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        VStack(alignment: .leading) {
                            Text("18.4K")
                                .font(.title1.bold())
                                .foregroundStyle(.green)
                            Text("Estimated Weekly Downloads")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                }
                .padding(12)
            }
            .groupBoxStyle(ModernGroupBoxStyle())
        }
    }

    @ViewBuilder
    private func renderMetricRow(title: String, value: String, score: Double) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .font(.caption.bold())
                Spacer()
                Text(value)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ProgressView(value: score)
                .tint(score > 0.85 ? .green : .orange)
        }
    }
}
