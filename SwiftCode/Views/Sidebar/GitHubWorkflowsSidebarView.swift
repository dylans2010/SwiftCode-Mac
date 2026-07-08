import SwiftUI

struct GitHubWorkflowsSidebarView: View {
    @State private var workflows: [GitHubWorkflow] = []
    @State private var isRefreshing = false
    @State private var selectedWorkflow: GitHubWorkflow?
    @State private var editingContent = ""
    @Environment(WorkspaceViewModel.self) var workspaceVM

    var body: some View {
        VStack(spacing: 0) {
            List {
                Section("Workflows") {
                    if workflows.isEmpty {
                        Text("No workflows found")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(workflows) { workflow in
                            Button(action: { openWorkflow(workflow) }) {
                                VStack(alignment: .leading) {
                                    Text(workflow.name).font(.headline)
                                    Text(workflow.path).font(.caption).foregroundColor(.secondary)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }

            HStack {
                Button(action: createNewWorkflow) {
                    Label("New Workflow", systemImage: "plus")
                }
                .buttonStyle(.bordered)

                Spacer()

                Button(action: refreshWorkflows) {
                    if isRefreshing {
                        ProgressView().controlSize(.small)
                    } else {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                }
                .disabled(isRefreshing)
                .buttonStyle(.bordered)
            }
            .padding()
        }
        .sheet(item: $selectedWorkflow) { workflow in
            WorkflowEditorView(content: $editingContent, fileName: workflow.name) { newContent in
                saveWorkflow(workflow, content: newContent)
                selectedWorkflow = nil
            }
            .frame(minWidth: 600, minHeight: 400)
        }
        .onAppear {
            refreshWorkflows()
        }
        .macDesktopOptimized()
    }

    private func refreshWorkflows() {
        isRefreshing = true
        Task {
            let projectRoot = workspaceVM.projectURL.path
            let workflowsDir = URL(fileURLWithPath: projectRoot).appendingPathComponent(".github/workflows")

            do {
                if !FileManager.default.fileExists(atPath: workflowsDir.path) {
                    workflows = []
                    isRefreshing = false
                    return
                }
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

    private func openWorkflow(_ workflow: GitHubWorkflow) {
        do {
            editingContent = try String(contentsOfFile: workflow.path, encoding: .utf8)
            selectedWorkflow = workflow
        } catch {
            print("Failed to read workflow: \(error)")
        }
    }

    private func createNewWorkflow() {
        let newWorkflow = GitHubWorkflow(name: "main.yml", path: "")
        editingContent = """
name: CI

on:
  push:
    branches: [ main ]
  pull_request:
    branches: [ main ]

jobs:
  build:
    runs-on: macos-latest
    steps:
      - uses: actions/checkout@v2
      - name: Build
        run: swift build
"""
        selectedWorkflow = newWorkflow
    }

    private func saveWorkflow(_ workflow: GitHubWorkflow, content: String) {
        let projectRoot = workspaceVM.projectURL
        let workflowsDir = projectRoot.appendingPathComponent(".github/workflows")

        do {
            try FileManager.default.createDirectory(at: workflowsDir, withIntermediateDirectories: true)
            let fileURL = workflowsDir.appendingPathComponent(workflow.name)
            try content.write(to: fileURL, options: .atomic, encoding: .utf8)
            refreshWorkflows()
        } catch {
            print("Failed to save workflow: \(error)")
        }
    }
}

public struct GitHubWorkflow: Identifiable, Codable {
    public let id: UUID
    public let name: String
    public let path: String

    public init(id: UUID = UUID(), name: String, path: String) {
        self.id = id
        self.name = name
        self.path = path
    }
}
