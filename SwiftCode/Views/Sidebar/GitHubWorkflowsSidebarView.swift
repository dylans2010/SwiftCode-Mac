import SwiftUI

struct GitHubWorkflowsSidebarView: View {
    @State private var workflows: [GitHubWorkflow] = []
    @State private var isRefreshing = false

    var body: some View {
        VStack(spacing: 0) {
            List {
                Section("Workflows") {
                    if workflows.isEmpty {
                        Text("No workflows found")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(workflows) { workflow in
                            VStack(alignment: .leading) {
                                Text(workflow.name).font(.headline)
                                Text(workflow.path).font(.caption).foregroundColor(.secondary)
                            }
                        }
                    }
                }
            }

            Button(action: refreshWorkflows) {
                if isRefreshing {
                    ProgressView().controlSize(.small)
                } else {
                    Label("Refresh Workflows", systemImage: "arrow.clockwise")
                }
            }
            .disabled(isRefreshing)
            .buttonStyle(.bordered)
            .padding()
        }
        .onAppear {
            refreshWorkflows()
        }
    }

    private func refreshWorkflows() {
        isRefreshing = true
        Task {
            let projectRoot = FileManager.default.currentDirectoryPath
            let workflowsDir = URL(fileURLWithPath: projectRoot).appendingPathComponent(".github/workflows")

            do {
                let contents = try FileManager.default.contentsOfDirectory(at: workflowsDir, includingPropertiesForKeys: nil)
                workflows = contents.filter { $0.pathExtension == "yml" || $0.pathExtension == "yaml" }.map { url in
                    GitHubWorkflow(name: url.lastPathComponent, path: url.path)
                }
            } catch {
                print("Failed to load workflows: \(error)")
                workflows = []
            }
            isRefreshing = false
        }
    }
}

struct GitHubWorkflow: Identifiable {
    let id = UUID()
    let name: String
    let path: String
}
