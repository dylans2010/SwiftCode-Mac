import SwiftUI

struct StorageManagerView: View {
    @State private var sm = StorageManager.shared
    @State private var isCleaningDerived = false
    @State private var isCleaningCaches = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header
                VStack(alignment: .leading, spacing: 4) {
                    Text("Storage Manager")
                        .font(.title2)
                        .fontWeight(.bold)
                    Text("Audit disk space allocated to build artifacts, cached dependencies, and project binaries.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.bottom, 10)

                // Large visualization chart
                GroupBox {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("Workspace Disk Footprint")
                            .font(.headline)

                        let totalAllocated = sm.projectUsageGB + sm.derivedDataGB + sm.cacheUsageGB + sm.vmUsageGB + sm.archiveUsageGB + sm.logUsageGB + sm.backupUsageGB

                        HStack {
                            Text(String(format: "Total Allocated: %.2f GB", totalAllocated))
                                .font(.title3)
                                .fontWeight(.bold)
                            Spacer()
                            Text(String(format: "Free Space: %.1f GB", sm.totalSystemFreeGB))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }

                        // visual multi-color bar chart
                        GeometryReader { geo in
                            HStack(spacing: 0) {
                                Color.blue.frame(width: max(0, CGFloat(sm.projectUsageGB / totalAllocated) * geo.size.width))
                                Color.orange.frame(width: max(0, CGFloat(sm.derivedDataGB / totalAllocated) * geo.size.width))
                                Color.green.frame(width: max(0, CGFloat(sm.cacheUsageGB / totalAllocated) * geo.size.width))
                                Color.purple.frame(width: max(0, CGFloat(sm.archiveUsageGB / totalAllocated) * geo.size.width))
                                Color.gray.frame(width: max(0, CGFloat((sm.logUsageGB + sm.backupUsageGB) / totalAllocated) * geo.size.width))
                            }
                            .cornerRadius(6)
                        }
                        .frame(height: 16)

                        // Legend
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                            LegendRow(color: .blue, label: "Projects", sizeGB: sm.projectUsageGB)
                            LegendRow(color: .orange, label: "Derived Data", sizeGB: sm.derivedDataGB)
                            LegendRow(color: .green, label: "Caches", sizeGB: sm.cacheUsageGB)
                            LegendRow(color: .purple, label: "Archives", sizeGB: sm.archiveUsageGB)
                            LegendRow(color: .gray, label: "Logs & Backups", sizeGB: sm.logUsageGB + sm.backupUsageGB)
                        }
                    }
                    .padding(8)
                }
                .groupBoxStyle(ModernGroupBoxStyle())

                // Clean-up actions card
                GroupBox {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("Maintenance & Space Saver")
                            .font(.headline)
                            .padding(.bottom, 4)

                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Clean Derived Data & Artifacts")
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                Text("Purges local build databases and cached binary assets. Safe to run anytime.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button {
                                isCleaningDerived = true
                                sm.cleanDerivedData()
                                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                                    isCleaningDerived = false
                                }
                            } label: {
                                Text(isCleaningDerived ? "Cleaning..." : "Purge Derived Data")
                            }
                            .buttonStyle(.bordered)
                            .disabled(isCleaningDerived)
                        }

                        Divider()

                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Purge Global Package Caches")
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                Text("Deletes index structures and downloaded packages under Xcode directories.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button {
                                isCleaningCaches = true
                                sm.cleanCaches()
                                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                                    isCleaningCaches = false
                                }
                            } label: {
                                Text(isCleaningCaches ? "Cleaning..." : "Clear Caches")
                            }
                            .buttonStyle(.bordered)
                            .disabled(isCleaningCaches)
                        }
                    }
                    .padding(8)
                }
                .groupBoxStyle(ModernGroupBoxStyle())
            }
            .padding(24)
        }
        .onAppear {
            sm.recalculateSizes()
        }
    }
}

private struct LegendRow: View {
    let color: Color
    let label: String
    let sizeGB: Double

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Text(String(format: "%.2f GB", sizeGB))
                .font(.caption)
                .fontWeight(.medium)
        }
    }
}
