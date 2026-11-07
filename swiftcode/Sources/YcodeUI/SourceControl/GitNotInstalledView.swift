import AppKit
import SwiftUI

@MainActor
public struct GitNotInstalledView: View {
    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Git is not installed", systemImage: "exclamationmark.triangle.fill")
                .font(.headline)
                .foregroundStyle(.orange)

            Text("Source control needs the git command-line tools. Install Git, then reopen the project.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Button {
                if let url = URL(string: "https://git-scm.com/downloads") {
                    NSWorkspace.shared.open(url)
                }
            } label: {
                Label("Install Git from git-scm.com", systemImage: "arrow.down.circle")
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}
