import SwiftUI

public struct DeviceConnectSessionsView: View {
    @State private var sessionManager = SessionManager.shared
    @State private var historyManager = HistoryManager.shared

    public init() {}

    public var body: some View {
        VStack(spacing: 24) {
            GroupBox {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Label("Deployment Sessions & History", systemImage: "clock.badge.exclamationmark")
                            .font(.headline)
                            .foregroundColor(.purple)
                        Spacer()
                        if !historyManager.historyItems.isEmpty {
                            Button(action: {
                                sessionManager.clearHistory()
                                historyManager.clearHistory()
                            }) {
                                Label("Clear History", systemImage: "trash")
                            }
                            .buttonStyle(.bordered)
                        }
                    }

                    if historyManager.historyItems.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "clock")
                                .font(.system(size: 32))
                                .foregroundStyle(.secondary)
                            Text("No Session History Discovered")
                                .font(.headline)
                            Text("Your previous deployment iterations will be displayed here once run.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 20)
                    } else {
                        VStack(spacing: 12) {
                            ForEach(historyManager.historyItems) { item in
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack {
                                        Text("Project: \(item.projectName)")
                                            .font(.subheadline.weight(.bold))
                                        Spacer()
                                        Text(formattedDate(item.timestamp))
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }

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
                                .padding()
                                .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                        }
                    }
                }
                .padding()
            }
            .groupBoxStyle(ModernGroupBoxStyle())
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
