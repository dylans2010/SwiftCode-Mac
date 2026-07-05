import SwiftUI

// MARK: - Go Support Extension View
struct GoSupportExtensionView: View {
    @State private var isEnabled = true
    @State private var gofmtOnSave = true
    @State private var goVersion = "1.22"
    @State private var enableModules = true

    private let goVersions = ["1.20", "1.21", "1.22", "1.23"]

    var body: some View {
        Form {
            Section {
                Toggle("Enable Go Support", isOn: $isEnabled)
                Toggle("gofmt on Save", isOn: $gofmtOnSave)
                Toggle("Go Modules (go.mod)", isOn: $enableModules)
            } header: {
                Label("Go Support", systemImage: "arrow.trianglehead.2.counterclockwise.rotate.90")
            }
            Section {
                Picker("Go Version", selection: $goVersion) {
                    ForEach(goVersions, id: \.self) { v in
                        Text("Go \(v)").tag(v)
                    }
                }
            } header: {
                Text("Toolchain")
            }
            Section {
                Text("Go syntax highlighting and gofmt integration. Automatically formats Go files on save and provides go.mod-aware import resolution.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("About")
            }
        }
        .navigationTitle("Go Support")
        .navigationBarTitleDisplayMode(.inline)
    }
}
