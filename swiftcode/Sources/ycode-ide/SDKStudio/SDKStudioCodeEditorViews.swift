import Foundation
import YcodeIDEShell
import SwiftUI
import SwiftCodeExtensions
import SwiftCodeSDKStudio

@MainActor
struct SDKCodeEditorShellView: View {
    @Bindable var editorState: SDKCodeEditorState
    @State private var findCoordinator = SDKCodeFindCoordinator()
    @State private var showingFindBar = false
    @State private var showingConsole = true
    @State private var showingSnippets = false
    @State private var showingGoToLine = false
    @State private var goToLineInput = ""
    @State private var bottomTab: BottomTab = .console
    @State private var showVisualManifestEditor = false
    @State private var buildKind: SDKBuildRunKind = .typescriptExtension
    @State private var schemeOrEntry = ""
    @State private var activeBuildTaskID: UUID?
    @State private var isValidating = false
    @State private var showSidebar = true
    @State private var saveError: String?
    @State private var findAdapter: SDKCodeFindAdapter?

    private enum BottomTab: String, CaseIterable {
        case console = "Console"
        case diagnostics = "Diagnostics"
        case snippets = "Snippets"
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            if showingGoToLine {
                HStack(spacing: 8) {
                    Text("Go to line:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField("Line number", text: $goToLineInput)
                        .frame(width: 90)
                        .onSubmit { jumpToEnteredLine() }
                    Button("Go") { jumpToEnteredLine() }
                    Button("Cancel") { showingGoToLine = false; goToLineInput = "" }
                    Spacer()
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
            }
            Divider()
            HStack(spacing: 0) {
                if showSidebar {
                    SDKCodeFileNavigatorView(editorState: editorState)
                        .frame(width: 220)
                    Divider()
                }
                VStack(spacing: 0) {
                    SDKCodeEditorTabBarView(editorState: editorState)
                    Divider()
                    editorPane
                    if showingFindBar {
                        Divider()
                        SDKCodeFindBarView(coordinator: findCoordinator, editorState: editorState) {
                            showingFindBar = false
                        }
                    }
                    if showingConsole {
                        Divider()
                        bottomPanel
                            .frame(height: 180)
                    }
                }
            }
        }
        .onAppear {
            editorState.checkExternalModifications()
            let adapter = SDKCodeFindAdapter(editorState: editorState)
            findAdapter = adapter
            findCoordinator.editor = adapter
        }
        .sheet(isPresented: $showVisualManifestEditor) {
            if let manifestURL = editorState.projectRootURL?.appendingPathComponent("swiftcode.json") {
                SDKManifestEditorView(manifestFileURL: manifestURL, editorState: editorState)
            }
        }
        .alert("Save failed", isPresented: Binding(
            get: { saveError != nil }, set: { if !$0 { saveError = nil } }
        )) {
            Button("OK", role: .cancel) { saveError = nil }
        } message: {
            Text(saveError ?? "")
        }
    }

