import SwiftUI

@MainActor
public struct SDKCodeFindBarView: View {
    @ObservedObject var state: SDKCodeEditorState
    @ObservedObject var coordinator: SDKCodeFindCoordinator

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
        .onExitCommand(perform: onDismiss)
    }
}
