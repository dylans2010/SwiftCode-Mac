import AppKit
import Foundation
import SwiftUI

// MARK: - SDKCodeProjectRootView
//
// Header row for the Studio code editor's file navigator. Shows the
// currently open project root (folder name + full path) with a
// "Change…" button, or a centered "Open Project…" button when nothing
// is open yet. Folder selection uses a real `NSOpenPanel` restricted to
// directories only — the caller receives the chosen `URL` and owns the
// tree; this view performs no file I/O itself.

@MainActor
public struct SDKCodeProjectRootView: View {
    /// The open project folder, or `nil` when nothing is open.
    public let rootURL: URL?

    /// Called with the folder chosen in the open panel.
    public let onSelectRoot: (URL) -> Void

    public init(rootURL: URL?, onSelectRoot: @escaping (URL) -> Void) {
        self.rootURL = rootURL
        self.onSelectRoot = onSelectRoot
    }

    public var body: some View {
        Group {
            if let rootURL {
                HStack(spacing: 8) {
                    Image(systemName: "folder.fill")
                        .foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(rootURL.lastPathComponent)
                            .font(.headline)
                            .lineLimit(1)
                        Text(rootURL.path)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    Spacer(minLength: 4)
                    Button("Change…", action: presentOpenPanel)
                }
            } else {
                HStack {
                    Spacer()
                    Button("Open Project…", action: presentOpenPanel)
                    Spacer()
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    /// Presents a real `NSOpenPanel` for picking a project folder.
    /// Directories only; creating a new folder from the panel is allowed.
    private func presentOpenPanel() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.prompt = "Open"
        panel.message = "Choose a project folder to browse in the file navigator."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        onSelectRoot(url)
    }
}
