import SwiftUI

struct DeviceStatusBadge: View {
    let status: String

    var body: some View {
        Text(status)
            .font(.caption2.weight(.bold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(backgroundColor.opacity(0.15))
            .foregroundStyle(backgroundColor)
            .clipShape(Capsule())
    }

    private var backgroundColor: Color {
        switch status.lowercased() {
        case "ready", "running", "succeeded", "completed", "valid signing":
            return .green
        case "building", "installing", "launching", "verifying", "saving project", "validating environment":
            return .blue
        case "busy":
            return .orange
        case "failed", "crashed", "error", "invalid profile/certificate", "expired provisioning":
            return .red
        default:
            return .secondary
        }
    }
}

struct DeviceConnectHeader: View {
    let title: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.title3)
                .foregroundStyle(.blue)
            Text(title)
                .font(.headline)
            Spacer()
        }
        .padding(.vertical, 4)
    }
}
