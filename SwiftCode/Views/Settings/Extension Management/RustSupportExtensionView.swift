import SwiftUI

// MARK: - Rust Support Extension View
struct RustSupportExtensionView: View {
    @State private var isEnabled = true
    @State private var edition = "2021"
    @State private var clippyEnabled = true
    @State private var showLifetimeHints = true
    @State private var showOwnershipHints = true

    private let editions = ["2015", "2018", "2021"]

    var body: some View {
        Form {
            Section {
                Toggle("Enable Rust Support", isOn: $isEnabled)
                Toggle("Clippy Linting", isOn: $clippyEnabled)
                Toggle("Ownership Hints", isOn: $showOwnershipHints)
                Toggle("Lifetime Hints", isOn: $showLifetimeHints)
            } header: {
                Label("Rust Support", systemImage: "gearshape.2.fill")
            }
            Section {
                Picker("Edition", selection: $edition) {
                    ForEach(editions, id: \.self) { e in
                        Text("Rust \(e)").tag(e)
                    }
                }
                .pickerStyle(.segmented)
            } header: {
                Text("Language Edition")
            }
            Section {
                Text("Rust syntax highlighting with ownership and lifetime annotations. Integrates Clippy for idiomatic code suggestions.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("About")
            }
        }
        .navigationTitle("Rust Support")
        .navigationBarTitleDisplayMode(.inline)
    }
}
