import SwiftUI

struct TemplatePickerView: View {
    @Bindable var viewModel: HomeViewModel
    @EnvironmentObject private var projectManager: ProjectManager
    @Environment(\.dismiss) var dismiss

    @State private var projectName = "MyProject"
    @State private var selectedTemplate: any ProjectScaffoldTemplate = MacOSAppTemplate()

    let templates: [any ProjectScaffoldTemplate] = [
        IntroductionTemplate(),
        MacOSAppTemplate(),
        MultiplatformAppTemplate(),
        DocumentAppTemplate(),
        MenuBarAppTemplate(),
        SwiftPackageTemplate(),
        CommandLineToolTemplate(),
        FrameworkTemplate(),
        GameMetalTemplate(),
        GameSpriteKitTemplate(),
        iOSAppTemplate(),
        SwiftDataAppTemplate(),
        SwiftMacroTemplate(),
        SafariExtensionTemplate(),
        SystemExtensionTemplate(),
        SwiftUIViewLibraryTemplate(),
        StaticLibraryTemplate()
    ]

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    SectionView(title: "Project Name") {
                        TextField("MyProject", text: $projectName)
                            .textFieldStyle(.roundedBorder)
                    }

                    SectionView(title: "Choose a Template") {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 100))], spacing: 20) {
                            ForEach(templates, id: \.name) { template in
                                VStack {
                                    Image(systemName: template.icon)
                                        .font(.system(size: 30))
                                        .frame(width: 60, height: 60)
                                        .background(selectedTemplate.name == template.name ? Color.accentColor : Color.secondary.opacity(0.1))
                                        .foregroundColor(selectedTemplate.name == template.name ? .white : .primary)
                                        .cornerRadius(10)

                                    Text(template.name)
                                        .font(.caption)
                                        .lineLimit(1)
                                }
                                .onTapGesture {
                                    selectedTemplate = template
                                }
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text(selectedTemplate.name)
                            .font(.headline)
                        Text(selectedTemplate.description)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.secondary.opacity(0.05))
                    .cornerRadius(8)
                }
                .padding()
            }

            Divider()

            HStack {
                Button("Back") { dismiss() }
                Spacer()
                Button("Create Project") {
                    createProject()
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
        }
        .navigationTitle("Select Template")
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
                do {
                    try await ProjectScaffoldTemplateEngine.shared.createProject(at: projectURL, template: selectedTemplate)
                    let project = try await ProjectManager.shared.importProject(from: projectURL)
                    try await projectManager.openProject(project)
                    dismiss()
                } catch {
                    LoggingTool.error("Failed to create project: \(error)")
                }
            }
        }
    }
}
