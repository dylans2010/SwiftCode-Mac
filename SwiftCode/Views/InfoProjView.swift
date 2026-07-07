import SwiftUI

struct InfoProjView: View {
    let project: Project

    var body: some View {
        Form {
            Section("Basic Information") {
                LabeledContent("Name", value: project.name)
                LabeledContent("ID", value: project.id.uuidString)
                LabeledContent("Created", value: project.createdAt, format: .dateTime)
                LabeledContent("Last Opened", value: project.lastOpened, format: .dateTime)
                LabeledContent("File Count", value: "\(project.fileCount)")
            }

            Section("Description") {
                Text(project.description.isEmpty ? "No description provided." : project.description)
                    .foregroundStyle(project.description.isEmpty ? .secondary : .primary)
            }

            if let config = project.ciBuildConfiguration {
                Section("Build Configuration") {
                    LabeledContent("Platform", value: config.platform.rawValue)
                    LabeledContent("Deployment Target", value: config.deploymentTarget)
                    LabeledContent("Device Family", value: config.targetDeviceFamily.rawValue)
                    LabeledContent("Bundle ID", value: config.bundleIdentifier)
                    LabeledContent("Scheme", value: config.schemeName)
                }
            }

            if let repo = project.githubRepo {
                Section("GitHub Integration") {
                    LabeledContent("Repository", value: repo)
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Project Info")
    }
}
