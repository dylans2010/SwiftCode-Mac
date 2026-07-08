import SwiftUI

struct SourceControlView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var projectManager: ProjectManager
    @Environment(\.dismiss) private var dismiss

    @State private var showSetup = false

    var body: some View {
        NavigationStack {
            Group {
                if settings.gitPath.isEmpty || settings.httpsAuthToken.isEmpty {
                    VStack(spacing: 20) {
                        Image(systemName: "gearshape.2")
                            .font(.system(size: 60))
                            .foregroundStyle(.secondary)
                        Text("Git not configured")
                            .font(.title2.bold())
                        Text("Please complete the setup to use Source Control features.")
                            .foregroundStyle(.secondary)
                        Button("Start Setup") {
                            showSetup = true
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                    }
                } else {
                    dashboard
                }
            }
            .navigationTitle("Source Control")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $showSetup) {
                SCSetupOnboard()
            }
            .onAppear {
                checkSetup()
            }
        }
    }

    private func checkSetup() {
        if settings.gitPath.isEmpty || settings.httpsAuthToken.isEmpty {
            showSetup = true
        }
    }

    private var dashboard: some View {
        List {
            Section("GitHub Integration") {
                if let project = projectManager.activeProject {
                    NavigationLink(destination: GitHubIntegrationView(project: project)) {
                        Label("GitHub Project Sync", systemImage: "arrow.triangle.2.circlepath")
                    }
                    NavigationLink(destination: GitHubIssuesView()) {
                        Label("Issues", systemImage: "exclamationmark.circle")
                    }
                }

                NavigationLink(destination: GistsView()) {
                    Label("Gists", systemImage: "doc.on.doc")
                }
            }

            Section("Local Git") {
                if let project = projectManager.activeProject {
                    NavigationLink(destination: GitChangesView(project: project)) {
                        Label("Changes", systemImage: "plus.minus.circle")
                    }
                    NavigationLink(destination: GitBranchesView(project: project)) {
                        Label("Branches", systemImage: "arrow.triangle.branch")
                    }
                    NavigationLink(destination: GitHistoryView()) {
                        Label("History", systemImage: "clock.arrow.circlepath")
                    }
                    NavigationLink(destination: GitCLIView()) {
                        Label("Git CLI", systemImage: "terminal")
                    }
                }
            }

            Section("Settings") {
                Button {
                    showSetup = true
                } label: {
                    Label("Configure Git / Token", systemImage: "gear")
                }
            }
        }
    }
}
