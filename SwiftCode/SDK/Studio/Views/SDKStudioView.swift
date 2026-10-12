import SwiftUI

// MARK: - SDKStudioView
//
// SwiftCode Studio root view — the EXCLUSIVE creation hub for SwiftCode
// platform/SDK projects and extensions (spec §13.3 "Exclusive Project
// Creation Boundary").
//
// Per the spec, Studio is the ONLY UI surface where users may create
// projects targeting the SwiftCode platform and extensions using the
// SwiftCode SDK. The main code-editor UI is restricted to editing,
// navigating, and viewing existing files; creation templates, new-project
// wizards, and platform scaffolding MUST NOT appear in the main editor's
// file/menu interfaces. Selecting "New SwiftCode Project" or "New
// Extension" in the main editor is required to redirect here via
// `SDKStudioWindowManager.shared.openStudio(section: .projects)` (or
// `.extensions`).
//
// IMPORTANT APP-SURGERY NOTE: rerouting the main editor's menus to
// `SDKStudioWindowManager` is a separate task and is NOT part of this
// file. Tracked in `SwiftCode/SDK/Studio/agent_notes.md`.
//
// Shell only: the five detail panes are built in parallel and referenced
// here, never redefined:
//   - `SDKStudioProjectsView`   (project & extension generation wizards)
//   - `SDKStudioExtensionsView` (lifecycle console + manifest inspector)
//   - `SDKStudioAPIKeysView`    (developer API key management)
//   - `SDKStudioLogsView`       (dual logging inspector: user + developer)
//   - `SDKCodeEditorShellView`  (Studio code editor: navigator, tabs,
//                                console, find bar, snippet browser)
//
// Native macOS SwiftUI (`NavigationSplitView`), macOS 15, Swift 6.
//
// `SDKStudioView` is explicitly `@MainActor`: Swift 6 removed the old
// implicit `@MainActor` inference from `@StateObject`, so views that own
// `@MainActor`-isolated state (like `SDKCodeEditorShellView`) must be
// `@MainActor` themselves, and this view constructs them.

@MainActor
public struct SDKStudioView: View {
    @State private var selection: SDKStudioSection

    public init(initialSection: SDKStudioSection = .projects) {
        _selection = State(initialValue: initialSection)
    }

    public var body: some View {
        NavigationSplitView {
            List(SDKStudioSection.allCases, selection: $selection) { section in
                Label(section.rawValue, systemImage: section.systemImage)
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 220)
            .navigationTitle("Studio")
        } detail: {
            studioDetailView(for: selection)
        }
        .navigationTitle("SwiftCode Studio")
    }

    @ViewBuilder
    private func studioDetailView(for section: SDKStudioSection) -> some View {
        switch section {
        case .projects:
            SDKStudioProjectsView()
        case .extensions:
            SDKStudioExtensionsView()
        case .apiKeys:
            SDKStudioAPIKeysView()
        case .logs:
            SDKStudioLogsView()
        case .codeEditor:
            SDKCodeEditorShellView()
        }
    }
}
