import SwiftUI

// MARK: - Git Blame Extension View
struct GitBlameExtensionView: View {
    @State private var showInlineBlame = true
    @State private var blameFormat = "relative"
    @State private var showAuthorAvatar = false

    private let blameFormats = ["relative", "absolute", "short-hash"]

    var body: some View {
        Form {
            Section {
                Toggle("Show Inline Blame", isOn: $showInlineBlame)
                Toggle("Show Author Avatar", isOn: $showAuthorAvatar)
            } header: {
                Label("Git Blame", systemImage: "person.crop.rectangle.stack")
            }
            Section {
                Picker("Date Format", selection: $blameFormat) {
                    Text("Relative (2 days ago)").tag("relative")
                    Text("Absolute (2024-01-15)").tag("absolute")
                    Text("Short Hash (a3f9b2c)").tag("short-hash")
                }
            } header: {
                Text("Display")
            }
            Section {
                Text("Shows inline git blame annotations for each line of code, including the author name, commit hash, and commit date.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("About")
            }
        }
        .navigationTitle("Git Blame")
        .navigationBarTitleDisplayMode(.inline)
    }
}