    private var toolbar: some View {
        HStack(spacing: 12) {
            Button(action: { showSidebar.toggle() }, label: {
                Image(systemName: "sidebar.left")
            }).help("Toggle sidebar")
            Spacer()
            if editorState.projectRootURL == nil {
                Text("No project open").foregroundStyle(.secondary)
            } else {
                Text(editorState.projectRootURL?.lastPathComponent ?? "")
                    .font(.callout.monospaced())
            }
            Button("Validate") { runValidation() }
                .disabled(isValidating || editorState.projectRootURL == nil)
            Button("Manifest") { showVisualManifestEditor = true }
                .disabled(editorState.projectRootURL == nil)
            Button("Find") { showingFindBar.toggle() }
                .keyboardShortcut("f", modifiers: .command)
            Button("Go to Line…") { showingGoToLine = true }
            Picker("Build", selection: $buildKind) {
                ForEach(SDKBuildRunKind.allCases, id: \.self) { kind in
                    Text(kind.displayName).tag(kind)
                }
            }
            .pickerStyle(.menu)
            .frame(width: 170)
            if activeBuildTaskID == nil {
                Button("Build / Run") { triggerBuildRun() }
                    .buttonStyle(.borderedProminent)
                    .disabled(editorState.projectRootURL == nil)
            } else {
                Button("Stop") { stopBuild() }
                    .buttonStyle(.bordered)
            }
            Button(action: { showingSnippets.toggle() }, label: {
                Image(systemName: "square.grid.2x2")
            }).help("Snippets")
            Button(action: { showingConsole.toggle() }, label: {
                Image(systemName: "apple.terminal")
            }).help("Console")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
    }

    private var editorPane: some View {
        Group {
            if let tab = editorState.activeTab {
                let doc = tab.document
                VStack(alignment: .leading, spacing: 0) {
                    if editorState.externalModificationTabIDs.contains(tab.id) {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                            Text("This file changed on disk.")
                            Button("Reload") { try? editorState.reloadTabFromDisk(tab.id) }
                            Button("Keep Mine") { editorState.dismissExternalModification(for: tab.id) }
                            Spacer()
                        }
                        .font(.caption)
                        .padding(6)
                        .background(Color.yellow.opacity(0.15))
                    }
                    TextEditor(text: Binding(
                        get: { editorState.activeTab?.document.text ?? "" },
                        set: { editorState.updateText($0, for: tab.id) }
                    ))
                    .font(.body.monospaced())
                    .onChange(of: doc.text) { _, _ in
                        findCoordinator.editorTextDidChange()
                    }
                    HStack {
                        Text(doc.language.displayName)
                        Text(doc.displayName + (doc.isDirty ? " •" : ""))
                        Spacer()
                        Text("\(doc.text.components(separatedBy: .newlines).count) lines")
                        Button("Save") { saveActiveDocument() }
                            .keyboardShortcut("s", modifiers: .command)
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                }
            } else {
                SDKStudioEmptyState(title: "No File Open", systemImage: "doc", description: "Open a file from the navigator, or create a new untitled tab.")
                .toolbar {
                    Button("New Untitled Tab") {
                        _ = editorState.newUntitledTab()
                    }
                }
            }
        }
    }

    private var bottomPanel: some View {
        VStack(spacing: 0) {
            Picker("Panel", selection: $bottomTab) {
                ForEach(BottomTab.allCases, id: \.self) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding(6)
            switch bottomTab {
            case .console:
                SDKCodeConsoleView(editorState: editorState)
            case .diagnostics:
                SDKCodeDiagnosticsView(editorState: editorState)
            case .snippets:
                SDKCodeSnippetLibraryView(editorState: editorState)
            }
        }
    }

    private func saveActiveDocument() {
        guard let tab = editorState.activeTab else { return }
        if tab.document.fileURL == nil {
            saveError = "Untitled documents need Save As — use the main IDE to choose a location."
            return
        }
        if !editorState.saveTab(tab.id) {
            saveError = "Could not save \(tab.document.displayName)."
        }
    }

    private func jumpToEnteredLine() {
        guard let line = Int(goToLineInput.trimmingCharacters(in: .whitespaces)) else { return }
        editorState.navigateActiveTabTo(line: line)
        goToLineInput = ""
        showingGoToLine = false
    }

    private func runValidation() {
        guard let root = editorState.projectRootURL else { return }
        isValidating = true
        Task {
            _ = await SDKCodeBuildRunner.shared.validateProject(at: root, into: editorState)
            isValidating = false
            bottomTab = .diagnostics
            showingConsole = true
        }
    }

    private func triggerBuildRun() {
        guard let root = editorState.projectRootURL else { return }
        let request = SDKBuildRunRequest(projectRoot: root, kind: buildKind,
                                         schemeOrEntry: schemeOrEntry.isEmpty ? nil : schemeOrEntry)
        activeBuildTaskID = request.taskID
        bottomTab = .console
        showingConsole = true
        Task {
            await SDKCodeBuildRunner.shared.run(request, into: editorState)
            activeBuildTaskID = nil
        }
    }

    private func stopBuild() {
        guard let taskID = activeBuildTaskID else { return }
        Task {
            await SDKCodeBuildRunner.shared.cancel(taskID: taskID)
            activeBuildTaskID = nil
        }
    }
}

@MainActor
private final class SDKCodeFindAdapter: SDKCodeFindableEditor {
    weak var editorState: SDKCodeEditorState?

    init(editorState: SDKCodeEditorState) {
        self.editorState = editorState
    }

    var findableText: String { editorState?.activeDocument?.text ?? "" }

    func selectFindRange(_ range: Range<Int>) {}
}

struct SDKCodeEditorTabBarView: View {
    @Bindable var editorState: SDKCodeEditorState

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 2) {
                ForEach(editorState.tabs) { tab in
                    HStack(spacing: 4) {
                        Button(action: { editorState.activateTab(tab.id) }) {
                            HStack(spacing: 4) {
                                Text(tab.document.displayName)
                                if tab.document.isDirty { Text("•") }
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(tab.isActive ? Color.accentColor.opacity(0.15) : Color.clear,
                                        in: RoundedRectangle(cornerRadius: 6))
                        }
                        .buttonStyle(.plain)
                        Button(action: { editorState.closeTab(tab.id) }) {
                            Image(systemName: "xmark").font(.caption2)
                        }
                        .buttonStyle(.plain)
                        .help("Close \(tab.document.displayName)")
                    }
                }
                Button(action: { _ = editorState.newUntitledTab() }) {
                    Image(systemName: "plus")
                }
                .buttonStyle(.plain)
                .help("New untitled tab")
            }
            .padding(.horizontal, 4)
        }
        .frame(height: 30)
    }
}

struct SDKCodeFileNavigatorView: View {
    @Bindable var editorState: SDKCodeEditorState
    @State private var rootPathText: String = ""
    @State private var tree: [SDKCodeFileNode] = []
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SDKCodeProjectRootView(rootURL: editorState.projectRootURL) { url in
                editorState.setProjectRoot(url)
                refreshTree()
            }
            if let errorMessage {
                Text(errorMessage).font(.caption).foregroundStyle(.red).padding(6)
            }
            if editorState.projectRootURL == nil {
                SDKStudioEmptyState(title: "No Project Open", systemImage: "folder", description: "Open a project folder to browse its files.")
            } else {
                List {
                    ForEach(tree) { node in
                        SDKCodeFileTreeRow(node: node, depth: 0, editorState: editorState,
                                           onToggle: { toggle(node) })
                    }
                }
                .listStyle(.sidebar)
            }
            HStack {
                Button("New File") { createEntry(isDirectory: false) }
                Button("New Folder") { createEntry(isDirectory: true) }
                Spacer()
                Button(action: { _ = editorState.newUntitledTab() }) {
                    Image(systemName: "doc.badge.plus")
                }.help("New untitled tab")
            }
            .font(.caption)
            .padding(6)
        }
        .onAppear {
            rootPathText = editorState.projectRootURL?.path ?? ""
            refreshTree()
        }
        .onChange(of: editorState.projectRootURL) { _, _ in refreshTree() }
    }

    private func refreshTree() {
        guard let root = editorState.projectRootURL else { tree = []; return }
        tree = SDKCodeFileNode.loadChildren(of: root)
    }

    private func toggle(_ node: SDKCodeFileNode) {
        tree = tree.map { current in
            guard current.id == node.id else { return current }
            if current.needsLoading {
                return current.withChildren(SDKCodeFileNode.loadChildren(of: current.url)).toggledExpanded()
            }
            return current.toggledExpanded()
        }
    }

    private func createEntry(isDirectory: Bool) {
        guard let root = editorState.projectRootURL else { return }
        let base = isDirectory ? "New Folder" : "Untitled"
        let ext = isDirectory ? "" : ".ts"
        var candidate = root.appendingPathComponent(base + ext)
        var n = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = root.appendingPathComponent("\(base) \(n)" + ext)
            n += 1
        }
        do {
            if isDirectory {
                try FileManager.default.createDirectory(at: candidate, withIntermediateDirectories: false)
            } else {
                try "".write(to: candidate, atomically: true, encoding: .utf8)
                _ = try editorState.openFile(candidate)
            }
            refreshTree()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct SDKCodeFileTreeRow: View {
    let node: SDKCodeFileNode
    let depth: Int
    let editorState: SDKCodeEditorState
    let onToggle: () -> Void

    var body: some View {
        if node.isDirectory {
            DisclosureGroup(isExpanded: Binding(
                get: { node.isExpanded },
                set: { _ in onToggle() }
            )) {
                if let children = node.children {
                    ForEach(children) { child in
                        SDKCodeFileTreeRow(node: child, depth: depth + 1, editorState: editorState,
                                           onToggle: onToggle)
                    }
                }
            } label: {
                Label(node.name, systemImage: "folder")
            }
        } else {
            Button(action: { _ = try? editorState.openFile(node.url) }) {
                HStack(spacing: 4) {
                    Image(systemName: iconFor(node))
                    Text(node.name).lineLimit(1)
                }
            }
            .buttonStyle(.plain)
        }
    }

    private func iconFor(_ node: SDKCodeFileNode) -> String {
        switch SDKCodeLanguage.infer(fromFileURL: node.url) {
        case .swift: return "swift"
        case .typescript, .javascript: return "chevron.left.forwardslash.chevron.right"
        case .json: return "curlybraces"
        case .markdown: return "doc.text"
        case .plaintext: return "doc"
        }
    }
}

struct SDKCodeProjectRootView: View {
    let rootURL: URL?
    let onSelectRoot: (URL) -> Void
    @State private var pathText: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Project").font(.caption).foregroundStyle(.secondary)
            HStack {
                TextField("/path/to/project", text: $pathText)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { submit() }
                Button("Open") { submit() }
            }
            if let rootURL {
                Text(rootURL.path).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .padding(6)
        .onAppear { pathText = rootURL?.path ?? "" }
        .onChange(of: rootURL) { _, new in pathText = new?.path ?? "" }
    }

    private func submit() {
        let path = pathText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty else { return }
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue else { return }
        onSelectRoot(URL(fileURLWithPath: path))
    }
}

struct SDKCodeFindBarView: View {
    @Bindable var coordinator: SDKCodeFindCoordinator
    @Bindable var editorState: SDKCodeEditorState
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
            TextField("Find in file", text: $editorState.findQuery)
                .textFieldStyle(.roundedBorder)
                .onChange(of: editorState.findQuery) { _, new in
                    coordinator.setQuery(new)
                }
                .onSubmit { coordinator.findNext() }
            Toggle("Aa", isOn: $coordinator.caseSensitive)
                .help("Case sensitive")
            Text(coordinator.matchSummaryText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(minWidth: 70, alignment: .leading)
            Button(action: { coordinator.findPrevious() }) {
                Image(systemName: "chevron.up")
            }
            .help("Previous match (⇧⌘G)")
            .disabled(!coordinator.hasMatches)
            Button(action: { coordinator.findNext() }) {
                Image(systemName: "chevron.down")
            }
            .help("Next match (⌘G)")
            .disabled(!coordinator.hasMatches)
            Button(action: onDismiss) {
                Image(systemName: "xmark")
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .onAppear {
            coordinator.setQuery(editorState.findQuery)
        }
    }
}

struct SDKCodeConsoleView: View {
    @Bindable var editorState: SDKCodeEditorState
    @State private var followOutput = true

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("\(editorState.consoleEntries.count) console entries")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Toggle("Follow output", isOn: $followOutput)
                    .font(.caption)
                    .help("When on, the console scrolls to the latest entry on every append.")
                Button("Clear") { editorState.clearConsole() }
                    .font(.caption)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(editorState.consoleEntries) { entry in
                            HStack(alignment: .top, spacing: 6) {
                                Text(streamBadge(entry.stream))
                                    .font(.caption2.monospaced())
                                    .padding(.horizontal, 4)
                                    .background(streamColor(entry.stream).opacity(0.15), in: RoundedRectangle(cornerRadius: 4))
                                Text(entry.text)
                                    .font(.caption.monospaced())

                            }
                            .id(entry.id)
                        }
                    }
                    .padding(.horizontal, 8)
                }
                .onChange(of: editorState.consoleEntries.count) { _, _ in
                    if followOutput, let last = editorState.consoleEntries.last {
                        withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                    }
                }
            }
        }
    }

    private func streamBadge(_ stream: SDKConsoleStream) -> String {
        switch stream {
        case .stdout: return "OUT"
        case .stderr: return "ERR"
        case .system: return "SYS"
        }
    }

    private func streamColor(_ stream: SDKConsoleStream) -> Color {
        switch stream {
        case .stdout: return .primary
        case .stderr: return .red
        case .system: return .blue
        }
    }
}

