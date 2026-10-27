import SwiftUI
import AppKit
import os

@MainActor
public struct SwiftCodeWelcomeView: View {
    @Environment(ProjectSessionStore.self) private var sessionStore
    @Environment(ThemeViewModel.self) private var themeVM

    @State private var welcomeVM = WelcomeViewModel()
    @State private var showingNewProjectSheet = false
    @State private var sheetInitialMode: NewProjectSheetView.SelectionMode = .create
    @State private var selectedProjectID: UUID?

    // Project action confirmations
    @State private var activeConfirmation: ActiveConfirmation?
    @State private var showConfirmationAlert = false
    @State private var errorMessage: String?
    @State private var showError = false

    enum ActiveConfirmation: Identifiable {
        case remove(Project)
        case delete(Project)

        var id: UUID {
            switch self {
            case .remove(let project): return project.id
            case .delete(let project): return project.id
            }
        }
    }

    private var confirmationAlertTitle: String {
        switch activeConfirmation {
        case .remove: return "Remove From Recent Projects"
        case .delete: return "Delete Project From Disk"
        case .none: return ""
        }
    }

    private var versionString: String {
        let shortVersion = (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "1.0.0"
        let bundleVersion = (Bundle.main.infoDictionary?["CFBundleVersion"] as? String) ?? "1"
        return "Version \(shortVersion) (\(bundleVersion))"
    }

    public init() {}

    public var body: some View {
        ZStack {
            // Background Window Accessor for strict styling enforcement
            WelcomeWindowAccessor { window in
                applyWelcomeWindowStyle(to: window)
            }

            // Main Two-Column Layout (Matching Screenshot: 800 x 480)
            HStack(spacing: 0) {
                // Left Column: App Branding & Quick Actions
                leftPane
                    .frame(width: 470)

                // Subtle vertical divider line
                Rectangle()
                    .fill(Color.white.opacity(0.08))
                    .frame(width: 1)

                // Right Column: Recent Projects List
                rightPane
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            // Loading / Error Overlay
            loadingOverlay
        }
        .frame(width: 800, height: 480)
        .background(
            VisualEffectView(material: .underWindowBackground, blendingMode: .behindWindow)
                .overlay(Color.black.opacity(0.35))
        )
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showingNewProjectSheet) {
            NewProjectSheetView(viewModel: welcomeVM, initialMode: sheetInitialMode)
        }
        .alert(
            confirmationAlertTitle,
            isPresented: $showConfirmationAlert,
            presenting: activeConfirmation
        ) { config in
            switch config {
            case .remove(let project):
                Button("Remove from Recents", role: .destructive) {
                    sessionStore.removeProjectFromRecents(project)
                    if selectedProjectID == project.id {
                        selectedProjectID = sessionStore.projects.first?.id
                    }
                }
                Button("Cancel", role: .cancel) {}
            case .delete(let project):
                Button("Delete From Disk", role: .destructive) {
                    do {
                        try sessionStore.deleteProject(project)
                        if selectedProjectID == project.id {
                            selectedProjectID = sessionStore.projects.first?.id
                        }
                    } catch {
                        showErrorMessage(error.localizedDescription)
                    }
                }
                Button("Cancel", role: .cancel) {}
            }
        } message: { config in
            switch config {
            case .remove(let project):
                Text("Are you sure you want to remove \"\(project.displayName)\" from the recents list? Files on disk will remain untouched.")
            case .delete(let project):
                Text("Are you sure you want to permanently delete \"\(project.displayName)\" from your disk? This cannot be undone.")
            }
        }
        .alert("Error", isPresented: $showError, presenting: errorMessage) { _ in
            Button("OK") {}
        } message: { msg in Text(msg) }
        .onAppear {
            if let window = NSApplication.shared.windows.first(where: { $0.isVisible }) {
                applyWelcomeWindowStyle(to: window)
            }
            if selectedProjectID == nil {
                selectedProjectID = sessionStore.projects.first?.id
            }
        }
        .onDisappear {
            if let window = NSApplication.shared.windows.first(where: { $0.isVisible }) {
                restoreStandardWindowStyle(for: window)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { notification in
            if let window = notification.object as? NSWindow, window.isVisible {
                applyWelcomeWindowStyle(to: window)
            }
        }
    }

    // MARK: - Left Column (Hero & Action Buttons)

    private var leftPane: some View {
        ZStack {
            VisualEffectView(material: .sidebar, blendingMode: .behindWindow)
                .overlay(Color.black.opacity(0.35))
                .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer().frame(height: 52)

                // App Icon centered in a squircle with shadow
                appIconView

                // Title: "SwiftCode"
                Text("SwiftCode")
                    .font(.system(size: 32, weight: .bold, design: .default))
                    .foregroundStyle(Color.white)
                    .padding(.top, 14)

                // Subtitle: Version dynamically pulled from Bundle info
                Text(versionString)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(Color(red: 0.62, green: 0.67, blue: 0.77))
                    .padding(.top, 4)

                Spacer().frame(height: 32)

                // Buttons List (matching the screenshot pill style)
                VStack(spacing: 12) {
                    WelcomePillButton(
                        title: "Create Project",
                        systemImage: "plus.app"
                    ) {
                        sheetInitialMode = .create
                        showingNewProjectSheet = true
                    }

                    WelcomePillButton(
                        title: "Clone Git Repository...",
                        systemImage: "arrow.down.doc"
                    ) {
                        sheetInitialMode = .clone
                        showingNewProjectSheet = true
                    }

                    WelcomePillButton(
                        title: "Open File or Folder...",
                        systemImage: "folder"
                    ) {
                        openFileOrFolder()
                    }
                }
                .padding(.horizontal, 40)

                Spacer(minLength: 24)
            }
        }
    }

    @ViewBuilder
    private var appIconView: some View {
        Group {
            if let icon = NSImage(named: NSImage.applicationIconName) ?? NSImage(named: "AppIcon") {
                Image(nsImage: icon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else if let icon = NSImage(named: AppIconManager.shared.resolvedPreviewImageName(for: AppIconManager.shared.currentVariant)) {
                Image(nsImage: icon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(Color(red: 0.12, green: 0.15, blue: 0.25))
                    Image(systemName: "swift")
                        .font(.system(size: 48, weight: .semibold))
                        .foregroundStyle(Color.orange)
                }
            }
        }
        .frame(width: 96, height: 96)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.45), radius: 14, x: 0, y: 7)
    }

    // MARK: - Right Column (Recent Projects)

    private var rightPane: some View {
        ZStack {
            VisualEffectView(material: .underWindowBackground, blendingMode: .behindWindow)
                .overlay(
                    LinearGradient(
                        colors: [
                            Color(red: 0.082, green: 0.137, blue: 0.337).opacity(0.35),
                            Color(red: 0.063, green: 0.106, blue: 0.267).opacity(0.45)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .overlay(Color.black.opacity(0.2))
                .ignoresSafeArea()

            if sessionStore.projects.isEmpty {
                emptyProjectsView
            } else {
                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(sessionStore.projects) { project in
                            RecentProjectRow(
                                project: project,
                                isSelected: selectedProjectID == project.id,
                                onSelect: {
                                    selectedProjectID = project.id
                                },
                                onOpen: {
                                    Task {
                                        await sessionStore.openProject(project)
                                    }
                                }
                            )
                            .contextMenu {
                                projectContextMenu(for: project)
                            }
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 12)
                }
            }
        }
    }

    private var emptyProjectsView: some View {
        VStack(spacing: 12) {
            Image(systemName: "folder")
                .font(.system(size: 38, weight: .light))
                .foregroundStyle(Color.white.opacity(0.35))

            Text("No Recent Projects")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.75))

            Text("Opened and created projects will appear here.")
                .font(.system(size: 11))
                .foregroundStyle(Color.white.opacity(0.45))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Context Menu

    @ViewBuilder
    private func projectContextMenu(for project: Project) -> some View {
        Button {
            Task {
                await sessionStore.openProject(project)
            }
        } label: {
            Label("Open Project", systemImage: "arrow.right.circle")
        }

        Button {
            revealInFinder(project)
        } label: {
            Label("Reveal in Finder", systemImage: "folder")
        }

        Button {
            copyProjectPath(project)
        } label: {
            Label("Copy Path", systemImage: "doc.on.doc")
        }

        Divider()

        Button {
            activeConfirmation = .remove(project)
            showConfirmationAlert = true
        } label: {
            Label("Remove From Recent Projects", systemImage: "bookmark.slash")
        }

        Button(role: .destructive) {
            activeConfirmation = .delete(project)
            showConfirmationAlert = true
        } label: {
            Label("Delete Project From Disk...", systemImage: "trash")
        }
    }

    // MARK: - Actions & Helpers

    private func openFileOrFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Open"
        if panel.runModal() == .OK, let url = panel.url {
            Task {
                do {
                    var targetURL = url
                    var isDir: ObjCBool = false
                    if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), !isDir.boolValue {
                        if url.pathExtension != "xcodeproj" && url.pathExtension != "xcworkspace" {
                            targetURL = url.deletingLastPathComponent()
                        }
                    }
                    let project = try await sessionStore.importProject(from: targetURL)
                    await sessionStore.openProject(project)
                } catch {
                    showErrorMessage(error.localizedDescription)
                }
            }
        }
    }

    private func revealInFinder(_ project: Project) {
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: project.directoryURL.path)
    }

    private func copyProjectPath(_ project: Project) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(project.directoryURL.path, forType: .string)
    }

