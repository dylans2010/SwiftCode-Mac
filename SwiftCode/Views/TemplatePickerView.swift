import SwiftUI

struct TemplatePickerView: View {
    @Bindable var viewModel: WelcomeViewModel
    @Environment(ProjectSessionStore.self) private var sessionStore
    @Environment(\.dismiss) var dismiss

    @State private var projectName = "MyProject"
    @State private var selectedTemplate: any ProjectScaffoldTemplate = MacOSAppTemplate()
    @State private var searchText = ""

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
        StaticLibraryTemplate(),
        DashboardViewTemplate(),
        LoginViewTemplate(),
        ChatViewTemplate(),
        SettingsViewTemplate(),
        OnboardingViewTemplate(),
        ECommerceViewTemplate(),
        CalendarViewTemplate(),
        NotesViewTemplate(),
        WeatherViewTemplate(),
        TodoViewTemplate(),
        AudioPlayerViewTemplate(),
        ProfileViewTemplate(),
        FitnessTrackerViewTemplate(),
        NewsReaderViewTemplate(),
        MapViewTemplate(),
        DrawingViewTemplate(),
        CalculatorViewTemplate(),
        PhotoGalleryViewTemplate(),
        MarkdownEditorViewTemplate(),
        FileBrowserViewTemplate(),
        TaskBoardViewTemplate(),
        AnalyticsDashboardViewTemplate(),
        RecipeViewTemplate(),
        BudgetTrackerViewTemplate(),
        QuizViewTemplate()
    ]

    var filteredTemplates: [any ProjectScaffoldTemplate] {
        if searchText.isEmpty {
            return templates
        }
        return templates.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Elegant Modern Header
            HStack(spacing: 16) {
                ZStack {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color.orange.opacity(0.18).gradient)
                    Image(systemName: "square.grid.2x2.fill")
                        .font(.system(size: 26, weight: .bold))
                        .foregroundStyle(.orange.gradient)
                }
                .frame(width: 58, height: 58)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Select a Template")
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                    Text("Choose from various highly polished starter configurations.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 20)
            .background(.thinMaterial)

            Divider()

            HStack(spacing: 0) {
                // Left Panel: Configuration & Grid
                VStack(spacing: 20) {
                    // Project Name Input Card
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Project Name")
                            .font(.headline)
                            .foregroundStyle(.secondary)

                        TextField("MyProject", text: $projectName)
                            .textFieldStyle(.plain)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .stroke(Color.accentColor.opacity(0.2), lineWidth: 1)
                            )
                    }
                    .padding(.horizontal)

                    // Template Search Bar
                    HStack(spacing: 10) {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(.secondary)
                        TextField("Search Templates", text: $searchText)
                            .textFieldStyle(.plain)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                    .padding(.horizontal)

                    // Grid Browser
                    ScrollView {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 110, maximum: 140), spacing: 14)], spacing: 14) {
                            ForEach(filteredTemplates, id: \.name) { template in
                                TemplateGridCard(
                                    template: template,
                                    isSelected: selectedTemplate.name == template.name,
                                    onTap: { selectedTemplate = template }
                                )
                            }
                        }
                        .padding(.horizontal)
                        .padding(.bottom, 16)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 20)

                Divider()

                // Right Panel: Template Inspector Detail
                VStack(alignment: .leading, spacing: 18) {
                    Text("Template Inspector")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.secondary)
                        .padding(.bottom, 4)

                    // Header Info
                    HStack(spacing: 14) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(Color.orange.opacity(0.12).gradient)
                            Image(systemName: selectedTemplate.icon)
                                .font(.title)
                                .foregroundStyle(.orange.gradient)
                        }
                        .frame(width: 52, height: 52)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(selectedTemplate.name)
                                .font(.headline)
                            Text("Ready to Scaffold")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Divider()

                    // Description
                    VStack(alignment: .leading, spacing: 6) {
                        Text("About this Template")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.secondary)
                        Text(selectedTemplate.description)
                            .font(.body)
                            .foregroundStyle(.primary)
                            .lineSpacing(4)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer()

                    // Quick Specs
                    VStack(alignment: .leading, spacing: 8) {
                        TemplateSpecRow(label: "Files Included", value: "\(selectedTemplate.files.count)")
                        TemplateSpecRow(label: "Target Platform", value: "macOS, iOS, Swift Package")
                        TemplateSpecRow(label: "Deployment", value: "Native App Sandbox")
                    }
                }
                .frame(width: 260)
                .padding(24)
                .background(.regularMaterial)
            }

            Divider()

            // Footer Action Bar
            HStack {
                Button(action: { dismiss() }) {
                    Label("Back", systemImage: "chevron.left")
                        .padding(.horizontal, 4)
                }
                .controlSize(.large)

                Spacer()

                Button(action: createProject) {
                    Label("Create Project", systemImage: "sparkles")
                        .bold()
                        .padding(.horizontal, 8)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(.orange)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 14)
            .background(.thinMaterial)
        }
        .frame(width: 760, height: 560)
        .background(.ultraThinMaterial)
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
                    let project = try sessionStore.createProject(name: projectName)
                    await sessionStore.openProject(project)
                    dismiss()
                } catch {
                    LoggingTool.error("Failed to create project: \(error)")
                }
            }
        }
    }
}

// MARK: - Helper Views

struct TemplateGridCard: View {
    let template: any ProjectScaffoldTemplate
    let isSelected: Bool
    let onTap: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(isSelected ? Color.orange.gradient : Color.secondary.opacity(isHovered ? 0.14 : 0.08).gradient)
                    Image(systemName: template.icon)
                        .font(.system(size: 26))
                        .foregroundStyle(isSelected ? .white : .orange)
                }
                .frame(width: 58, height: 58)

                Text(template.name)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(isSelected ? .orange : .primary)
                    .lineLimit(1)
                    .multilineTextAlignment(.center)
            }
            .padding(.vertical, 14)
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(isSelected ? Color.orange.opacity(0.08) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(isSelected ? Color.orange : Color.clear, lineWidth: 1.5)
            )
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hover in
            withAnimation(.snappy(duration: 0.15)) {
                isHovered = hover
            }
        }
    }
}

struct TemplateSpecRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.caption.bold())
                .foregroundStyle(.primary)
        }
    }
}
