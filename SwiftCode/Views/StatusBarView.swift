import SwiftUI

struct StatusBarView: View {
    @State var workspace: WorkspaceViewModel

    var body: some View {
        HStack {
            if let status = workspace.git.status {
                Label(status.branchName, systemImage: "branch")
                Text("↑\(status.ahead) ↓\(status.behind)")
            }
            Spacer()
            if workspace.build.isBuilding {
                ProgressView().controlSize(.small)
                Text("Building...")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .font(.caption)
        .background(Color.secondary.opacity(0.1))
    }
}
