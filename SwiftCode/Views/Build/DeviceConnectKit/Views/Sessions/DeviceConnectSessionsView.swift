import SwiftUI

public struct DeviceConnectSessionsView: View {
    @State private var sessionManager = SessionManager.shared
    @State private var historyManager = HistoryManager.shared

    public init() {}

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Deployment Sessions & History")
                            .font(.title2.weight(.bold))
                        Text("Audit and review previous build, deployment, and run sessions.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(action: {
                        sessionManager.clearHistory()
                        historyManager.clearHistory()
                    }) {
                        Label("Clear History", systemImage: "trash")
                    }
                    .buttonStyle(.bordered)
                }

                // History List Rendered in GroupBoxes
                if historyManager.historyItems.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "clock.badge.exclamationmark")
                            .font(.system(size: 32))
                            .foregroundStyle(.secondary)
                        Text("No Session History Discovered")
                            .font(.headline)
                        Text("Your previous deployment iterations will be displayed here once ran.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
                } else {
                    ForEach(historyManager.historyItems) { item in
                        GroupBox(label: HStack {
                            Text("Project: \(item.projectName)")
                                .font(.subheadline.weight(.bold))
                            Spacer()
                            Text(formattedDate(item.timestamp))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }) {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Label("Target: \(item.deviceName)", systemImage: "iphone")
                                        .font(.subheadline)
                                    Spacer()
                                    Label(String(format: "%.1fs", item.duration), systemImage: "stopwatch")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }

                                Divider()

                                HStack(spacing: 12) {
                                    StatusBadgePair(label: "Build", status: item.buildResult.rawValue)
                                    StatusBadgePair(label: "Deploy", status: item.deployResult.rawValue)
                                    StatusBadgePair(label: "Runtime", status: item.runResult.rawValue)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                        .groupBoxStyle(ModernGroupBoxStyle())
                    }
                }
            }
            .padding()
        }
    }

    private func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

struct StatusBadgePair: View {
    let label: String
    let status: String

    var body: some View {
        HStack(spacing: 4) {
            Text("\(label):")
                .font(.caption)
                .foregroundStyle(.secondary)
            DeviceStatusBadge(status: status)
        }
    }
}
