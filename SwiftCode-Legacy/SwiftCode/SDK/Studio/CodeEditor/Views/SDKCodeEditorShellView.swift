import AppKit
import SwiftUI

// MARK: - SDKCodeEditorShellView
//
// The Studio Code Editor section's root view: an Xcode-like arrangement of
// file navigator (left), tabbed editor + visual `swiftcode.json` manifest
// editor (center), find bar & build/validate toolbar (top), and console +
// structured compiler/manifest diagnostics panel (bottom).

@MainActor
public struct SDKCodeEditorShellView: View {
    @ObservedObject private var editorState: SDKCodeEditorState
    @StateObject private var defaultEditorState = SDKCodeEditorState()
    @StateObject private var findCoordinator = SDKCodeFindCoordinator()

    private enum BottomTab: String, CaseIterable, Identifiable {
        case console = "Console"
        case diagnostics = "Diagnostics"
        var id: String { rawValue }
    }

    @State private var showingFindBar = false
    @State private var showingConsole = true
    @State private var showingSnippets = false
    @State private var showingGoToLine = false
    @State private var goToLineInput = ""
    @State private var bottomTab: BottomTab = .console
    @State private var showVisualManifestEditor = true

    // Build & validation state
    @State private var buildKind: SDKBuildRunKind = .typescriptExtension
    @State private var schemeOrEntry: String = ""
    @State private var activeBuildTaskID: UUID?
    @State private var isValidating = false

    public init(editorState: SDKCodeEditorState? = nil) {
        let resolved = editorState ?? SDKCodeEditorState()
        self._editorState = ObservedObject(wrappedValue: resolved)
    }

    public var body: some View {
        NavigationSplitView {
            SDKCodeFileNavigatorView(editorState: editorState)
                .navigationSplitViewColumnWidth(min: 180, ideal: 240)
        } detail: {
            SDKVerticalSplitView(
                top: editorColumn,
                bottom: bottomPanel
                    .frame(minHeight: 150),
                isBottomVisible: $showingConsole
            )
        }
        .navigationTitle("Code Editor")
        .toolbar { shellToolbar }
        .sheet(isPresented: $showingSnippets) {
            SDKCodeSnippetLibraryView(
                editorState: editorState,
                onInsertIntoManifest: { capID, reason in
                    _ = editorState.addCapabilityToManifest(capabilityId: capID, reason: reason)
                }
            )
            .environmentObject(editorState)
            .frame(minWidth: 720, minHeight: 520)
        }
        .onChange(of: editorState.diagnostics.count) { _, newCount in
            if newCount > 0 {
                showingConsole = true
            }
        }
    }

    // MARK: - Editor column

    private var isManifestActiveTab: Bool {
        editorState.activeTab?.document.displayName == "swiftcode.json"
    }

    private var editorColumn: some View {
        VStack(spacing: 0) {
            if showingFindBar {
                SDKCodeFindBarView(
                    state: editorState,
                    coordinator: findCoordinator,
                    onDismiss: { showingFindBar = false }
                )
                Divider()
            }
            HStack(spacing: 0) {
                SDKCodeEditorTabBarView(state: editorState)
                if isManifestActiveTab {
                    Spacer(minLength: 8)
                    Picker("Manifest Mode", selection: $showVisualManifestEditor) {
                        Text("Visual Editor").tag(true)
                        Text("Text Buffer").tag(false)
                    }
                    .pickerStyle(.segmented)
                    .controlSize(.small)
                    .frame(width: 190)
                    .padding(.trailing, 8)
                }
            }
            if isManifestActiveTab && showVisualManifestEditor {
                SDKManifestEditorView(
                    manifestFileURL: editorState.activeTab?.document.fileURL,
                    editorState: editorState
                )
            } else {
                SDKCodeEditorView(
                    state: editorState,
                    highlighter: SDKKeywordHighlighter(),
                    findCoordinator: findCoordinator
                )
            }
        }
    }

    // MARK: - Bottom Panel (Console + Structured Diagnostics)

    private var bottomPanel: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Picker("", selection: $bottomTab) {
                    Text("Console (\(editorState.consoleEntries.count))")
                        .tag(BottomTab.console)
                    Text("Diagnostics (\(editorState.diagnostics.count))")
                        .tag(BottomTab.diagnostics)
                }
                .pickerStyle(.segmented)
                .frame(width: 280)