struct SDKCodeDiagnosticsView: View {
    @Bindable var editorState: SDKCodeEditorState

    var body: some View {
        List {
            if editorState.diagnostics.isEmpty {
                Text("No diagnostics. Run Validate to check the project.")
                    .foregroundStyle(.secondary)
            }
            ForEach(editorState.diagnostics) { diag in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: icon(for: diag.severity))
                        .foregroundStyle(color(for: diag.severity))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("[\(diag.code)] \(diag.message)")
                            .font(.callout)
                        if let suggestion = diag.suggestion {
                            Text(suggestion).font(.caption).foregroundStyle(.secondary)
                        }
                        if let fileURL = diag.fileURL {
                            Text("\(fileURL.lastPathComponent)\(diag.line.map { ":\($0)" } ?? "")")
                                .font(.caption.monospaced()).foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    if diag.fileURL != nil, diag.line != nil {
                        Button("Go to") {
                            if let fileURL = diag.fileURL {
                                editorState.navigateTo(fileURL: fileURL, line: diag.line ?? 1, column: diag.column)
                            }
                        }
                        .font(.caption)
                    }
                }
            }
        }
        .listStyle(.plain)
    }

    private func icon(for severity: SDKEditorDiagnostic.Severity) -> String {
        switch severity {
        case .error: return "xmark.octagon.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .info: return "info.circle.fill"
        }
    }

    private func color(for severity: SDKEditorDiagnostic.Severity) -> Color {
        switch severity {
        case .error: return .red
        case .warning: return .orange
        case .info: return .blue
        }
    }
}

