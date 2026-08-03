import SwiftUI
import UniformTypeIdentifiers

public struct NewProjectSheetView: View {
    @Environment(ProjectSessionStore.self) private var sessionStore
    var viewModel: WelcomeViewModel
    @Environment(\.dismiss) var dismiss

    @State private var mode: SelectionMode = .create
    @State private var showingImportNameAlert = false
    @State private var pendingImportURL: URL?
    @State private var pendingImportName = ""

    public enum SelectionMode: String, CaseIterable, Identifiable {
        case create = "New Project"
        case importFolder = "Import Folder"
        case clone = "Clone Repo"
        case xcodeproj = "Xcode Proj"
        case scproj = "SC Project"

        public var id: String { rawValue }

        public var icon: String {
            switch self {
            case .create: "plus.square.fill"
            case .importFolder: "folder.badge.plus"
            case .clone: "arrow.triangle.branch"
            case .xcodeproj: "hammer.circle.fill"
            case .scproj: "shippingbox.fill"
            }
        }

        public var subtitle: String {
            switch self {
            case .create: "Start from a premium template"
            case .importFolder: "Select directory on disk"
            case .clone: "Pull remote Git URL"
            case .xcodeproj: "Open Apple Workspace"
            case .scproj: "Restore project archive"
            }
        }

        public var tint: Color {
            switch self {
            case .create: .orange
            case .importFolder: .blue
            case .clone: .purple
            case .xcodeproj: .pink
            case .scproj: .green
            }
        }
    }

