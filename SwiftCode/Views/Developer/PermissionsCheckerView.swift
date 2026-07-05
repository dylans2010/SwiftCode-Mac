import SwiftUI

struct PermissionsCheckerView: View {
    let permissions = [
        PermissionInfo(name: "Camera", status: "Authorized", icon: "camera.fill"),
        PermissionInfo(name: "Notifications", status: "Denied", icon: "bell.badge.fill"),
        PermissionInfo(name: "Network", status: "Authorized", icon: "network"),
        PermissionInfo(name: "Local Storage", status: "Authorized", icon: "hdd.fill"),
        PermissionInfo(name: "Microphone", status: "Not Determined", icon: "mic.fill")
    ]

    var body: some View {
        List(permissions) { perm in
            HStack {
                Label(perm.name, systemImage: perm.icon)
                Spacer()
                Text(perm.status)
                    .font(.caption)
                    .foregroundStyle(colorForStatus(perm.status))
            }
        }
        .navigationTitle("Permissions")
    }

    private func colorForStatus(_ status: String) -> Color {
        switch status {
        case "Authorized": return .green
        case "Denied": return .red
        default: return .secondary
        }
    }
}

struct PermissionInfo: Identifiable {
    let id = UUID()
    let name: String
    let status: String
    let icon: String
}