struct SDKCodeSnippetLibraryView: View {
    @Bindable var editorState: SDKCodeEditorState
    @State private var allSnippets: [SDKSnippet] = SDKSnippetStore.loadAll()
    @State private var searchQuery = ""
    @State private var selectedCategory: SDKSnippetCategoryFilter = .all
    @State private var selectedVariant: SDKSnippetCodeVariant = .typescript
    @State private var expandedSnippetIDs: Set<String> = []
    @State private var copiedSnippetID: String?
    @State private var insertedSnippetID: String?

    private var visibleSnippets: [SDKSnippet] {
        SDKSnippetStore.filter(allSnippets, query: searchQuery, category: selectedCategory)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                TextField("Filter snippets by ID, title, or code…", text: $searchQuery)
                    .textFieldStyle(.roundedBorder)
                Picker("Category", selection: $selectedCategory) {
                    ForEach(SDKSnippetCategoryFilter.allCases, id: \.self) { category in
                        Text(category.rawValue).tag(category)
                    }
                }
                .pickerStyle(.menu)
                Picker("Variant", selection: $selectedVariant) {
                    ForEach(SDKSnippetCodeVariant.allCases, id: \.self) { variant in
                        Text(variant.rawValue).tag(variant)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 260)
            }
            .padding(6)
            List {
                if visibleSnippets.isEmpty {
                    Text("No matching snippets.").foregroundStyle(.secondary)
                }
                ForEach(visibleSnippets) { snippet in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(snippet.title).font(.headline)
                            Text(snippet.capabilityId).font(.caption.monospaced()).foregroundStyle(.secondary)
                            Spacer()
                            Button(expandedSnippetIDs.contains(snippet.id) ? "Hide" : "Show") {
                                if expandedSnippetIDs.contains(snippet.id) {
                                    expandedSnippetIDs.remove(snippet.id)
                                } else {
                                    expandedSnippetIDs.insert(snippet.id)
                                }
                            }
                            .font(.caption)
                            Button("Copy") {
                                ShellPasteboard.copy(snippet.executableCode(for: selectedVariant))
                                copiedSnippetID = snippet.id
                            }
                            .font(.caption)
                            Button("Insert") {
                                editorState.insertCodeSnippet(snippet.executableCode(for: selectedVariant))
                                insertedSnippetID = snippet.id
                            }
                            .font(.caption)
                            Button("Add to Manifest") {
                                _ = editorState.addCapabilityToManifest(
                                    capabilityId: snippet.capabilityId, reason: snippet.description)
                            }
                            .font(.caption)
                        }
                        Text(snippet.description).font(.caption).foregroundStyle(.secondary)
                        if expandedSnippetIDs.contains(snippet.id) {
                            Text(snippet.executableCode(for: selectedVariant))
                                .font(.caption.monospaced())

                                .padding(6)
                                .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 6))
                        }
                        if insertedSnippetID == snippet.id {
                            Text("Inserted into the editor.").font(.caption).foregroundStyle(.green)
                        }
                        if copiedSnippetID == snippet.id {
                            Text("Copied to the pasteboard.").font(.caption).foregroundStyle(.green)
                        }
                    }
                }
            }
            .listStyle(.plain)
        }
    }
}

