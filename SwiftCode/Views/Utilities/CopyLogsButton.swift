import SwiftUI
import AppKit

/// Reusable and robust utility button to copy log contents/text to the macOS clipboard, showing confirmation and disabling itself if empty.
public struct CopyLogsButton: View {
    private let logTextProvider: @MainActor () -> String
    @State private var showCopiedConfirmation = false

    public init(logs: @escaping @autoclosure @MainActor () -> String) {
        self.logTextProvider = logs
    }

    public init(provider: @escaping @MainActor () -> String) {
        self.logTextProvider = provider
    }

    @MainActor
    private var logText: String {
        logTextProvider()
    }

    @MainActor
    private var hasLogs: Bool {
        !logText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    public var body: some View {
        Button {
            copyToClipboard()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: showCopiedConfirmation ? "checkmark.circle.fill" : "doc.on.doc")
                    .foregroundColor(showCopiedConfirmation ? .green : .accentColor)
                Text(showCopiedConfirmation ? "Copied!" : "Copy Logs")
                    .fontWeight(.medium)
            }
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .disabled(!hasLogs)
        .help("Copy logs to system clipboard")
    }

    private func copyToClipboard() {
        let text = logText
        guard !text.isEmpty else { return }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        // Support very large log outputs without truncation or memory issues by assigning as NSPasteboard.PasteboardType.string
        pasteboard.setString(text, forType: .string)

        withAnimation(.spring()) {
            showCopiedConfirmation = true
        }

        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            await MainActor.run {
                withAnimation {
                    showCopiedConfirmation = false
                }
            }
        }
    }
}
