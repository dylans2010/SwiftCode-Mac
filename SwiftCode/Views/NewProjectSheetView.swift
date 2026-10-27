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
        case scproj = "SwiftCode Project Archive"

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
            case .create: "Start from a starter template"
            case .importFolder: "Select directory on disk"
            case .clone: "Pull remote Git repository"
            case .xcodeproj: "Open Apple Workspace"
            case .scproj: "Restore project archive"
            }
        }

        public var tint: Color {
            switch self {
            case .create: Color(red: 0.106, green: 0.404, blue: 0.863)
            case .importFolder: .blue
            case .clone: .purple
            case .xcodeproj: .indigo
            case .scproj: .teal
            }
        }
    }

    public init(viewModel: WelcomeViewModel, initialMode: SelectionMode = .create) {
        self.viewModel = viewModel
        self._mode = State(initialValue: initialMode)
    }

    public var body: some View {
        NavigationStack {
            HStack(spacing: 0) {
                // Left Column: Liquid Glass Sidebar
                sidebarView
                    .frame(width: 230)

                // Divider line
                Rectangle()
                    .fill(Color.white.opacity(0.08))
                    .frame(width: 1)

                // Right Column: Content Viewport
                VStack(spacing: 0) {
                    headerView

                    Rectangle()
                        .fill(Color.white.opacity(0.08))
                        .frame(height: 1)

                    ScrollView {
                        contentView
                            .padding(24)
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                    }

                    Rectangle()
                        .fill(Color.white.opacity(0.08))
                        .frame(height: 1)

                    footerView
                }
                .background(Color(red: 0.082, green: 0.102, blue: 0.180))
            }
        }
        .frame(width: 780, height: 560)
        .background(Color(red: 0.082, green: 0.102, blue: 0.180))
        .preferredColorScheme(.dark)
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

    // MARK: - Sidebar

    private var sidebarView: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Create Workspace")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Color.white)
                Text("Project launcher pipeline")
                    .font(.caption2)
                    .foregroundStyle(Color.white.opacity(0.5))
            }
            .padding(.horizontal, 10)
            .padding(.top, 4)

            ScrollView {
                VStack(spacing: 6) {
                    ForEach(SelectionMode.allCases) { item in
                        Button {
                            withAnimation(.snappy(duration: 0.18)) {
                                mode = item
                            }
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: item.icon)
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundStyle(mode == item ? .white : item.tint)
                                    .frame(width: 28, height: 28)
                                    .background(
                                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                                            .fill(mode == item ? Color.white.opacity(0.2) : Color.white.opacity(0.06))
                                    )

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.rawValue)
                                        .font(.system(size: 12.5, weight: mode == item ? .semibold : .medium))
                                        .foregroundStyle(mode == item ? .white : Color.white.opacity(0.9))

                                    Text(item.subtitle)
                                        .font(.system(size: 9.5))
                                        .foregroundStyle(mode == item ? Color.white.opacity(0.8) : Color.white.opacity(0.5))
                                        .lineLimit(1)
                                }

                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(
                                        mode == item
                                            ? Color(red: 0.106, green: 0.404, blue: 0.863)
                                            : Color.clear
                                    )
                            )
                            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            Spacer()

            HStack(spacing: 6) {
                Image(systemName: "macbook")
                    .font(.caption2)
                Text("macOS native client")
                    .font(.caption2)
            }
            .foregroundStyle(Color.white.opacity(0.45))
            .padding(.horizontal, 10)
            .padding(.bottom, 6)
        }
        .padding(14)
        .background(
            LinearGradient(
                colors: [
                    Color(red: 0.075, green: 0.094, blue: 0.168),
                    Color(red: 0.063, green: 0.082, blue: 0.148)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }

    // MARK: - Header

    private var headerView: some View {
        HStack(spacing: 16) {
            Image(systemName: mode.icon)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(Color.white)
                .frame(width: 44, height: 44)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(mode.tint.opacity(0.25))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(mode.tint.opacity(0.4), lineWidth: 1)
                )

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(Color.white)
                Text(mode.subtitle)
                    .font(.subheadline)
                    .foregroundStyle(Color.white.opacity(0.6))
            }

            Spacer()
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
        .background(Color(red: 0.082, green: 0.102, blue: 0.180).opacity(0.95))
    }

    // MARK: - Footer

    private var footerView: some View {
        HStack {
            Text("Select an option to create or import native projects.")
                .font(.caption)
                .foregroundStyle(Color.white.opacity(0.5))

            Spacer()

            Button("Cancel") { dismiss() }
                .keyboardShortcut(.cancelAction)
                .buttonStyle(.bordered)
                .controlSize(.regular)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
        .background(Color(red: 0.075, green: 0.094, blue: 0.168))
    }

    // MARK: - Content View

    @ViewBuilder
    private var contentView: some View {
        switch mode {
        case .create:
            actionPanel(
                icon: "sparkles",
                title: "Scaffold from starter models",
                description: "Choose an app, library, multiplatform, or command line tool template with full build structures, files, configurations, and sensible defaults automatically configured.",
                tint: Color(red: 0.106, green: 0.404, blue: 0.863),
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
                .tint(Color(red: 0.106, green: 0.404, blue: 0.863))
            }

        case .clone:
            GitCloneSheetView(viewModel: viewModel)
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.white.opacity(0.04))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )

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
                tint: .indigo,
                actionTitle: "Select Xcode Project",
                actionIcon: "app.badge"
            ) {
                Button { importXcodeProject() } label: {
                    Label("Select Xcode Project", systemImage: "app.badge")
                        .font(.headline)
                        .foregroundColor(.white)
                        .padding(.vertical, 10)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.indigo)
            }

        case .scproj:
            ImportProjView()
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.white.opacity(0.04))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
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
            HStack(alignment: .top, spacing: 18) {
                Image(systemName: icon)
                    .font(.system(size: 32, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 64, height: 64)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(tint.opacity(0.16))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(tint.opacity(0.3), lineWidth: 1)
                    )

                VStack(alignment: .leading, spacing: 6) {
                    Text(title)
                        .font(.title3.bold())
                        .foregroundColor(.white)
                    Text(description)
                        .font(.body)
                        .foregroundStyle(Color.white.opacity(0.7))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            HStack(spacing: 16) {
                Label("Dynamic scaffolding", systemImage: "checkmark.seal.fill")
                Label("Universal architecture", systemImage: "desktopcomputer")
                Label("Integrated sessions", systemImage: "tray.full.fill")
            }
            .font(.caption.weight(.medium))
            .foregroundStyle(Color.white.opacity(0.55))

            actions()
                .frame(maxWidth: 280)
                .accessibilityLabel(actionTitle)
                .accessibilityHint("Starts the \(actionTitle.lowercased()) flow.")
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.white.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    private var title: String {
        switch mode {
        case .create: return "Create Project"
        case .importFolder: return "Import Folder"
        case .clone: return "Clone Repository"
        case .xcodeproj: return "Open Xcode Project"
        case .scproj: return "Open SwiftCode Project Archive"
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