    private func showErrorMessage(_ message: String) {
        errorMessage = message
        showError = true
    }

    // MARK: - Window Configuration (Strict Screenshot Parity)

    private func applyWelcomeWindowStyle(to window: NSWindow) {
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true

        // The WelcomeView is NOT allowed to be minimized, resized or full screen
        window.styleMask.remove([.resizable, .miniaturizable])
        window.styleMask.insert([.titled, .closable, .fullSizeContentView])

        let fixedSize = NSSize(width: 800, height: 480)
        window.minSize = fixedSize
        window.maxSize = fixedSize
        window.showsResizeIndicator = false
        window.collectionBehavior = []

        // Remove/hide the minimize button and zoom button so ONLY the close button shows
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true
        window.standardWindowButton(.closeButton)?.isHidden = false

        if window.frame.size != fixedSize {
            window.setContentSize(fixedSize)
            window.center()
        }
    }

    private func restoreStandardWindowStyle(for window: NSWindow) {
        window.isOpaque = true
        window.backgroundColor = nil
        window.showsResizeIndicator = true
        window.isMovableByWindowBackground = false
        window.titleVisibility = .visible
        window.titlebarAppearsTransparent = false
        window.styleMask.insert([.resizable, .miniaturizable, .closable])
        window.collectionBehavior = [.fullScreenPrimary]
        window.standardWindowButton(.miniaturizeButton)?.isHidden = false
        window.standardWindowButton(.zoomButton)?.isHidden = false
        window.standardWindowButton(.closeButton)?.isHidden = false
        window.minSize = NSSize(width: 900, height: 600)
        window.maxSize = NSSize(width: 10000, height: 10000)
    }

