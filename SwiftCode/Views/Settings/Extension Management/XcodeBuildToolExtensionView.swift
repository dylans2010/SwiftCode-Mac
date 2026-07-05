import SwiftUI

// MARK: - Xcode Build Tool Extension View
struct XcodeBuildToolExtensionView: View {
    @State private var isEnabled = true
    @State private var scheme = ""
    @State private var configuration = "Debug"
    @State private var streamLogs = true
    @State private var showBuildTimings = false

    private let configurations = ["Debug", "Release", "Profile"]

    var body: some View {
        Form {
            Section {
                Toggle("Enable Xcode Build Tool", isOn: $isEnabled)
                Toggle("Stream Build Logs", isOn: $streamLogs)
                Toggle("Show Build Timings", isOn: $showBuildTimings)
            } header: {
                Label("Xcode Build Tool", systemImage: "hammer.fill")
            }
            Section {
                HStack {
                    Text("Scheme")
                    Spacer()
                    TextField("MyApp", text: $scheme)
                        .multilineTextAlignment(.trailing)
                        .foregroundStyle(.secondary)
                }
                Picker("Configuration", selection: $configuration) {
                    ForEach(configurations, id: \.self) { c in
                        Text(c).tag(c)
                    }
                }
            } header: {
                Text("Build Settings")
            }
            Section {
                Text("Triggers xcodebuild commands and streams build logs to the integrated console panel. Supports build, test, archive, and clean actions.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("About")
            }
        }
        .navigationTitle("Xcode Build Tool")
        .navigationBarTitleDisplayMode(.inline)
    }
}