    public init(viewModel: WelcomeViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        NavigationStack {
            HStack(spacing: 0) {
                // High-fidelity sidebar selector with native materials
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Create Workspace")
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                            .foregroundStyle(.primary)
                        Text("Project launcher pipeline")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 8)

                    ScrollView {
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
                                            .frame(width: 30, height: 32)
                                            .background((mode == item ? Color.white.opacity(0.18) : item.tint.opacity(0.14)), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(item.rawValue)
                                                .font(.subheadline.weight(.semibold))
                                                .foregroundStyle(mode == item ? .white : .primary)
                                            Text(item.subtitle)
                                                .font(.system(size: 9))
                                                .foregroundStyle(mode == item ? .white.opacity(0.82) : .secondary)
                                                .lineLimit(1)
                                        }

                                        Spacer(minLength: 0)
                                    }
                                    .padding(8)
                                    .background(mode == item ? item.tint.gradient : Color.clear.gradient, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                                    .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    Spacer()

                    Label("macOS native client", systemImage: "macbook")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                }
                .padding(16)
                .frame(width: 220)
                .background(VisualEffectView(material: .sidebar, blendingMode: .withinWindow))

                Divider()

                VStack(spacing: 0) {
                    // Header Bar with dynamic material
                    HStack(spacing: 16) {
                        Image(systemName: mode.icon)
                            .font(.system(size: 26, weight: .semibold))
                            .foregroundStyle(mode.tint.gradient)
                            .frame(width: 52, height: 52)
                            .background(mode.tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                        VStack(alignment: .leading, spacing: 4) {
                            Text(title)
                                .font(.system(size: 22, weight: .bold, design: .rounded))
                            Text(mode.subtitle)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()
                    }
                    .padding(20)
                    .background(Color(NSColor.windowBackgroundColor))

                    Divider()

                    // Scrollable dynamic content viewport
                    ScrollView {
                        contentView
                            .padding(20)
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                    }
                    .background(Color(NSColor.windowBackgroundColor).opacity(0.4))

                    Divider()

                    // Action footer bar
                    HStack {
                        Text("Select an option to import or scaffold native projects.")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Spacer()

                        Button("Cancel") { dismiss() }
                            .keyboardShortcut(.cancelAction)
                            .buttonStyle(.bordered)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(VisualEffectView(material: .headerView, blendingMode: .withinWindow))
                }
            }
        }
        .frame(width: 760, height: 560)
        .alert("Project Name", isPresented: $showingImportNameAlert) {
            TextField("Enter project name", text: $pendingImportName)
            Button("Import") {
                if let url = pendingImportURL {
                    Task {
                        do {
                            let project = try await sessionStore.importProject(from: url, name: pendingImportName)
                            await sessionStore.openProject(project)
                            dismiss()
                        } catch {
                            LoggingTool.error("Failed to import project: \(error)")
                        }
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Please enter a name for your imported project.")
        }
    }

    @ViewBuilder
    private var contentView: some View {
        switch mode {
        case .create:
            actionPanel(
                icon: "sparkles",
                title: "Scaffold from starter models",
                description: "Choose an app, library, multiplatform, or command line tool template with full build structures, files, configurations, and sensible defaults automatically configured.",
                tint: .orange,
                actionTitle: "Choose Scaffold Template",
                actionIcon: "square.grid.2x2.fill"
            ) {
                NavigationLink(destination: TemplatePickerView(viewModel: viewModel)) {
                    Label("Choose Template", systemImage: "square.grid.2x2.fill")
                        .font(.headline)
                        .foregroundColor(.white)
                        .padding(.vertical, 10)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
            }

        case .clone:
            GitCloneSheetView(viewModel: viewModel)
                .padding(16)
                .background(Color(NSColor.controlBackgroundColor).opacity(0.4), in: RoundedRectangle(cornerRadius: 16, style: .continuous))

        case .importFolder:
            actionPanel(
                icon: "folder.badge.plus",
                title: "Import file directory",
                description: "Map any file directory from your Mac's filesystem. SwiftCode will automatically scan, synchronize, and load it into your workspaces.",
                tint: .blue,
                actionTitle: "Select Directory",
                actionIcon: "folder.fill"
            ) {
                Button { importFolder() } label: {
                    Label("Select Directory", systemImage: "folder.fill")
                        .font(.headline)
                        .foregroundColor(.white)
                        .padding(.vertical, 10)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.blue)
            }

        case .xcodeproj:
            actionPanel(
                icon: "hammer.circle.fill",
                title: "Open Xcode Target Project",
                description: "Import any native Xcode target .xcodeproj or .xcworkspace. Perfect for seamless side-by-side transition and compilation within SwiftCode.",
                tint: .pink,
                actionTitle: "Select .xcodeproj File",
                actionIcon: "app.badge"
            ) {
                Button { importXcodeProject() } label: {
                    Label("Select .xcodeproj File", systemImage: "app.badge")
                        .font(.headline)
                        .foregroundColor(.white)
                        .padding(.vertical, 10)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.pink)
            }

        case .scproj:
            ImportProjView()
                .padding(16)
                .background(Color(NSColor.controlBackgroundColor).opacity(0.4), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
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
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .top, spacing: 16) {
                Image(systemName: icon)
                    .font(.system(size: 38, weight: .semibold))
                    .foregroundStyle(tint.gradient)
                    .frame(width: 72, height: 72)
                    .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 18, style: .continuous))

                VStack(alignment: .leading, spacing: 6) {
                    Text(title)
                        .font(.title3.bold())
                        .foregroundColor(.primary)
                    Text(description)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            HStack(spacing: 12) {
                Label("Dynamic scaffolding", systemImage: "checkmark.seal.fill")
                Label("Universal architecture", systemImage: "desktopcomputer")
                Label("Integrated sessions", systemImage: "tray.full.fill")
            }
            .font(.caption.weight(.medium))
            .foregroundStyle(.secondary)

            actions()
                .frame(maxWidth: 280)
                .accessibilityLabel(actionTitle)
                .accessibilityHint("Starts the \(actionTitle.lowercased()) flow.")
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.25), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(tint.opacity(0.2), lineWidth: 1)
        )
    }

    private var title: String {
        switch mode {
        case .create: return "Create Project"
        case .importFolder: return "Import Folder"
        case .clone: return "Clone Repository"
        case .xcodeproj: return "Open Xcode Project"
        case .scproj: return "Open SC Project"
        }
    }

    private func importFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        if panel.runModal() == .OK, let url = panel.url {
            pendingImportURL = url
            pendingImportName = url.lastPathComponent
            showingImportNameAlert = true
        }
    }

    private func importXcodeProject() {
        let panel = NSOpenPanel()
        let xcodeProjType = UTType("com.apple.dt.document.xcodeproj") ?? UTType(filenameExtension: "xcodeproj") ?? .directory
        panel.allowedContentTypes = [xcodeProjType, .directory]
        panel.treatsFilePackagesAsDirectories = false
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        if panel.runModal() == .OK, let url = panel.url {
            pendingImportURL = url
            pendingImportName = url.deletingPathExtension().lastPathComponent
            showingImportNameAlert = true
        }
    }
}
