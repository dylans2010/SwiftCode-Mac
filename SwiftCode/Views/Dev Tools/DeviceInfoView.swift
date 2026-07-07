import SwiftUI

struct DeviceInfoView: View {
    var body: some View {
        List {
            Section("System Information") {
                InfoRow(label: "Device Name", value: Host.current().localizedName ?? "Unknown")
                InfoRow(label: "OS Version", value: ProcessInfo.processInfo.operatingSystemVersionString)
                InfoRow(label: "Architecture", value: "arm64")
            }

            Section("Process Information") {
                InfoRow(label: "Process ID", value: "\(ProcessInfo.processInfo.processIdentifier)")
                InfoRow(label: "Process Name", value: ProcessInfo.processInfo.processName)
                InfoRow(label: "Uptime", value: formatUptime(ProcessInfo.processInfo.systemUptime))
            }

            Section("Hardware") {
                InfoRow(label: "Processor Count", value: "\(ProcessInfo.processInfo.processorCount)")
                InfoRow(label: "Memory Size", value: "\(ProcessInfo.processInfo.physicalMemory / 1024 / 1024 / 1024) GB")
            }
        }
        .navigationTitle("Device Info")
    }

    func formatUptime(_ seconds: TimeInterval) -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.day, .hour, .minute, .second]
        formatter.unitsStyle = .full
        return formatter.string(from: seconds) ?? ""
    }
}

struct InfoRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.medium)
        }
    }
}
