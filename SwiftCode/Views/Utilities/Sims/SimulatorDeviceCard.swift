import SwiftUI

/// A modern card representing a single Simulator's characteristics.
public struct SimulatorDeviceCard: View {
    public let device: SimulatorDevice

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "iphone")
                    .font(.title2)
                    .foregroundStyle(device.state == .booted ? .green : .secondary)

                Spacer()

                Circle()
                    .fill(device.state == .booted ? .green : .gray)
                    .frame(width: 8, height: 8)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(device.name)
                    .font(.headline)
                    .lineLimit(1)

                Text(device.runtimeIdentifier?.components(separatedBy: ".").last ?? "iOS 18.0")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(device.state.rawValue)
                    .font(.caption2.bold())
                    .foregroundStyle(device.state == .booted ? .green : .secondary)
            }
        }
        .padding()
        .background(Color(NSColor.windowBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(device.state == .booted ? Color.green.opacity(0.3) : Color.gray.opacity(0.1), lineWidth: 1)
        }
    }
}
