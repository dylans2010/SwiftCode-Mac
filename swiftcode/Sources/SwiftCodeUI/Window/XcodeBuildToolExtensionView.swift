// XcodeBuildToolExtensionView.swift
//
// Ported from Legacy `SwiftCode/Views/Settings/Extension Management/XcodeBuildToolExtensionView.swift` (SwiftCode-Mac migration, Views/UI worklist).
// Worklist verdict: PARTIAL.
// Missing behaviour ported: tool settings panel (stream build logs, show build timings, scheme/configuration pickers as extension settings)
// Static port only — no Swift toolchain here; build verification pending on Dylan's Mac.
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
                    .padding(10)
                    .liquidGlass(style: .subtle, cornerRadius: 8)
            } header: {
                Text("About")
            }
        }
        .navigationTitle("Xcode Build Tool")
    }
}
