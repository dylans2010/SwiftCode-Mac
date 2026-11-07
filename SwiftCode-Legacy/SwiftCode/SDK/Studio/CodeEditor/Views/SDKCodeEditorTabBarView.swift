import AppKit
import SwiftUI

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
        .liquidGlass(style: .subtle, cornerRadius: 6)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(isActive ? Color.accentColor.opacity(0.4) : Color.clear, lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            state.activateTab(tab.id)
        }
        .help(tab.document.fileURL?.path ?? "Untitled document")
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }
}
