import SwiftUI

/// Renders a responsive list or grid of installed platform SDK Runtimes.
public struct SimulatorRuntimeView: View {
    @Environment(SimulatorManager.self) private var simulatorManager

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    Label("Discovered Platform Runtimes", systemImage: "cpu.fill")
                        .font(.title2.bold())
                    Spacer()
                    Button(action: {
                        Task {
                            await simulatorManager.refresh()
                        }
                    }) {
                        Label("Scan System", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.bordered)
                }

                if simulatorManager.runtimes.isEmpty {
                    ContentUnavailableView {
                        Label("No Runtimes Detected", systemImage: "cpu")
                    } description: {
                        Text("Please install Xcode runtimes using 'xcodebuild -downloadAllPlatforms'.")
                    }
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 280, maximum: 400), spacing: 16)], spacing: 16) {
                        ForEach(simulatorManager.runtimes) { runtime in
                            VStack(alignment: .leading, spacing: 12) {
                                HStack {
                                    Image(systemName: "cpu")
                                        .font(.title)
                                        .foregroundStyle(.orange)
                                    Spacer()
                                    Text(runtime.platform)
                                        .font(.caption2.bold())
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.orange.opacity(0.15))
                                        .foregroundStyle(.orange)
                                        .clipShape(RoundedRectangle(cornerRadius: 4))
                                }

                                VStack(alignment: .leading, spacing: 4) {
                                    Text(runtime.name)
                                        .font(.headline)
                                    Text("Build: \(runtime.buildversion)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }

                                Divider()

                                HStack {
                                    Circle()
                                        .fill(runtime.isAvailable ? .green : .red)
                                        .frame(width: 6, height: 6)
                                    Text(runtime.isAvailable ? "Ready" : "Unavailable")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                    Text(runtime.identifier.components(separatedBy: ".").last ?? "")
                                        .font(.system(.caption2, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding()
                            .background(Color(NSColor.controlBackgroundColor))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .overlay {
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(Color.gray.opacity(0.1), lineWidth: 1)
                            }
                        }
                    }
                }
            }
            .padding(24)
        }
        .background(Color(NSColor.windowBackgroundColor))
    }
}
