import SwiftUI

struct OperationsDashboardView: View {
    @State private var coord = OperationsCoordinator.shared
    @State private var health = WorkspaceHealth.shared
    @State private var registry = ProjectRegistryManager.shared
    @State private var builds = BuildHistoryManager.shared
    @State private var storage = SCOperationsStorageManager.shared
    @State private var security = SecurityManager.shared
    @State private var queue = OperationQueueManager.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header Banner
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Operational Command Center")
                            .font(.system(size: 24, weight: .bold))
                        Text("Monitor, manage, and optimize your desktop developer workflow.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()

                    // Quick run rescan
                    Button {
                        triggerSystemRescan()
                    } label: {
                        Label("Rescan Workspace", systemImage: "arrow.clockwise")
                            .font(.headline)
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(.bottom, 10)

                // Top Metrics row (Health, Storage, Active Operations)
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                    // 1. Health card
                    GroupBox {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Label("Workspace Health", systemImage: "heart.text.square.fill")
                                    .font(.headline)
                                    .foregroundStyle(.red)
                                Spacer()
                                Text("\(health.healthScore)%")
                                    .font(.system(size: 22, weight: .bold))
                                    .foregroundStyle(health.healthScore >= 80 ? .green : .orange)
                            }

                            Text("Current State: **\(health.rating)**")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)

                            ProgressView(value: Double(health.healthScore), total: 100)
                                .tint(health.healthScore >= 80 ? .green : .orange)

                            Button("Explore Diagnostics") {
                                coord.selectPanel(.health)
                            }
                            .buttonStyle(.link)
                        }
                        .padding(4)
                    }
                    .groupBoxStyle(ModernGroupBoxStyle())

                    // 2. Storage Summary
                    GroupBox {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Label("Storage Breakdown", systemImage: "externaldrive.fill")
                                    .font(.headline)
                                    .foregroundStyle(.blue)
                                Spacer()
                                Text(String(format: "%.2f GB", storage.projectUsageGB + storage.derivedDataGB))
                                    .font(.system(size: 16, weight: .semibold))
                            }

                            Text("Free Disk space: **\(String(format: "%.1f GB", storage.totalSystemFreeGB))**")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            HStack {
                                CapsuleProgressSegment(label: "Projects", value: storage.projectUsageGB, total: 5.0, color: .blue)
                                CapsuleProgressSegment(label: "DerivedData", value: storage.derivedDataGB, total: 5.0, color: .orange)
                            }

                            Button("Clean Artifacts") {
                                coord.selectPanel(.storage)
                            }
                            .buttonStyle(.link)
                        }
                        .padding(4)
                    }
                    .groupBoxStyle(ModernGroupBoxStyle())

                    // 3. Queue Tasks
                    GroupBox {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Label("Operational Queue", systemImage: "list.bullet.rectangle.fill")
                                    .font(.headline)
                                    .foregroundStyle(.purple)
                                Spacer()
                                Text("\(coord.activeTaskCount) Active")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundStyle(coord.activeTaskCount > 0 ? .purple : .secondary)
                            }

                            if queue.tasks.isEmpty {
                                Text("No background compile tasks.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            } else {
                                VStack(alignment: .leading, spacing: 4) {
                                    ForEach(queue.tasks.suffix(2)) { task in
                                        HStack {
                                            Text(task.name)
                                                .font(.caption2)
                                                .lineLimit(1)
                                            Spacer()
                                            Text(task.status)
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                }
                            }

                            Button("Manage Queue") {
                                coord.selectPanel(.queue)
                            }
                            .buttonStyle(.link)
                        }
                        .padding(4)
                    }
                    .groupBoxStyle(ModernGroupBoxStyle())
                }

                // Recent Projects and Recent Builds
                HStack(alignment: .top, spacing: 16) {
                    // Recent Projects Card
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Recent Projects")
                                .font(.title3)
                                .fontWeight(.bold)
                            Spacer()
                            Button("Registry") {
                                coord.selectPanel(.projectRegistry)
                            }
                            .buttonStyle(.link)
                        }

                        if registry.registryEntries.isEmpty {
                            VStack(spacing: 8) {
                                Image(systemName: "folder.badge.questionmark")
                                    .font(.largeTitle)
                                    .foregroundStyle(.secondary)
                                Text("No registered SwiftCode projects yet.")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 30)
                            .background(RoundedRectangle(cornerRadius: 8).fill(Color(NSColor.underPageBackgroundColor)))
                        } else {
                            VStack(spacing: 8) {
                                ForEach(registry.registryEntries.prefix(4)) { entry in
                                    HStack {
                                        Image(systemName: "folder.fill")
                                            .foregroundStyle(.orange)
                                        VStack(alignment: .leading) {
                                            Text(entry.name)
                                                .font(.system(size: 13, weight: .medium))
                                            Text(entry.rootURL.path)
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                                .lineLimit(1)
                                        }
                                        Spacer()
                                        Button("Open") {
                                            registry.openProject(entry)
                                        }
                                        .buttonStyle(.bordered)
                                    }
                                    .padding(.vertical, 4)
                                    Divider()
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color(NSColor.windowBackgroundColor)))

                    // Recent Builds Card
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Latest Builds")
                                .font(.title3)
                                .fontWeight(.bold)
                            Spacer()
                            Button("History") {
                                coord.selectPanel(.buildHistory)
                            }
                            .buttonStyle(.link)
                        }

                        if builds.buildRecords.isEmpty {
                            VStack(spacing: 8) {
                                Image(systemName: "clock.badge")
                                    .font(.largeTitle)
                                    .foregroundStyle(.secondary)
                                Text("No builds performed in this session.")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 30)
                            .background(RoundedRectangle(cornerRadius: 8).fill(Color(NSColor.underPageBackgroundColor)))
                        } else {
                            VStack(spacing: 8) {
                                ForEach(builds.buildRecords.prefix(4)) { record in
                                    HStack {
                                        Image(systemName: record.status == "Succeeded" ? "checkmark.circle.fill" : "xmark.circle.fill")
                                            .foregroundStyle(record.status == "Succeeded" ? .green : .red)
                                        VStack(alignment: .leading) {
                                            Text(record.projectName)
                                                .font(.system(size: 13, weight: .medium))
                                            Text("\(record.configuration) • \(record.sdk)")
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                        Text(String(format: "%.1fs", record.duration))
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    .padding(.vertical, 4)
                                    Divider()
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color(NSColor.windowBackgroundColor)))
                }
            }
            .padding(24)
        }
    }

    private func triggerSystemRescan() {
        OperationQueueManager.shared.enqueueTask(name: "Full Workspace Integrity Scan") {
            await DiagnosticsManager.shared.scanWorkspace()
            await SecurityManager.shared.runAudit()
            await AIEngineeringReports.shared.generateReport()
            WorkspaceAnalytics.shared.refresh()
            SCOperationsStorageManager.shared.recalculateSizes()
        }
    }
}

private struct CapsuleProgressSegment: View {
    let label: String
    let value: Double
    let total: Double
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            ProgressView(value: min(value, total), total: total)
                .tint(color)
        }
    }
}
