import SwiftUI

struct TemplatePickerView: View {
    @Bindable var viewModel: WelcomeViewModel
    @Environment(ProjectSessionStore.self) private var sessionStore
    @Environment(\.dismiss) var dismiss

    var showsHeader: Bool = true
    var showsBackButton: Bool = true

    @State private var projectName = "MyProject"
    @State private var selectedTemplate: any ProjectScaffoldTemplate = MacOSAppTemplate()
    @State private var searchText = ""
    @State private var showingNameAlert = false

    let templates: [any ProjectScaffoldTemplate] = [
        EmptyTemplate(),
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
            if showsHeader {
                // Elegant Dark Header
                HStack(spacing: 16) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color.accentColor.opacity(0.2))
                        Image(systemName: "square.grid.2x2.fill")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundStyle(Color.accentColor)
                    }
                    .frame(width: 48, height: 48)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(Color.accentColor.opacity(0.3), lineWidth: 1)
                    )

                    VStack(alignment: .leading, spacing: 3) {
                        Text("Select a Template")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(Color.white)
                        Text("Choose from various starter configurations.")
                            .font(.subheadline)
                            .foregroundStyle(Color.white.opacity(0.6))
                    }

                    Spacer()
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
                .background(VisualEffectView(material: .headerView, blendingMode: .withinWindow))

                Rectangle()
                    .fill(Color.white.opacity(0.08))
                    .frame(height: 1)
            }

            HStack(spacing: 0) {
                // Left Panel: Configuration & Grid
                VStack(spacing: 16) {
                    // Project Name Input Card
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Project Name")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.white.opacity(0.6))

                        TextField("MyProject", text: $projectName)
                            .textFieldStyle(.plain)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Color.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .liquidGlass(style: .subtle, cornerRadius: 10)
                    }
                    .padding(.horizontal, 16)

                    // Template Search Bar
                    HStack(spacing: 10) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 13))
                            .foregroundStyle(Color.white.opacity(0.5))
                        TextField("Search Templates", text: $searchText)
                            .textFieldStyle(.plain)
                            .font(.system(size: 13))
                            .foregroundStyle(Color.white)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .liquidGlass(style: .subtle, cornerRadius: 10)
                    .padding(.horizontal, 16)

                    // Grid Browser
                    ScrollView {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 105, maximum: 140), spacing: 10)], spacing: 10) {
                            ForEach(filteredTemplates, id: \.name) { template in
                                TemplateGridCard(
                                    template: template,
                                    isSelected: selectedTemplate.name == template.name,
                                    onTap: { selectedTemplate = template }
                                )
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 16)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 14)

                Rectangle()
                    .fill(Color.white.opacity(0.08))
                    .frame(width: 1)

                // Right Panel: Template Inspector Detail
                VStack(alignment: .leading, spacing: 14) {
                    Text("Template Inspector")
                        .font(.system(size: 11.5, weight: .bold))
                        .foregroundStyle(Color.white.opacity(0.5))
                        .padding(.bottom, 2)

                    // Header Info
                    HStack(spacing: 12) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color.accentColor.opacity(0.2))
                            Image(systemName: selectedTemplate.icon)
                                .font(.system(size: 18))
                                .foregroundStyle(Color.accentColor)
                        }
                        .frame(width: 40, height: 40)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(selectedTemplate.name)
                                .font(.system(size: 13.5, weight: .bold))
                                .foregroundStyle(Color.white)
                                .lineLimit(1)
                            Text("Ready to Scaffold")
                                .font(.caption2)
                                .foregroundStyle(Color.white.opacity(0.5))
                        }
                    }

                    Rectangle()
                        .fill(Color.white.opacity(0.08))
                        .frame(height: 1)

                    // Description
                    VStack(alignment: .leading, spacing: 6) {
                        Text("About this Template")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(Color.white.opacity(0.5))
                        Text(selectedTemplate.description)
                            .font(.system(size: 11.5))
                            .foregroundStyle(Color.white.opacity(0.8))
                            .lineSpacing(2.5)
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
                .frame(width: 220)
                .padding(16)
                .background(VisualEffectView(material: .sidebar, blendingMode: .withinWindow))
            }

            Rectangle()
                .fill(Color.white.opacity(0.08))
                .frame(height: 1)

            // Footer Action Bar
            HStack {
                if showsBackButton {
                    Button(action: { dismiss() }) {
                        Label("Back", systemImage: "chevron.left")
                            .padding(.horizontal, 4)
                    }
                    .controlSize(.regular)
                }

                Spacer()

                Button(action: { showingNameAlert = true }) {
                    Label("Create Project", systemImage: "sparkles")
                        .bold()
                        .padding(.horizontal, 8)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
                .tint(Color.accentColor)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(VisualEffectView(material: .headerView, blendingMode: .withinWindow))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(VisualEffectView(material: .contentBackground, blendingMode: .withinWindow))
        .liquidGlass(style: .sheet, cornerRadius: 16)
        .toolbar(.hidden, for: .windowToolbar)
        .toolbar(.hidden)
        .preferredColorScheme(.dark)
        .alert("Project Name", isPresented: $showingNameAlert) {
            TextField("Enter project name", text: $projectName)
            Button("Create") {
                createProject()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Please enter a name for your new project.")
        }
    }

    private func createProject() {
        Task {
            do {
                let project = try sessionStore.createProject(name: projectName)
                try await ProjectScaffoldTemplateEngine.shared.createProject(at: project.directoryURL, template: selectedTemplate)
                sessionStore.refreshFileTree(for: project)
                await sessionStore.openProject(project)
                dismiss()
            } catch {
                LoggingTool.error("Failed to create project: \(error)")
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
            VStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(
                            isSelected
                                ? Color.accentColor
                                : Color.white.opacity(isHovered ? 0.10 : 0.05)
                        )
                    Image(systemName: template.icon)
                        .font(.system(size: 22))
                        .foregroundStyle(isSelected ? Color.white : Color.accentColor)
                }
                .frame(width: 50, height: 50)

                Text(template.name)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(isSelected ? Color.white : Color.white.opacity(0.85))
                    .lineLimit(1)
                    .multilineTextAlignment(.center)
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity)
            .liquidGlass(
                style: isSelected ? .prominent : .subtle,
                cornerRadius: 14,
                tint: isSelected ? Color.accentColor.opacity(0.2) : nil
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(
                        isSelected ? Color.accentColor : Color.white.opacity(0.06),
                        lineWidth: isSelected ? 1.5 : 1
                    )
            )
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
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
                .font(.caption2)
                .foregroundStyle(Color.white.opacity(0.5))
            Spacer()
            Text(value)
                .font(.caption2.bold())
                .foregroundStyle(Color.white)
        }
    }
}
