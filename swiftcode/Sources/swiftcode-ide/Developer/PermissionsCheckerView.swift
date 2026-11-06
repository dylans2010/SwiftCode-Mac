// Ported from SwiftCode-Legacy `SwiftCode/Views/Developer/PermissionsCheckerView.swift` (Dylan's own code; direct port authorised under MIT).
// Audit A: MISSING at bc28f653. Static port only — no Swift toolchain here; build verification pending on Dylan's Mac.
import SwiftUI
import SwiftCodeUI

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
        .liquidGlass(style: .subtle, cornerRadius: 12)
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
