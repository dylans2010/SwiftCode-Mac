import SwiftUI
import UniformTypeIdentifiers

struct NewProjectSheetView: View {
    @Environment(ProjectSessionStore.self) private var sessionStore
    @Bindable var viewModel: HomeViewModel
    @Environment(\.dismiss) var dismiss

    @State private var mode: SelectionMode = .create

    enum SelectionMode: String, CaseIterable, Identifiable {
        case create = "New"
        case importFolder = "Import"
        case clone = "Clone"
        case xcodeproj = "Xcode"
        case scproj = ".scproj"

        var id: String { rawValue }

        var icon: String {
            switch self {
            case .create: "plus.square.fill"
            case .importFolder: "folder.badge.plus"
            case .clone: "arrow.triangle.branch"
            case .xcodeproj: "hammer.circle.fill"
            case .scproj: "shippingbox.fill"
            }
        }

        var subtitle: String {
            switch self {
            case .create: "Start from a template"
            case .importFolder: "Use an existing folder"
            case .clone: "Pull from Git"
            case .xcodeproj: "Open an Xcode workspace"
            case .scproj: "Restore an archive"
            }
        }

        var tint: Color {
            switch self {
            case .create: .orange
            case .importFolder: .blue
            case .clone: .purple
            case .xcodeproj: .pink
            case .scproj: .green
            }
        }
    }

    var body: some View {
        NavigationStack {
            HStack(spacing: 0) {
                sidebar

                Divider()

                VStack(spacing: 0) {
                    header

                    ScrollView {
                        contentView
                            .padding(24)
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                    }

                    Divider()

                    HStack {
                        Text("Choose how you want to bring code into SwiftCode.")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Spacer()

                        Button("Cancel") { dismiss() }
                            .keyboardShortcut(.cancelAction)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 14)
                    .background(.thinMaterial)
                }
            }
            .navigationTitle(title)
        }
        .frame(width: 760, height: 560)
        .background(.ultraThinMaterial)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Create")
                    .font(.title2.bold())
                Text("Project launcher")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 8)

            VStack(spacing: 8) {
                ForEach(SelectionMode.allCases) { item in
                    Button {
                        withAnimation(.snappy(duration: 0.18)) {
                            mode = item
                        }
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: item.icon)
                                .font(.headline)
                                .foregroundStyle(mode == item ? .white : item.tint)
                                .frame(width: 32, height: 32)
                                .background((mode == item ? Color.white.opacity(0.18) : item.tint.opacity(0.14)), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.rawValue)
                                    .font(.headline)
                                Text(item.subtitle)
                                    .font(.caption2)
                                    .foregroundStyle(mode == item ? .white.opacity(0.82) : .secondary)
                            }

                            Spacer()
                        }
                        .padding(10)
                        .background(mode == item ? item.tint.gradient : Color.clear.gradient, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }

            Spacer()

            Label("macOS optimized", systemImage: "macbook")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
        }
        .padding(18)
        .frame(width: 230)
        .background(.regularMaterial)
    }

    private var header: some View {
        HStack(spacing: 16) {
            Image(systemName: mode.icon)
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(mode.tint.gradient)
                .frame(width: 58, height: 58)
                .background(mode.tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 18, style: .continuous))

            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                Text(mode.subtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(24)
        .background(.thinMaterial)
    }

    @ViewBuilder
    private var contentView: some View {
        switch mode {
        case .create:
            actionPanel(
                icon: "sparkles",
                title: "Build from a polished starter",
                description: "Pick an app or package template with the right files, structure, and defaults already in place.",
                tint: .orange,
                actionTitle: "Choose Template",
                actionIcon: "square.grid.2x2.fill"
            ) {
                NavigationLink(destination: TemplatePickerView(viewModel: viewModel)) {
                    Label("Choose Template", systemImage: "square.grid.2x2.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }

        case .clone:
            GitCloneSheetView(viewModel: viewModel)
                .padding(18)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))

        case .importFolder:
            actionPanel(
                icon: "folder.badge.plus",
                title: "Import a folder",
                description: "Select a folder from disk and SwiftCode will add it to your project library.",
                tint: .blue,
                actionTitle: "Select Folder",
                actionIcon: "folder.fill"
            ) {
                Button { importFolder() } label: {
                    Label("Select Folder", systemImage: "folder.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }

        case .xcodeproj:
            actionPanel(
                icon: "hammer.circle.fill",
                title: "Import an Xcode project",
                description: "Open an existing .xcodeproj and continue working with it inside SwiftCode.",
                tint: .pink,
                actionTitle: "Select .xcodeproj",
                actionIcon: "app.badge"
            ) {
                Button { importXcodeProject() } label: {
                    Label("Select .xcodeproj", systemImage: "app.badge")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }

        case .scproj:
            ImportProjView()
                .padding(18)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
    }

    private func actionPanel<Actions: View>(
        icon: String,
        title: String,
        description: String,
        tint: Color,
        actionTitle: String,
        actionIcon: String,
        @ViewBuilder actions: () -> Actions
    ) -> some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(alignment: .top, spacing: 18) {
                Image(systemName: icon)
                    .font(.system(size: 44, weight: .semibold))
                    .foregroundStyle(tint.gradient)
                    .frame(width: 86, height: 86)
                    .background(tint.opacity(0.13), in: RoundedRectangle(cornerRadius: 26, style: .continuous))

                VStack(alignment: .leading, spacing: 8) {
                    Text(title)
                        .font(.title.bold())
                    Text(description)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            HStack(spacing: 12) {
                Label("Clean setup", systemImage: "checkmark.seal.fill")
                Label("Ready for macOS", systemImage: "desktopcomputer")
                Label("Saved to Library", systemImage: "tray.full.fill")
            }
            .font(.subheadline.weight(.medium))
            .foregroundStyle(.secondary)

            actions()
                .frame(maxWidth: 260)
                .accessibilityLabel(actionTitle)
                .accessibilityHint("Starts the \(actionTitle.lowercased()) flow using \(actionIcon).")
        }
        .padding(28)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(tint.opacity(0.25), lineWidth: 1)
        )
    }

    private var title: String {
        switch mode {
        case .create: return "Create New Project"
        case .importFolder: return "Import Folder"
        case .clone: return "Clone Repository"
        case .xcodeproj: return "Import Xcode Project"
        case .scproj: return "Import .scproj File"
        }
    }

    private func importFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        if panel.runModal() == .OK, let url = panel.url {
            Task {
                do {
                    let project = try await sessionStore.importProject(from: url)
                    await sessionStore.openProject(project)
                    dismiss()
                } catch {
                    LoggingTool.error("Failed to import folder: \(error)")
                }
            }
        }
    }

    private func importXcodeProject() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "xcodeproj")].compactMap { $0 }
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        if panel.runModal() == .OK, let url = panel.url {
            Task {
                do {
                    let project = try await sessionStore.importProject(from: url.deletingLastPathComponent())
                    await sessionStore.openProject(project)
                    dismiss()
                } catch {
                    LoggingTool.error("Failed to import Xcode project: \(error)")
                }
            }
        }
    }
}
