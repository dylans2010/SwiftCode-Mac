import SwiftUI

// MARK: - ExtensionsHomeView: the Extensions destination
//
// Opened from the code-editor toolbar (WorkspaceView), not from the
// sidebar anymore. NavigationSplitView over the section list, reusing
// the app's native macOS split-view pattern. Each section renders real
// manager state; the Xcode section additionally runs a real buffer
// command (sort lines) against an editable demo buffer, so the adapter
// is exercised in the UI, not just described in docs.
//
// Freeze guard: the manager's first load is async (ensureReady), so
// this view shows a spinner until it completes instead of blocking
// the main thread on disk work during its first frame.

public struct ExtensionsHomeView: View {
    @StateObject private var viewModel = ExtV2HomeViewModel()
    @ObservedObject private var manager = ExtV2Manager.shared
    @State private var demoBufferText = "banana\nApple\ncherry\napple"
    @State private var demoResult: String?

    public init() {}

    public var body: some View {
        Group {
            if !manager.isReady {
                ProgressView("Loading extensions…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                splitView
            }
        }
        .task {
            await manager.ensureReady()
        }
    }

    private var splitView: some View {
        NavigationSplitView {
            // Plain buttons, not a List selection binding: the sidebar
            // is a small fixed set, and this keeps selection state in
            // exactly one place (the view model).
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(ExtV2HomeSection.allCases) { section in
                        Button {
                            viewModel.section = section
                        } label: {
                            Label(section.title, systemImage: section.icon)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            viewModel.section == section
                                ? Color.accentColor.opacity(0.15)
                                : Color.clear,
                            in: RoundedRectangle(cornerRadius: 6))
                    }
                }
                .padding(8)
            }
            .navigationTitle("Extensions")
        } detail: {
            Group {
                switch viewModel.section {
                case .discover:
                    ExtensionsSearchView()
                case .installed:
                    ExtensionsInstalledView()
                case .updates:
                    ExtensionUpdatesView()
                case .enabled, .disabled:
                    installedList
                case .native:
                    nativeSection
                case .xcode:
                    xcodeSection
                case .permissions:
                    ExtensionPermissionsView()
                case .settings:
                    ExtensionSettingsView()
                case .diagnostics:
                    ExtensionDiagnosticsView()
                }
            }
            .navigationTitle(viewModel.section.title)
        }
    }

    private var installedList: some View {
        VStack(spacing: 0) {
            if viewModel.filteredInstalled.isEmpty {
                ContentUnavailableView(
                    "Nothing here",
                    systemImage: "puzzlepiece",
                    description: Text("No extensions match this section."))
            } else {
                List(viewModel.filteredInstalled) { installed in
                    ExtensionSidebarRow(metadata: installed.metadata, state: installed.state)
                }
                .listStyle(.plain)
            }
        }
    }

    private var nativeSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("SwiftCode-native plugins run from the documented SDK (see Docs/Extensions-v2.md). Third-party native code is never loaded in-process; untrusted extensions should ship through the out-of-process VS Code host.")
                .font(.callout)
                .foregroundStyle(.secondary)
            Button("Register sample native plugin") {
                manager.registerSamplePlugin()
            }
            .buttonStyle(.borderedProminent)
            if viewModel.filteredInstalled.isEmpty {
                ContentUnavailableView("No native extensions", systemImage: "swift", description: Text("Register the sample plugin above to see the SDK working."))
            } else {
                List(viewModel.filteredInstalled) { installed in
                    ExtensionSidebarRow(metadata: installed.metadata, state: installed.state)
                }
                .listStyle(.plain)
            }
            Spacer()
        }
        .padding()
    }

    private var xcodeSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Xcode compatibility means reusable source-editor command logic through the ExtV2XcodeCommandRegistry adapter. XcodeKit extension binaries themselves run under Xcode only — they are not executed here.")
                .font(.callout)
                .foregroundStyle(.secondary)
            GroupBox("Registered commands") {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(ExtV2XcodeCommandRegistry.shared.allIdentifiers, id: \.self) { id in
                        Text("• \(id)").font(.callout)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            GroupBox("Try it: sort lines in this buffer") {
                VStack(alignment: .leading, spacing: 8) {
                    TextEditor(text: $demoBufferText)
                        .font(.callout.monospaced())
                        .frame(height: 120)
                        .border(Color.secondary.opacity(0.3))
                    Button("Sort all lines") {
                        Task {
                            let buffer = ExtV2SourceTextBuffer(
                                text: demoBufferText,
                                selections: [ExtV2SourceRange(
                                    start: ExtV2SourcePosition(line: 0, column: 0),
                                    end: ExtV2SourcePosition(line: demoBufferText.components(separatedBy: "\n").count - 1, column: 0))])
                            do {
                                try await ExtV2XcodeCommandRegistry.shared.perform(
                                    identifier: "com.swiftcode.xcode.sortLines", buffer: buffer)
                                demoBufferText = buffer.completeBuffer
                                demoResult = "Sorted."
                            } catch {
                                demoResult = "Failed: \(error.localizedDescription)"
                            }
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    if let demoResult {
                        Text(demoResult).font(.callout).foregroundStyle(.secondary)
                    }
                }
            }
            Spacer()
        }
        .padding()
    }
}