                if !editorState.diagnostics.isEmpty {
                    let errors = editorState.diagnostics.filter { $0.severity == .error }.count
                    let warnings = editorState.diagnostics.filter { $0.severity == .warning }.count
                    HStack(spacing: 8) {
                        if errors > 0 {
                            Label("\(errors) error(s)", systemImage: "xmark.octagon.fill")
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                        if warnings > 0 {
                            Label("\(warnings) warning(s)", systemImage: "exclamationmark.triangle.fill")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                    }
                }
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .liquidGlass(style: .subtle, cornerRadius: 8)
            .padding(6)
            Divider()

            switch bottomTab {
            case .console:
                SDKCodeConsoleView(state: editorState)
            case .diagnostics:
                diagnosticsListView
            }
        }
    }

    private var diagnosticsListView: some View {
        Group {
            if editorState.diagnostics.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "checkmark.seal")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                    Text("No compiler or manifest diagnostics")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(editorState.diagnostics) { diag in
                    Button {
                        if let url = diag.fileURL {
                            if url.lastPathComponent == "swiftcode.json" {
                                showVisualManifestEditor = false
                            }
                            editorState.navigateTo(
                                fileURL: url,
                                line: diag.line ?? 1,
                                column: diag.column
                            )
                        }
                    } label: {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Image(systemName: diag.severity == .error ? "xmark.octagon.fill" : (diag.severity == .warning ? "exclamationmark.triangle.fill" : "info.circle.fill"))
                                .foregroundStyle(diag.severity == .error ? .red : (diag.severity == .warning ? .orange : .blue))
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 6) {
                                    Text(diag.code)
                                        .font(.caption.monospaced())
                                        .fontWeight(.semibold)
                                    if let fileURL = diag.fileURL {
                                        Text("\(fileURL.lastPathComponent):\(diag.line ?? 1)")
                                            .font(.caption.monospaced())
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                Text(diag.message)
                                    .font(.callout)
                                    .foregroundStyle(.primary)
                                if let suggestion = diag.suggestion, !suggestion.isEmpty {
                                    Text(suggestion)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            if diag.fileURL != nil {
                                Image(systemName: "arrow.up.right.square")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 2)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .listStyle(.plain)
            }
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var shellToolbar: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            Button {
                toggleSidebar()
            } label: {
                Image(systemName: "sidebar.left")
            }
            .help("Toggle File Navigator")
        }
        ToolbarItemGroup(placement: .automatic) {
            Button {
                showingFindBar.toggle()
            } label: {
                Image(systemName: "magnifyingglass")
            }
            .help("Toggle Find Bar (⌘F)")
            .keyboardShortcut("f", modifiers: .command)

            Button {
                showingGoToLine.toggle()
            } label: {
                Image(systemName: "arrow.down.to.line.compact")
            }
            .help("Go to Line… (⌘L)")
            .keyboardShortcut("l", modifiers: .command)
            .popover(isPresented: $showingGoToLine) {
                HStack(spacing: 8) {
                    Text("Line:")
                        .font(.callout)
                    TextField("1", text: $goToLineInput)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 72)
                        .onSubmit {
                            jumpToEnteredLine()
                        }
                    Button("Go") {
                        jumpToEnteredLine()
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(12)
            }

            Button {
                openFilePanel()
            } label: {
                Image(systemName: "folder")
            }
            .help("Open File… (⌘O)")
            .keyboardShortcut("o", modifiers: .command)

            Button {
                openManifestInEditor()
            } label: {
                Label("swiftcode.json", systemImage: "doc.badge.gearshape")
            }
            .help("Open Visual swiftcode.json Manifest Editor")
            .disabled(editorState.projectRootURL == nil)

            Picker("Build Target", selection: $buildKind) {
                ForEach(SDKBuildRunKind.allCases, id: \.self) { kind in
                    Text(kind.displayName).tag(kind)
                }
            }
            .frame(width: 165)
            .help("Select Build / Run target kind")

            if buildKind != .typescriptExtension {
                TextField(
                    buildKind == .xcodebuildSwift ? "Scheme (optional)" : "Script (e.g. dist/index.js)",
                    text: $schemeOrEntry
                )
                .textFieldStyle(.roundedBorder)
                .frame(width: 145)
            }

            Button {
                runValidation()
            } label: {
                Label("Validate", systemImage: "checkmark.shield")
            }
            .disabled(editorState.projectRootURL == nil || isValidating || activeBuildTaskID != nil)
            .help("Validate swiftcode.json manifest and capability usage")

            if let runningID = activeBuildTaskID {
                Button(role: .destructive) {
                    Task {
                        await SDKCodeBuildRunner.shared.cancel(taskID: runningID)
                        activeBuildTaskID = nil
                    }
                } label: {
                    Label("Stop", systemImage: "stop.fill")
                }
                .help("Cancel active build/run")
            } else {
                Button {
                    triggerBuildRun()
                } label: {
                    Label("Build", systemImage: "hammer.fill")
                }
                .keyboardShortcut("b", modifiers: .command)
                .disabled(editorState.projectRootURL == nil)
                .help("Save modified files, validate manifest, and build project (⌘B)")
            }

            Button {
                showingConsole.toggle()
            } label: {
                Image(systemName: "terminal")
            }
            .help("Toggle Console & Diagnostics")
        }
        ToolbarItem(placement: .primaryAction) {
            Button("Snippets") {
                showingSnippets = true
            }
            .help("Browse SDK Capability Snippets & Insert Code")
        }
    }

    // MARK: - Actions

    private func jumpToEnteredLine() {
        let trimmed = goToLineInput.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = trimmed.split(separator: ":")
        if let line = parts.first.flatMap({ Int($0) }) {
            let col = parts.count > 1 ? Int(parts[1]) : nil
            editorState.navigateActiveTabTo(line: line, column: col)
        }
        showingGoToLine = false
    }

    private func openManifestInEditor() {
        guard let root = editorState.projectRootURL else { return }
        let manifestURL = root.appendingPathComponent("swiftcode.json")
        if FileManager.default.fileExists(atPath: manifestURL.path) {
            showVisualManifestEditor = true
            _ = try? editorState.openFile(manifestURL)
        } else {
            editorState.appendConsole(.system("No swiftcode.json found in \(root.lastPathComponent)."))
            showingConsole = true
        }
    }

    private func runValidation() {
        guard let root = editorState.projectRootURL else { return }
        isValidating = true
        showingConsole = true
        Task {
            let ok = await SDKCodeBuildRunner.shared.validateProject(at: root, into: editorState)
            isValidating = false
            if !ok {
                bottomTab = .diagnostics
            }
        }
    }

    private func triggerBuildRun() {
        guard let root = editorState.projectRootURL else { return }
        showingConsole = true
        let req = SDKBuildRunRequest(
            projectRoot: root,
            kind: buildKind,
            schemeOrEntry: schemeOrEntry.isEmpty ? nil : schemeOrEntry
        )
        activeBuildTaskID = req.taskID
        Task {
            await SDKCodeBuildRunner.shared.run(req, into: editorState)
            activeBuildTaskID = nil
            if editorState.diagnostics.contains(where: { $0.severity == .error }) {
                bottomTab = .diagnostics
            }
        }
    }

    private func toggleSidebar() {
        _ = NSApp.keyWindow?.firstResponder?.tryToPerform(
            #selector(NSSplitViewController.toggleSidebar(_:)),
            with: nil
        )
    }

    private func openFilePanel() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try editorState.openFile(url)
        } catch let error as SDKCodeEditorError {
            switch error {
            case .unreadableFile(let failedURL, let reason):
                editorState.appendConsole(.system(
                    "Could not open \(failedURL.lastPathComponent): \(reason)"
                ))
                showingConsole = true
            }
        } catch {
            editorState.appendConsole(.system("Could not open file: \(error.localizedDescription)"))
            showingConsole = true
        }
    }
}

// MARK: - SDKVerticalSplitView

struct SDKVerticalSplitView<Top: View, Bottom: View>: NSViewRepresentable {
    let top: Top
    let bottom: Bottom
    @Binding var isBottomVisible: Bool