struct SDKCodeBuildRunView: View {
    @Bindable var editorState: SDKCodeEditorState
    @State private var kind: SDKBuildRunKind = .typescriptExtension
    @State private var schemeOrEntry = ""
    @State private var runningTaskID: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if editorState.projectRootURL == nil {
                Text("Open a project to build or run.").foregroundStyle(.secondary)
            } else {
                Picker("Kind", selection: $kind) {
                    ForEach(SDKBuildRunKind.allCases, id: \.self) { kind in
                        Text(kind.displayName).tag(kind)
                    }
                }
                .pickerStyle(.segmented)
                Text(helpFor(kind)).font(.caption).foregroundStyle(.secondary)
                if kind != .typescriptExtension {
                    TextField(kind == .xcodebuildSwift ? "Scheme (blank = auto-detect)" : "Script path",
                              text: $schemeOrEntry)
                        .textFieldStyle(.roundedBorder)
                }
                if let runningTaskID {
                    Button("Stop") {
                        Task {
                            await SDKCodeBuildRunner.shared.cancel(taskID: runningTaskID)
                            self.runningTaskID = nil
                        }
                    }
                } else {
                    Button("Build / Run") {
                        guard let root = editorState.projectRootURL else { return }
                        let request = SDKBuildRunRequest(
                            projectRoot: root, kind: kind,
                            schemeOrEntry: schemeOrEntry.isEmpty ? nil : schemeOrEntry)
                        runningTaskID = request.taskID
                        Task {
                            await SDKCodeBuildRunner.shared.run(request, into: editorState)
                            runningTaskID = nil
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .padding()
    }

    private func helpFor(_ kind: SDKBuildRunKind) -> String {
        switch kind {
        case .xcodebuildSwift:
            return "Build the Xcode project with the managed build service."
        case .typescriptExtension:
            return "Run the project's build script (npm run build)."
        case .nodeScript:
            return "Run the script with node."
        }
    }
}
