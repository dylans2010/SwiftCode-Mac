// Ported from SwiftCode-Legacy (Dylan's own code, MIT-authorised direct port).
// Rebuilt in Ycode style: default accent, no Legacy liquid-glass/orange styling.

import SwiftUI

struct DeviceInfoView: View {
    var body: some View {
        List {
            Section("System Information") {
                DevToolInfoRow(label: "Device Name", value: Host.current().localizedName ?? "Unknown")
                DevToolInfoRow(label: "OS Version", value: ProcessInfo.processInfo.operatingSystemVersionString)
                DevToolInfoRow(label: "Architecture", value: "arm64")
            }

            Section("Process Information") {
                DevToolInfoRow(label: "Process ID", value: "\(ProcessInfo.processInfo.processIdentifier)")
                DevToolInfoRow(label: "Process Name", value: ProcessInfo.processInfo.processName)
                DevToolInfoRow(label: "Uptime", value: formatUptime(ProcessInfo.processInfo.systemUptime))
            }

            Section("Hardware") {
                DevToolInfoRow(label: "Processor Count", value: "\(ProcessInfo.processInfo.processorCount)")
                DevToolInfoRow(label: "Memory Size", value: "\(ProcessInfo.processInfo.physicalMemory / 1024 / 1024 / 1024) GB")
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

struct DevToolInfoRow: View {
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
