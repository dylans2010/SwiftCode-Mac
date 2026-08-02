import SwiftUI

public struct DeviceConnectEnvironmentView: View {
    @State private var environmentManager = EnvironmentManager.shared

    public init() {}

    public var body: some View {
        VStack(spacing: 24) {
            // Checklist GroupBox
            GroupBox {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Label("Toolchain Verification Checklist", systemImage: "checkmark.seal")
                            .font(.headline)
                            .foregroundColor(.orange)
                        Spacer()
                        if environmentManager.isValidating {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Button("Re-Validate") {
                                Task {
                                    await environmentManager.validateEnvironment()
                                }
                            }
                            .buttonStyle(.bordered)
                        }
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        ChecklistRow(title: "Xcode Installed & Registered", isMet: environmentManager.currentEnvironment.xcodeVersion != nil)
                        ChecklistRow(title: "Developer Directory Configuration", isMet: environmentManager.currentEnvironment.xcodePath != nil)
                        ChecklistRow(title: "iOS Development SDK Availability", isMet: environmentManager.currentEnvironment.hasiOSSDK)
                        ChecklistRow(title: "iOS Simulator SDK Support", isMet: environmentManager.currentEnvironment.hasSimulatorSDK)
                        ChecklistRow(title: "Code Signing Infrastructure verified", isMet: environmentManager.currentEnvironment.isSigningSetup)
                    }
                }
                .padding()
            }
            .groupBoxStyle(ModernGroupBoxStyle())

            // Detailed environment parameters
            GroupBox {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Label("Configuration Parameters", systemImage: "gearshape.2")
                            .font(.headline)
                            .foregroundColor(.blue)
                        Spacer()
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        InspectorRow(label: "macOS Version", value: environmentManager.currentEnvironment.macOSVersion)
                        InspectorRow(label: "Xcode Path", value: environmentManager.currentEnvironment.xcodePath ?? "Not Detected")
                        InspectorRow(label: "Xcode Version", value: environmentManager.currentEnvironment.xcodeVersion ?? "Not Detected")
                        InspectorRow(label: "Swift Compiler Version", value: environmentManager.currentEnvironment.swiftVersion ?? "Not Detected")
                        InspectorRow(label: "DerivedData Size", value: OutputFormatter.formatBytes(environmentManager.derivedDataSize))
                    }
                }
                .padding()
            }
            .groupBoxStyle(ModernGroupBoxStyle())

            // Diagnostics output
            GroupBox {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Label("System Diagnostics Log", systemImage: "doc.text.magnifyingglass")
                            .font(.headline)
                            .foregroundColor(.gray)
                        Spacer()
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        if environmentManager.diagnostics.isEmpty {
                            Text("No diagnostic entries recorded.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(environmentManager.diagnostics, id: \.self) { diagnostic in
                                HStack(alignment: .top, spacing: 8) {
                                    Image(systemName: "info.circle.fill")
                                        .foregroundStyle(.blue)
                                    Text(diagnostic)
                                        .font(.subheadline)
                                }
                            }
                        }
                    }
                }
                .padding()
            }
            .groupBoxStyle(ModernGroupBoxStyle())
        }
        .onAppear {
            if environmentManager.currentEnvironment.xcodeVersion == nil {
                Task {
                    await environmentManager.validateEnvironment()
                }
            }
        }
    }
}

struct ChecklistRow: View {
    let title: String
    let isMet: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: isMet ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .font(.title3)
                .foregroundStyle(isMet ? .green : .orange)
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(isMet ? .primary : .secondary)
            Spacer()
        }
    }
}
