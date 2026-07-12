import SwiftUI

struct SimulatorDeviceCard: View {
    let device: SimulatorDevice
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(statusColor.opacity(0.15))
                    .frame(width: 36, height: 36)

                Image(systemName: platformIcon)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(statusColor)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(device.name)
                    .font(.headline)
                    .lineLimit(1)

                HStack(spacing: 8) {
                    Text("\(device.platform) \(device.osVersion)")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Text("•")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Text(device.state.rawValue)
                        .font(.caption.weight(.semibold))
                        .foregroundColor(statusColor)
                }
            }

            Spacer()

            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.accentColor)
                    .imageScale(.large)
            }
        }
        .padding(12)
        .background(isSelected ? Color.accentColor.opacity(0.1) : Color.secondary.opacity(0.05))
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 1.5)
        )
    }

    private var platformIcon: String {
        switch device.platform.lowercased() {
        case "ios", "iphone": return "iphone"
        case "ipad": return "ipad"
        case "watchos", "watch": return "applewatch"
        case "tvos", "tv": return "appletv"
        case "visionos", "vision": return "visionpro"
        default: return "laptopcomputer"
        }
    }

    private var statusColor: Color {
        switch device.state {
        case .booted: return .green
        case .booting: return .orange
        case .shuttingDown: return .blue
        case .shutdown: return .secondary
        case .erasing: return .red
        default: return .secondary
        }
    }
}
