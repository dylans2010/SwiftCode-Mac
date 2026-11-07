import AppKit
import Foundation
import SwiftUI

@MainActor
public struct SDKCodeProjectRootView: View {
    public let rootURL: URL?

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
        .liquidGlass(style: .subtle, cornerRadius: 8)
        .padding(6)
    }

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
