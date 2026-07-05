import SwiftUI

// MARK: - Swift Package Manager Extension View
struct SwiftPackageManagerExtensionView: View {
    @State private var isEnabled = true
    @State private var autoResolve = true
    @State private var showDependencyGraph = true
    @State private var updatePolicy = "minor"

    var body: some View {
        Form {
            Section {
                Toggle("Enable SPM Integration", isOn: $isEnabled)
                Toggle("Auto-Resolve on Open", isOn: $autoResolve)
                Toggle("Show Dependency Graph", isOn: $showDependencyGraph)
            } header: {
                Label("Swift Package Manager", systemImage: "shippingbox.fill")
            }
            Section {
                Picker("Auto-Update Policy", selection: $updatePolicy) {
                    Text("Patch only (x.y.Z)").tag("patch")
                    Text("Minor (x.Y.z)").tag("minor")
                    Text("Manual only").tag("manual")
                }
            } header: {
                Text("Updates")
            }
            Section {
                Text("Manage SPM dependencies graphically: add packages by URL, update to latest versions, and remove unused packages without editing Package.swift manually.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("About")
            }
        }
        .navigationTitle("Swift Package Manager")
        .navigationBarTitleDisplayMode(.inline)
    }
}