    // MARK: - Loading Overlay

    @ViewBuilder
    private var loadingOverlay: some View {
        if sessionStore.state != .idle && sessionStore.state != .cancelled {
            ZStack {
                Color.black.opacity(0.4)
                    .ignoresSafeArea()

                VStack(spacing: 16) {
                    switch sessionStore.state {
                    case .resolving, .loading:
                        ProgressView()
                            .controlSize(.large)
                        Text("Opening project...")
                            .font(.headline)
                            .foregroundStyle(Color.white)
                        Button("Cancel") {
                            sessionStore.cancelLoad()
                        }
                        .buttonStyle(.bordered)
                    case .failed(let error):
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 38))
                            .foregroundColor(.red)
                        Text("Failed to open project")
                            .font(.headline)
                            .foregroundStyle(Color.white)
                        Text(error.localizedDescription)
                            .font(.subheadline)
                            .foregroundStyle(Color.white.opacity(0.7))
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: 320)
                        HStack(spacing: 12) {
                            Button("Cancel") {
                                sessionStore.closeProject()
                            }
                            .buttonStyle(.bordered)

                            Button("Retry") {
                                sessionStore.state = .idle
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    default:
                        EmptyView()
                    }
                }
                .padding(32)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(.ultraThinMaterial))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                )
            }
        }
    }
}

