import SwiftUI
import AppKit

@MainActor
struct RuntimeDiscoveryView: View {
    @Binding var selectedRuntimeIdentifier: String

    @State private var runtimes: [SimulatorRuntime] = []
    @State private var isScanning = false
    @State private var errorMessage: String? = nil
    @State private var scanPath: String? = nil

    private let runtimeManager = RuntimeManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Runtime Discovery", systemImage: "sparkles.search")
                    .font(.headline)
                    .foregroundColor(.cyan)

                Spacer()

                if !runtimes.isEmpty {
                    Button(action: {
                        Task { await performRefresh() }
                    }) {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(isScanning)
                    .accessibilityLabel("Refresh discovered runtimes")
                }
            }

            Text("Auto-detect standard macOS locations or browse to a custom simulator runtime directory.")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                Button(action: {
                    Task { await performAutoDetect() }
                }) {
                    Label("Auto-Detect", systemImage: "sparkles")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.cyan)
                .disabled(isScanning)

                Button(action: {
                    openCustomDirectoryPicker()
                }) {
                    Label("Browse...", systemImage: "folder")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(isScanning)
            }

            if isScanning {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Scanning file system...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 8)
            } else if let error = errorMessage {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                        Text("No Runtimes Discovered")
                            .font(.caption.bold())
                    }
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.orange.opacity(0.1))
                .cornerRadius(8)
            } else if !runtimes.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Select Runtime:")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)

                    VStack(spacing: 6) {
                        ForEach(runtimes) { runtime in
                            Button(action: {
                                selectedRuntimeIdentifier = runtime.identifier
                            }) {
                                HStack(spacing: 10) {
                                    Image(systemName: selectedRuntimeIdentifier == runtime.identifier ? "largecircle.fill.circle" : "circle")
                                        .foregroundColor(selectedRuntimeIdentifier == runtime.identifier ? .cyan : .secondary)
                                        .font(.system(size: 14))

                                    VStack(alignment: .leading, spacing: 2) {
                                        HStack {
                                            Text(runtime.name)
                                                .font(.body.bold())
                                                .foregroundColor(.primary)
                                            Spacer()
                                            Text(runtime.platform)
                                                .font(.caption2.bold())
                                                .padding(.horizontal, 6)
                                                .padding(.vertical, 2)
                                                .background(platformBackgroundColor(for: runtime.platform))
                                                .cornerRadius(4)
                                                .foregroundColor(.white)
                                        }

                                        Text("Version: \(runtime.version) | \(runtime.identifier)")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)

                                        if let path = runtime.path {
                                            Text(path)
                                                .font(.system(.ultraLight, size: 9))
                                                .lineLimit(1)
                                                .truncationMode(.middle)
                                                .foregroundStyle(.tertiary)
                                        }
                                    }
                                    .multilineTextAlignment(.leading)
                                }
                                .padding(10)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(selectedRuntimeIdentifier == runtime.identifier ? Color.cyan.opacity(0.12) : Color(NSColor.controlBackgroundColor))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(selectedRuntimeIdentifier == runtime.identifier ? Color.cyan : Color.clear, lineWidth: 1)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Image(systemName: "info.circle")
                            .foregroundColor(.secondary)
                        Text("Ready to scan")
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.secondary.opacity(0.1))
                .cornerRadius(8)
            }
        }
    }

    private func performAutoDetect() async {
        isScanning = true
        errorMessage = nil
        scanPath = nil

        let results = await runtimeManager.discoverRuntimes()
        runtimes = results
        isScanning = false

        if runtimes.isEmpty {
            errorMessage = "No valid .simruntime bundles found in standard locations:\n• /Library/Developer/CoreSimulator/Profiles/Runtimes/\n• ~/Library/Developer/CoreSimulator/Profiles/Runtimes/"
        } else {
            // Automatically select the first discovered if none is currently selected
            if selectedRuntimeIdentifier.isEmpty, let first = runtimes.first {
                selectedRuntimeIdentifier = first.identifier
            }
        }
    }

    private func performRefresh() async {
        runtimeManager.clearCache()
        if let path = scanPath {
            isScanning = true
            errorMessage = nil
            let results = await runtimeManager.getRuntimesFromCustomPath(path)
            runtimes = results
            isScanning = false
            if runtimes.isEmpty {
                errorMessage = "No valid .simruntime bundles found in the selected custom directory."
            }
        } else {
            await performAutoDetect()
        }
    }

    private func openCustomDirectoryPicker() {
        let openPanel = NSOpenPanel()
        openPanel.title = "Select Custom Runtime Directory"
        openPanel.showsResizeIndicator = true
        openPanel.showsHiddenFiles = false
        openPanel.canChooseFiles = false
        openPanel.canChooseDirectories = true
        openPanel.allowsMultipleSelection = false

        openPanel.begin { response in
            if response == .OK, let url = openPanel.url {
                scanPath = url.path
                Task {
                    await scanCustomDirectory(at: url.path)
                }
            }
        }
    }

    private func scanCustomDirectory(at path: String) async {
        isScanning = true
        errorMessage = nil

        let results = await runtimeManager.getRuntimesFromCustomPath(path)
        runtimes = results
        isScanning = false

        if runtimes.isEmpty {
            errorMessage = "No valid .simruntime bundles found in custom path: \(path)"
        } else {
            if selectedRuntimeIdentifier.isEmpty, let first = runtimes.first {
                selectedRuntimeIdentifier = first.identifier
            }
        }
    }

    private func platformBackgroundColor(for platform: String) -> Color {
        switch platform.lowercased() {
        case "ios": return .blue
        case "watchos": return .orange
        case "tvos": return .purple
        case "visionos": return .teal
        case "macos": return .green
        default: return .gray
        }
    }
}
