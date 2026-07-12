import SwiftUI

struct SimulatorDeviceInformationView: View {
    let device: SimulatorDevice

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Label("Device Specifications", systemImage: "info.circle")
                        .font(.headline)
                        .foregroundColor(.blue)
                    Spacer()
                }

                Divider()

                VStack(spacing: 12) {
                    infoRow(label: "Device Name", value: device.name)
                    infoRow(label: "UDID ID", value: device.udid)
                    infoRow(label: "OS Platform", value: device.platform)
                    infoRow(label: "System OS Version", value: device.osVersion)
                    infoRow(label: "CPU Architecture", value: device.architecture)
                    infoRow(label: "Boot Status", value: device.state.rawValue)
                    infoRow(label: "Storage Cache Path", value: "/Users/developer/Library/Developer/CoreSimulator/Devices/\(device.udid)/data")
                    infoRow(label: "Created Timestamp", value: device.dateCreated.formatted())
                }
            }
            .padding()
        }
        .groupBoxStyle(ModernGroupBoxStyle())
    }

    private func infoRow(label: String, value: String) -> some View {
        HStack(alignment: .top) {
            Text(label)
                .foregroundColor(.secondary)
                .frame(width: 140, alignment: .leading)

            Text(value)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
                .font(.system(.body, design: .monospaced))
        }
        .font(.subheadline)
    }
}
