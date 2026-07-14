import SwiftUI

@MainActor
struct ProjectSettingsView: View {
    @Environment(ProjectSessionStore.self) private var sessionStore
    @Environment(\.dismiss) private var dismiss

    @State private var projectName = ""
    @State private var projectDescription = ""
    @State private var githubRepo = ""
    @State private var bundleIdentifier = ""
    @State private var version = "1.0.0"
    @State private var build = "1"
    @State private var deploymentTarget = "16.0"
    @State private var errorMessage: String?
    @State private var showError = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Project Info") {
                    HStack {
                        Text("Name")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(projectName)
                            .foregroundStyle(.white)
                    }

                    TextField("Description", text: $projectDescription, axis: .vertical)
                        .lineLimit(3)
                }

                Section("GitHub") {
                    TextField("Repository (Owner/Repo)", text: $githubRepo)
                        .autocorrectionDisabled()
                }

                Section("Build Settings") {
                    TextField("Bundle Identifier", text: $bundleIdentifier)
                        .autocorrectionDisabled()

                    HStack {
                        Text("Version")
                        Spacer()
                        TextField("1.0.0", text: $version)
                            .multilineTextAlignment(.trailing)
                    }

                    HStack {
                        Text("Build")
                        Spacer()
                        TextField("1", text: $build)
                            .multilineTextAlignment(.trailing)
                    }

                    Picker("Deployment Target", selection: $deploymentTarget) {
                        Text("iOS 15.0").tag("15.0")
                        Text("iOS 16.0").tag("16.0")
                        Text("iOS 17.0").tag("17.0")
                        Text("iOS 18.0").tag("18.0")
                    }
                }

                if let project = sessionStore.activeProject {
                    Section("Statistics") {
                        HStack {
                            Text("Files")
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text("\(project.fileCount)")
                        }
                        HStack {
                            Text("Created")
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(project.createdAt, style: .date)
                        }
                        HStack {
                            Text("Last Opened")
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(project.lastOpened, style: .date)
                        }
                    }

                    Section("Storage") {
                        HStack {
                            Text("Location")
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(project.directoryURL.path)
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                        }

                        Button {
                            openProjectInFiles(project)
                        } label: {
                            Label("Show in Finder", systemImage: "folder.fill")
                                .foregroundStyle(.blue)
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Project Settings")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { saveSettings() }
                }
            }
            .alert("Error", isPresented: $showError, presenting: errorMessage) { _ in
                Button("OK") {}
            } message: { msg in Text(msg) }
            .onAppear { loadSettings() }
        }
    }

    private func loadSettings() {
        guard let project = sessionStore.activeProject else { return }
        projectName = project.name
        projectDescription = project.description
        githubRepo = project.githubRepo ?? ""
        bundleIdentifier = "com.swiftcode.\(project.name.lowercased().replacingOccurrences(of: " ", with: "."))"
    }

    private func saveSettings() {
        guard let project = sessionStore.activeProject else { return }

        let repo = githubRepo.isEmpty ? nil : githubRepo
        sessionStore.updateProjectSettings(description: projectDescription, githubRepo: repo, for: project)

        dismiss()
    }

    private func openProjectInFiles(_ project: Project) {
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: project.directoryURL.path)
    }
}