// MARK: - Typealias for seamless compatibility
public typealias WelcomeView = SwiftCodeWelcomeView

// MARK: - Pill Button Component (Dark Rounded Pill Matching Screenshot)

struct WelcomePillButton: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: systemImage)
                    .font(.system(size: 18, weight: .regular))
                    .foregroundStyle(Color.white.opacity(0.9))
                    .frame(width: 22, height: 22)

                Text(title)
                    .font(.system(size: 13.5, weight: .medium))
                    .foregroundStyle(Color.white)

                Spacer()
            }
            .padding(.horizontal, 16)
            .frame(width: 340, height: 44)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.white.opacity(isHovering ? 0.12 : 0.055))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.white.opacity(isHovering ? 0.14 : 0.07), lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.snappy(duration: 0.15)) {
                isHovering = hovering
            }
        }
    }
}

// MARK: - Recent Project Row (Matching Active Blue Card from Screenshot)

struct RecentProjectRow: View {
    let project: Project
    let isSelected: Bool
    let onSelect: () -> Void
    let onOpen: () -> Void

    @State private var isHovering = false

    private var truncatedPath: String {
        let fullPath = project.directoryURL.path
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if fullPath.hasPrefix(home) {
            return "~" + fullPath.dropFirst(home.count)
        }
        return fullPath
    }

    var body: some View {
        Button(action: {
            onSelect()
            onOpen()
        }) {
            HStack(spacing: 12) {
                macOSFolderIcon
                    .frame(width: 32, height: 32)

                VStack(alignment: .leading, spacing: 2) {
                    Text(project.displayName)
                        .font(.system(size: 13.5, weight: .bold))
                        .foregroundStyle(Color.white)
                        .lineLimit(1)

                    Text(truncatedPath)
                        .font(.system(size: 11, weight: .regular))
                        .foregroundStyle(isSelected ? Color.white.opacity(0.85) : Color.white.opacity(0.55))
                        .lineLimit(1)
                        .truncationMode(.head)
                }

                Spacer(minLength: 4)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(
                        isSelected
                            ? Color(red: 0.106, green: 0.404, blue: 0.863) // Vibrant Royal Blue Accent
                            : (isHovering ? Color.white.opacity(0.08) : Color.clear)
                    )
            )
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovering = hovering
        }
    }

    @ViewBuilder
    private var macOSFolderIcon: some View {
        if FileManager.default.fileExists(atPath: project.directoryURL.path) {
            let icon = NSWorkspace.shared.icon(forFile: project.directoryURL.path)
            Image(nsImage: icon)
                .resizable()
                .aspectRatio(contentMode: .fit)
        } else {
            Image(systemName: "folder.fill")
                .font(.system(size: 26))
                .foregroundStyle(
                    LinearGradient(
                        colors: [
                            Color(red: 0.35, green: 0.72, blue: 0.98),
                            Color(red: 0.18, green: 0.52, blue: 0.92)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
        }
    }
}

// MARK: - Window Accessor Representable

struct WelcomeWindowAccessor: NSViewRepresentable {
    let onWindow: (NSWindow) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            if let window = view.window {
                onWindow(window)
            }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            if let window = nsView.window {
                onWindow(window)
            }
        }
    }
}
