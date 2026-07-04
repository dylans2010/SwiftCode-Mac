import SwiftUI

struct GitHubWorkflowsSidebarView: View {
    var body: some View {
        VStack {
            List {
                Section("Actions") {
                    Text("No workflows found")
                        .foregroundStyle(.secondary)
                }
            }

            Button("Refresh Workflows") {
                // Refresh
            }
            .buttonStyle(.bordered)
            .padding()
        }
    }
}
