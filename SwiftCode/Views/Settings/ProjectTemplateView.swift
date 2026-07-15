import SwiftUI

// MARK: - Project Template View

struct ProjectTemplateView: View {
    @Environment(ProjectSessionStore.self) private var sessionStore
    @StateObject private var templateManager = ProjectTemplateManager.shared
    @State private var selectedTemplate: ProjectTemplate?
    @State private var showApplyConfirm = false
    @State private var applyResult: String?
    @State private var showResultAlert = false
    @State private var isInitializingRepo = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // 1. Overview Card
                GroupBox {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            Label("Project Template Scaffolder", systemImage: "doc.badge.plus")
                                .font(.headline)
                                .foregroundColor(.teal)
                            Spacer()
                        }

                        Text("Select a template to scaffold files into the current project.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding()
                }
                .groupBoxStyle(ModernGroupBoxStyle())

                // 2. Templates Card
                GroupBox {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            Label("Available Templates", systemImage: "doc.text.fill")
                                .font(.headline)
                                .foregroundColor(.orange)
                            Spacer()
                        }

                        VStack(spacing: 12) {
                            ForEach(templateManager.templates) { template in
                                TemplateRowView(
                                    template: template,
                                    isSelected: selectedTemplate?.id == template.id
                                ) {
                                    selectedTemplate = template
                                }
                                .padding()
                                .background(selectedTemplate?.id == template.id ? Color.orange.opacity(0.1) : Color.primary.opacity(0.04))
                                .cornerRadius(10)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10)
                                        .stroke(selectedTemplate?.id == template.id ? Color.orange.opacity(0.5) : Color.clear, lineWidth: 1)
                                )
                            }
                        }
                    }
                    .padding()
                }
                .groupBoxStyle(ModernGroupBoxStyle())

                // 3. Selection Details & Actions Card
                if let selected = selectedTemplate {
                    GroupBox {
                        VStack(alignment: .leading, spacing: 14) {
                            HStack {
                                Label("Selected Template Details", systemImage: "slider.horizontal.3")
                                    .font(.headline)
                                    .foregroundColor(.blue)
                                Spacer()
                            }

                            TemplateDetailView(template: selected)

                            Divider()

                            if isInitializingRepo {
                                HStack {
                                    ProgressView()
                                        .padding(.trailing, 8)
                                    Text("Initializing GitHub Repository...")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                            } else {
                                Button {
                                    showApplyConfirm = true
                                } label: {
                                    HStack {
                                        Spacer()
                                        Label("Apply Template", systemImage: "doc.badge.plus")
                                            .font(.subheadline.weight(.semibold))
                                            .foregroundStyle(.white)
                                        Spacer()
                                    }
                                }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.large)
                                .tint(.orange)
                            }
                        }
                        .padding()
                    }
                    .groupBoxStyle(ModernGroupBoxStyle())
                }
            }
            .padding(24)
        }
        .navigationTitle("Project Templates")
        .confirmationDialog(
            "Apply \"\(selectedTemplate?.name ?? "")\" template?",
            isPresented: $showApplyConfirm,
            titleVisibility: .visible
        ) {
            Button("Apply") { applyTemplate() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Template files will be added to the current project.")
        }
        .alert("Template Applied", isPresented: $showResultAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(applyResult ?? "")
        }
    }

    // MARK: - Apply

    private func applyTemplate() {
        guard let template = selectedTemplate,
              let project = sessionStore.activeProject else {
            applyResult = "No active project. Open a project first."
            showResultAlert = true
            return
        }

        isInitializingRepo = true

        Task {
            do {
                try templateManager.applyTemplate(template, to: project)

                // Block until repository is initialized
                try await GitHubService.shared.initializeGitHubRepository(for: project) { @Sendable log in
                    Task { @MainActor in
                        LogManager.shared.logDeployment("[GitHub Init] \(log)")
                    }
                }

                await MainActor.run {
                    isInitializingRepo = false
                    applyResult = "Template \"\(template.name)\" applied and GitHub repository initialized successfully."
                    showResultAlert = true
                    selectedTemplate = nil
                }
            } catch {
                await MainActor.run {
                    isInitializingRepo = false
                    applyResult = "Failed: \(error.localizedDescription)"
                    showResultAlert = true
                }
            }
        }
    }
}

// MARK: - Template Row

private struct TemplateRowView: View {
    let template: ProjectTemplate
    let isSelected: Bool
    let onSelect: () -> Void

    private var iconColor: Color {
        switch template.iconColor {
        case "blue": return .blue
        case "orange": return .orange
        case "green": return .green
        case "cyan": return .cyan
        case "purple": return .purple
        default: return .secondary
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: template.icon)
                .font(.title3)
                .foregroundStyle(iconColor)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 4) {
                Text(template.name)
                    .font(.subheadline.weight(.semibold))
                Text(template.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                HStack(spacing: 4) {
                    ForEach(template.tags, id: \.self) { tag in
                        Text(tag)
                            .font(.caption2)
                            .foregroundStyle(.orange)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(.orange.opacity(0.12), in: Capsule())
                    }
                }
            }

            Spacer()

            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.orange)
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture { onSelect() }
    }
}

// MARK: - Template Detail

private struct TemplateDetailView: View {
    let template: ProjectTemplate

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("\(template.files.count) file(s) will be created:")
                .font(.caption)
                .foregroundStyle(.secondary)

            ForEach(template.files, id: \.relativePath) { file in
                HStack(spacing: 6) {
                    Image(systemName: "doc.text")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(file.relativePath)
                        .font(.caption.monospaced())
                        .foregroundStyle(.primary)
                }
            }
        }
    }
}
