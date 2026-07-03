import SwiftUI

struct NewProjectSheetView: View {
    @Bindable var viewModel: HomeViewModel
    @Environment(\.dismiss) var dismiss
    @State private var projectName = "MyProject"
    @State private var selectedTemplate: String = "macOS App"

    var body: some View {
        VStack(spacing: 20) {
            Text("Create New Project").font(.headline)
            TextField("Project Name", text: $projectName)
            TemplatePickerView(selected: $selectedTemplate)
            HStack {
                Button("Cancel") { dismiss() }
                Button("Create") {
                    createProject()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .frame(width: 400)
    }

    private func createProject() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.message = "Select where to save your project"

        if panel.runModal() == .OK, let url = panel.url {
            let projectURL = url.appendingPathComponent(projectName)
            Task {
                let template: ProjectTemplate = {
                    switch selectedTemplate {
                    case "macOS App": return MacOSAppTemplate()
                    case "Swift Package": return SwiftPackageTemplate()
                    case "Command Line Tool": return CommandLineToolTemplate()
                    default: return FrameworkTemplate()
                    }
                }()

                do {
                    try await ProjectTemplateEngine.shared.createProject(at: projectURL, template: template)
                    await viewModel.importProject(url: projectURL)
                    dismiss()
                } catch {
                    LoggingTool.error("Failed to create project: \(error)")
                }
            }
        }
    }
}