    func makeNSView(context: Context) -> NSSplitView {
        let splitView = NSSplitView()
        splitView.isVertical = false
        splitView.dividerStyle = .thin
        splitView.autosaveName = "SDKCodeEditorConsoleSplit"

        let topHost = NSHostingView(rootView: top)
        let bottomHost = NSHostingView(rootView: bottom)
        context.coordinator.topHost = topHost
        context.coordinator.bottomHost = bottomHost

        splitView.addSubview(topHost)
        if isBottomVisible {
            splitView.addSubview(bottomHost)
            splitView.setHoldingPriority(.defaultHigh, forSubviewAt: 1)
        }
        return splitView
    }

    func updateNSView(_ splitView: NSSplitView, context: Context) {
        if let topHost = context.coordinator.topHost {
            topHost.rootView = top
        }
        guard let bottomHost = context.coordinator.bottomHost else { return }
        bottomHost.rootView = bottom

        let isShown = bottomHost.superview != nil
        if isBottomVisible != isShown {
            if isBottomVisible {
                splitView.addSubview(bottomHost)
                splitView.setHoldingPriority(.defaultHigh, forSubviewAt: splitView.subviews.count - 1)
            } else {
                bottomHost.removeFromSuperview()
            }
            splitView.adjustSubviews()
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator {
        var topHost: NSHostingView<Top>?
        var bottomHost: NSHostingView<Bottom>?
    }
}
