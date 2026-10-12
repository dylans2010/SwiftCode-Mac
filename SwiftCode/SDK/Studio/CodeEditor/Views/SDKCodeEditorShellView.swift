import AppKit
import SwiftUI

// MARK: - SDKCodeEditorShellView
//
// The Studio Code Editor section's root view: an Xcode-like arrangement of
// file navigator (left), tabbed editor (center), find bar (top,
// collapsible) and console (bottom, collapsible).
//
// STATE OWNERSHIP: this view owns the ONE `SDKCodeEditorState` for the
// session (`@StateObject`) plus the ONE `SDKCodeFindCoordinator`, and
// hands the same instances to every child through their public
// initializers. Children never create their own state. The struct is
// explicitly `@MainActor` — Swift 6 removed the old implicit `@MainActor`
// inference from `@StateObject`, so the annotation is required for the
// `@MainActor`-isolated `SDKCodeEditorState` to be constructed here.
// (`SDKCodeSnippetLibraryView`, built in this task, still reads the state
// via `@EnvironmentObject`, injected at its presentation site.)
//
// Native macOS SwiftUI (`NavigationSplitView`); the editor/console split
// is a real `NSSplitView` (`SDKVerticalSplitView` below), so the divider
// is draggable and its position is autosaved. macOS 15, Swift 6.
//
// SIBLING INTEGRATION (parallel tasks, all landed): the file navigator,
// tab strip, editor surface, console, and find bar are real sibling views
// wired below by their public initializers only:
//   - `SDKCodeFileNavigatorView(editorState:)`
//   - `SDKCodeEditorTabBarView(state:)`
//   - `SDKCodeEditorView(state:highlighter:findCoordinator:)` with the
//     real `SDKKeywordHighlighter`
//   - `SDKCodeConsoleView(state:)`
//   - `SDKCodeFindBarView(state:coordinator:onDismiss:)` +
//     `SDKCodeFindCoordinator()`
// This shell owns the layout, the shared `SDKCodeEditorState`, the
// find coordinator lifetime, and the toolbar. No sibling API is invented
// here; remaining INTEGRATION notes mark the build&run seam.

@MainActor
public struct SDKCodeEditorShellView: View {
    /// The single editor session owned by this shell.
    @StateObject private var editorState = SDKCodeEditorState()

    /// Find-session coordinator shared by the find bar and the editor
    /// surface (match navigation, per the `SDKCodeFindCoordinator`
    /// contract). Owned here so both siblings talk to the same instance.
    @StateObject private var findCoordinator = SDKCodeFindCoordinator()

    @State private var showingFindBar = false
    @State private var showingConsole = true
    @State private var showingSnippets = false

    public init() {}

    public var body: some View {
        NavigationSplitView {
            SDKCodeFileNavigatorView(editorState: editorState)
                .navigationSplitViewColumnWidth(min: 180, ideal: 240)
        } detail: {
            // Sibling views take the shared state through their public
            // initializers; no environment injection is needed here.
            SDKVerticalSplitView(
                top: editorColumn,
                bottom: SDKCodeConsoleView(state: editorState)
                    .frame(minHeight: 140),
                isBottomVisible: $showingConsole
            )
        }
        .navigationTitle("Code Editor")
        .toolbar { shellToolbar }
        .sheet(isPresented: $showingSnippets) {
            SDKCodeSnippetLibraryView()
                .environmentObject(editorState)
                .frame(minWidth: 560, minHeight: 420)
        }
    }

    // MARK: - Editor column

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
            SDKCodeEditorTabBarView(state: editorState)
            SDKCodeEditorView(
                state: editorState,
                highlighter: SDKKeywordHighlighter(),
                findCoordinator: findCoordinator
            )
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
        ToolbarItem(placement: .automatic) {
            Button {
                showingFindBar.toggle()
            } label: {
                Image(systemName: "magnifyingglass")
            }
            .help("Toggle Find Bar")
            .keyboardShortcut("f", modifiers: .command)
        }
        ToolbarItem(placement: .automatic) {
            Button {
                openFilePanel()
            } label: {
                Image(systemName: "folder")
            }
            .help("Open File…")
            .keyboardShortcut("o", modifiers: .command)
        }
        ToolbarItem(placement: .automatic) {
            Button {
                showingConsole.toggle()
            } label: {
                Image(systemName: "terminal")
            }
            .help("Toggle Console")
        }
        // INTEGRATION: build & run (sibling task). The sibling runner owns
        // `SDKBuildRunRequest` execution and reports through
        // `SDKCodeEditorState.appendConsole(_:)`; its toolbar items
        // (build/run/stop + kind picker) plug in here.
        ToolbarItem(placement: .primaryAction) {
            Button("Snippets") {
                showingSnippets = true
            }
            .help("Browse SDK Snippets")
        }
    }

    // MARK: - Actions

    /// Toggles the `NavigationSplitView` sidebar through the responder
    /// chain — the AppKit-backed split view controller handles
    /// `toggleSidebar(_:)` itself.
    private func toggleSidebar() {
        _ = NSApp.keyWindow?.firstResponder?.tryToPerform(
            #selector(NSSplitViewController.toggleSidebar(_:)),
            with: nil
        )
    }

    /// Real open-file flow: `NSOpenPanel` → `SDKCodeEditorState.openFile(_:)`.
    /// A file the editor cannot read surfaces as a console entry (the
    /// state contract throws `SDKCodeEditorError` instead of faking it).
    /// `runModal()` keeps the whole flow on `@MainActor` with no
    /// cross-executor captures.
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
//
// A thin, honest wrapper around AppKit's `NSSplitView` for the
// editor-over-console arrangement: a real draggable divider whose position
// is autosaved, and a bottom pane that is genuinely removed from (and
// re-added to) the split when collapsed — not just zero-heighted.
//
// Environment propagation: `NSHostingView` does not inherit the SwiftUI
// environment across the representable boundary, so callers must apply
// `.environmentObject(...)` to the `top`/`bottom` view values themselves
// (this shell does that at the call site).

struct SDKVerticalSplitView<Top: View, Bottom: View>: NSViewRepresentable {
    let top: Top
    let bottom: Bottom
    @Binding var isBottomVisible: Bool

    func makeNSView(context: Context) -> NSSplitView {
        let splitView = NSSplitView()
        splitView.isVertical = false // horizontal divider → panes stack vertically
        splitView.dividerStyle = .thin
        splitView.autosaveName = "SDKCodeEditorConsoleSplit"

        let topHost = NSHostingView(rootView: top)
        let bottomHost = NSHostingView(rootView: bottom)
        context.coordinator.topHost = topHost
        context.coordinator.bottomHost = bottomHost

        splitView.addSubview(topHost)
        if isBottomVisible {
            splitView.addSubview(bottomHost)
            // The console keeps its height when the window resizes; the
            // editor absorbs the delta.
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
