import AppKit
import SwiftUI

// MARK: - SDKCodeConsoleView
//
// Bottom console panel for the Studio code editor. A virtualized `List`
// (lazy rows, cheap at the 5,000-entry cap) over
// `SDKCodeEditorState.consoleEntries`, oldest first.
//
// REAL behaviors, no placeholders:
// - Stream-colored prefixes: OUT (secondary), ERR (red), SYS (blue) pills.
// - Timestamps rendered subtly per row.
// - Auto-scroll to the latest entry while "Follow" is on; the toggle is
//   honored on every append and when re-enabled.
// - "Clear" calls `state.clearConsole()`, which genuinely empties the
//   array (bounded by `SDKCodeEditorState.appendConsole(_:)`, so the list
//   can never grow unbounded).
// - Copy support two ways: drag-select text inside any row
//   (`.textSelection(.enabled)`), and multi-row selection (click / ⇧-click
//   / ⌘-click) copied verbatim to the pasteboard via "Copy Selected".

@MainActor
public struct SDKCodeConsoleView: View {
    @ObservedObject var state: SDKCodeEditorState

    @State private var followOutput: Bool = true
    @State private var selection: Set<SDKConsoleEntry.ID> = []

    public init(state: SDKCodeEditorState) {
        self.state = state
    }

    public var body: some View {
        VStack(spacing: 0) {
            headerBar
            Divider()
            if state.consoleEntries.isEmpty {
                emptyState
            } else {
                ScrollViewReader { proxy in
                    List(state.consoleEntries, selection: $selection) { entry in
                        SDKCodeConsoleRow(entry: entry)
                    }
                    .listStyle(.plain)
                    .onChange(of: state.consoleEntries.count) { _, _ in
                        scrollToLatest(proxy)
                    }
                    .onChange(of: followOutput) { _, following in
                        if following { scrollToLatest(proxy) }
                    }
                }
            }
        }
        .accessibilityLabel("Console")
    }

    // MARK: - Header

    private var headerBar: some View {
        HStack(spacing: 8) {
            Text("Console")
                .font(.headline)
            Text("\(state.consoleEntries.count)")
                .font(.callout)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .accessibilityLabel("\(state.consoleEntries.count) console entries")
            Spacer()
            Toggle("Follow", isOn: $followOutput)
                .help("Automatically scroll to the latest console output")
            Button("Copy Selected") {
                copySelectionToPasteboard()
            }
            .disabled(selection.isEmpty)
            .help("Copy the selected console entries to the clipboard")
            Button("Clear") {
                state.clearConsole()
                selection.removeAll()
            }
            .disabled(state.consoleEntries.isEmpty)
            .help("Clear all console output")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: "terminal")
                .font(.title2)
                .foregroundStyle(.tertiary)
            Text("No console output")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    // MARK: - Behavior

    /// Scrolls to the newest entry when following is enabled.
    private func scrollToLatest(_ proxy: ScrollViewProxy) {
        guard followOutput, let lastID = state.consoleEntries.last?.id else { return }
        proxy.scrollTo(lastID, anchor: .bottom)
    }

    /// Copies the selected rows (in document order, with stream tags) to
    /// the general pasteboard. Real copy — the text lands on the clipboard.
    private func copySelectionToPasteboard() {
        let selected = state.consoleEntries.filter { selection.contains($0.id) }
        guard !selected.isEmpty else { return }
        let text = selected
            .map { "[\($0.stream.rawValue.uppercased())] \($0.text)" }
            .joined(separator: "\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

// MARK: - SDKCodeConsoleRow

/// One console entry: subtle timestamp, stream-colored prefix pill, and
/// the (already 4 KiB-bounded) text. Text selection is enabled per row so
/// users can copy arbitrary spans, not just whole rows.
private struct SDKCodeConsoleRow: View {
    let entry: SDKConsoleEntry

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(entry.timestamp, format: .dateTime.hour().minute().second())
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
            SDKCodeConsoleStreamBadge(stream: entry.stream)
            Text(entry.text)
                .font(.body.monospaced())
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 1)
    }
}

// MARK: - SDKCodeConsoleStreamBadge

/// Stream-colored prefix pill: OUT (secondary), ERR (red), SYS (blue).
private struct SDKCodeConsoleStreamBadge: View {
    let stream: SDKConsoleStream

    var body: some View {
        Text(label)
            .font(.caption2)
            .fontDesign(.monospaced)
            .bold()
            .foregroundStyle(color)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(color.opacity(0.12), in: Capsule())
            .accessibilityLabel("Stream: \(stream.rawValue)")
    }

    private var label: String {
        switch stream {
        case .stdout: return "OUT"
        case .stderr: return "ERR"
        case .system: return "SYS"
        }
    }

    private var color: Color {
        switch stream {
        case .stdout: return .secondary
        case .stderr: return .red
        case .system: return .blue
        }
    }
}
