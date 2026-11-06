import SwiftUI

// MARK: - SDKCodeFindBarView
//
// The Studio code editor's find bar: a compact native macOS strip with a
// query field, match-case toggle, live match count, and next/previous
// navigation that REALLY moves the selection in the active editor.
//
// COORDINATION: the bar does not search itself. Its text field is bound to
// `SDKCodeEditorState.findQuery` (the published source of truth), changes
// are forwarded to the shared `SDKCodeFindCoordinator` via `setQuery(_)`,
// and the coordinator drives the registered editor through
// `SDKCodeFindableEditor.selectFindRange(_:)`. The case-sensitivity toggle
// binds directly to `coordinator.caseSensitive`, so it genuinely changes
// matching (the coordinator recomputes on toggle).
//
// The parent owns the bar's visibility and passes an `onDismiss` closure
// (typically `{ showingFindBar = false }`, which is idempotent); Escape
// dismisses the bar.

@MainActor
public struct SDKCodeFindBarView: View {
    @ObservedObject var state: SDKCodeEditorState
    @ObservedObject var coordinator: SDKCodeFindCoordinator

    /// Called to dismiss the bar. Invoked idempotently.
    public var onDismiss: () -> Void

    @FocusState private var queryFieldFocused: Bool

    public init(
        state: SDKCodeEditorState,
        coordinator: SDKCodeFindCoordinator,
        onDismiss: @escaping () -> Void
    ) {
        self.state = state
        self.coordinator = coordinator
        self.onDismiss = onDismiss
    }

    public var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            TextField("Find in file", text: $state.findQuery)
                .textFieldStyle(.roundedBorder)
                .focused($queryFieldFocused)
                .frame(minWidth: 160, maxWidth: 280)
                .accessibilityLabel("Find")

            Toggle("Match case", isOn: $coordinator.caseSensitive)
                .help("Match case when finding")

            Text(coordinator.matchSummaryText)
                .font(.callout)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(minWidth: 72, alignment: .trailing)
                .accessibilityLabel("Match count")

            Button {
                coordinator.findPrevious()
            } label: {
                Image(systemName: "chevron.up")
            }
            .keyboardShortcut("g", modifiers: [.command, .shift])
            .disabled(!coordinator.hasMatches)
            .help("Previous match (⇧⌘G)")

            Button {
                coordinator.findNext()
            } label: {
                Image(systemName: "chevron.down")
            }
            .keyboardShortcut("g", modifiers: .command)
            .disabled(!coordinator.hasMatches)
            .help("Next match (⌘G)")

            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Close find bar (Esc)")
            .accessibilityLabel("Close find bar")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .liquidGlass(style: .subtle, cornerRadius: 8)
        .padding(6)
        .onAppear {
            coordinator.setQuery(state.findQuery)
            queryFieldFocused = true
        }
        .onChange(of: state.findQuery) { _, newValue in
            coordinator.setQuery(newValue)
        }
        // Escape dismisses, even while the query field has focus.
        .onExitCommand(perform: onDismiss)
    }
}
