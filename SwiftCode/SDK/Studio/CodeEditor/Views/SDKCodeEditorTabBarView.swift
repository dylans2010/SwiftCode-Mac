import AppKit // Color(nsColor:) for the active tab's control-background fill
import SwiftUI

// MARK: - SDKCodeEditorTabBarView
//
// The Studio code editor's tab strip: shows open tabs, a dirty dot per
// unsaved document, a close button per tab, and click-to-activate — all
// wired to `SDKCodeEditorState` (`activateTab`, `closeTab`).
//
// WHY NOT `TabView` + `.tabViewStyle(.tabBar)`: on macOS that style renders
// a segmented-control-style picker, not document tabs — it offers no
// per-tab close buttons, no dirty indicators, and no horizontal scrolling
// for many tabs. A minimal custom strip (Xcode/VS Code style, native
// materials and controls) is the behaviorally native choice.
//
// REAL behaviors, no placeholders:
// - Tabs come from `state.tabs` (tab-bar order); the active tab is
//   `state.activeTabID`. Tapping a tab calls `state.activateTab(_:)`.
// - The orange dot reflects `document.isDirty` for real; the × calls
//   `state.closeTab(_:)`, which genuinely removes the tab and re-homes
//   activation per `SDKCodeEditorState` semantics.
// - The tooltip shows the full file path (or "Untitled").

@MainActor
public struct SDKCodeEditorTabBarView: View {
    @ObservedObject var state: SDKCodeEditorState

    public init(state: SDKCodeEditorState) {
        self.state = state
    }

    public var body: some View {
        Group {
            if state.tabs.isEmpty {
                EmptyView()
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 2) {
                        ForEach(state.tabs) { tab in
                            tabButton(tab)
                        }
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 5)
                }
                .background(.bar)
                .overlay(alignment: .bottom) {
                    Divider()
                }
            }
        }
        .accessibilityLabel("Open files")
    }

    // MARK: - Tab

    private func tabButton(_ tab: SDKCodeEditorTab) -> some View {
        let isActive = tab.id == state.activeTabID
        return HStack(spacing: 6) {
            if tab.document.isDirty {
                Circle()
                    .fill(Color.orange)
                    .frame(width: 7, height: 7)
                    .accessibilityLabel("Unsaved changes")
                    .help("Unsaved changes")
            }
            Text(tab.document.displayName)
                .font(.system(size: 12, weight: isActive ? .semibold : .regular))
                .foregroundStyle(isActive ? .primary : .secondary)
                .lineLimit(1)
                .truncationMode(.middle)
            Button {
                state.closeTab(tab.id)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(isActive ? .secondary : .tertiary)
                    .padding(4)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .help("Close \(tab.document.displayName)")
            .accessibilityLabel("Close \(tab.document.displayName)")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isActive ? Color(nsColor: .controlBackgroundColor) : Color.clear)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            state.activateTab(tab.id)
        }
        .help(tab.document.fileURL?.path ?? "Untitled document")
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }
}
