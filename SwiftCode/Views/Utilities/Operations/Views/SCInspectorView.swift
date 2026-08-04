import SwiftUI

struct SCInspectorView: View {
    @State private var coord = OperationsCoordinator.shared
    @State private var health = WorkspaceHealth.shared
    @State private var storage = StorageManager.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                // Title
                HStack {
                    Image(systemName: "info.circle.fill")
                        .foregroundStyle(.blue)
                    Text("Workspace Inspector")
                        .font(.headline)
                    Spacer()
                }

                Divider()

                // System Specs
                VStack(alignment: .leading, spacing: 10) {
                    Text("Environment")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundStyle(.secondary)

                    SCDetailRow(label: "Operating System", value: "macOS 15.0")
                    SCDetailRow(label: "Architecture", value: "Apple Silicon (ARM64)")
                    SCDetailRow(label: "Developer SDK", value: "macosx15.0")
                    SCDetailRow(label: "IDE Edition", value: "SwiftCode Premium 1.0")
                }

                Divider()

                // Health rating
                VStack(alignment: .leading, spacing: 10) {
                    Text("Workspace Integrity")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundStyle(.secondary)

                    SCDetailRow(label: "Health Score", value: "\(health.healthScore)%")
                    SCDetailRow(label: "Rating", value: health.rating)
                    SCDetailRow(label: "Disk Free Size", value: String(format: "%.1f GB", storage.totalSystemFreeGB))
                }

                Divider()

                // Quick actions
                VStack(alignment: .leading, spacing: 10) {
                    Text("Operations Actions")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundStyle(.secondary)

                    Button("View Log Streams") {
                        coord.selectPanel(.logs)
                    }
                    .buttonStyle(.bordered)
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Button("Review Notifications") {
                        coord.selectPanel(.notifications)
                    }
                    .buttonStyle(.bordered)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(16)
        }
        .frame(minWidth: 240, maxWidth: .infinity)
        .background(Color(NSColor.windowBackgroundColor))
    }
}
