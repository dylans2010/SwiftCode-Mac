import SwiftUI

struct UpdatesView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var isChecking = false
    @State private var checkResult: GitHubReleaseCheckResult?
    @State private var errorMessage: String?
    @State private var showingErrorAlert = false
    @State private var diagnosticLogs = ""

    private var currentBuild: Int {
        Int(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0") ?? 0
    }

    private var appVersionString: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Header Panel
                HStack(spacing: 16) {
                    ZStack {
                        Circle()
                            .fill(Color.blue.opacity(0.15))
                            .frame(width: 56, height: 56)
                        Image(systemName: "arrow.triangle.2.circlepath.circle.fill")
                            .font(.system(size: 32))
                            .foregroundColor(.blue)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Software Updates")
                            .font(.title2.bold())
                        Text("Keep your IDE secure and optimized with the latest builds.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(.horizontal, 4)

                // 1. Current Version Card
                GroupBox {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            Label("Current Version Details", systemImage: "info.circle.fill")
                                .font(.headline)
                                .foregroundColor(.blue)
                            Spacer()
                            Text("Local System")
                                .font(.caption.bold())
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2)
                                .background(Color.blue.opacity(0.12), in: Capsule())
                                .foregroundStyle(.blue)
                        }

                        VStack(spacing: 12) {
                            HStack {
                                Text("Application Name")
                                    .fontWeight(.medium)
                                Spacer()
                                Text("SwiftCode")
                                    .foregroundStyle(.secondary)
                            }
                            Divider()
                            HStack {
                                Text("Version")
                                    .fontWeight(.medium)
                                Spacer()
                                Text(appVersionString)
                                    .foregroundStyle(.secondary)
                            }
                            Divider()
                            HStack {
                                Text("Build Number")
                                    .fontWeight(.medium)
                                Spacer()
                                Text("\(currentBuild)")
                                    .font(.system(.body, design: .monospaced))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .padding()
                }
                .groupBoxStyle(ModernGroupBoxStyle())

                // 2. Update Status Card
                GroupBox {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            Label("Update Check Status", systemImage: "sparkles.rectangle.stack.fill")
                                .font(.headline)
                                .foregroundColor(.green)
                            Spacer()
                        }

                        if isChecking {
                            VStack(spacing: 14) {
                                ProgressView()
                                    .progressViewStyle(.circular)
                                Text("Querying server for build-* release artifacts...")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 20)
                        } else if let result = checkResult {
                            let hasUpdate = result.isUpdateAvailable(currentBuild: currentBuild)

                            VStack(spacing: 14) {
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(hasUpdate ? "New Update Available!" : "You're Fully Up To Date")
                                            .font(.headline)
                                            .foregroundColor(hasUpdate ? .orange : .green)
                                        Text(hasUpdate ? "A newer build is ready to be installed." : "SwiftCode is running the latest build version.")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Image(systemName: hasUpdate ? "arrow.down.circle.fill" : "checkmark.seal.fill")
                                        .font(.title)
                                        .foregroundColor(hasUpdate ? .orange : .green)
                                }
                                .padding(.bottom, 6)

                                Divider()

                                HStack {
                                    Text("Latest Tag Name")
                                        .fontWeight(.medium)
                                    Spacer()
                                    Text(result.latestTag)
                                        .font(.system(.body, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                }

                                Divider()

                                HStack {
                                    Text("Latest Build Number")
                                        .fontWeight(.medium)
                                    Spacer()
                                    Text("\(result.latestBuildNumber)")
                                        .font(.system(.body, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                }

                                if let releaseURL = result.releaseURL {
                                    Divider()
                                    Link(destination: releaseURL) {
                                        HStack {
                                            Label("Download Release on GitHub", systemImage: "arrow.up.right.square.fill")
                                                .font(.subheadline.weight(.bold))
                                            Spacer()
                                            Image(systemName: "chevron.right")
                                        }
                                        .padding()
                                        .background(Color.green.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                                        .foregroundStyle(.green)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        } else if let errorMessage {
                            VStack(alignment: .leading, spacing: 12) {
                                HStack {
                                    Label("Connection Interrupted", systemImage: "exclamationmark.triangle.fill")
                                        .foregroundColor(.red)
                                        .font(.headline)
                                    Spacer()
                                }

                                Text(errorMessage)
                                    .font(.subheadline)
                                    .foregroundColor(.red)
                                    .padding()
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(Color.red.opacity(0.08))
                                    .cornerRadius(8)

                                if !diagnosticLogs.isEmpty {
                                    DisclosureGroup("Show Diagnostic Connection Logs") {
                                        ScrollView {
                                            Text(diagnosticLogs)
                                                .font(.system(.caption, design: .monospaced))
                                                .padding(8)
                                                .frame(maxWidth: .infinity, alignment: .leading)
                                        }
                                        .frame(height: 100)
                                        .background(Color.black.opacity(0.15))
                                        .cornerRadius(6)
                                    }
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                }
                            }
                        } else {
                            VStack(spacing: 8) {
                                Text("Check for updates to download the latest builds of SwiftCode.")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.center)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                        }

                        Divider()

                        HStack(spacing: 12) {
                            Button {
                                Task { await checkForUpdates() }
                            } label: {
                                Label(errorMessage != nil ? "Retry Check" : "Check for Updates Now", systemImage: "arrow.clockwise")
                                    .fontWeight(.semibold)
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.large)
                            .tint(.blue)
                            .disabled(isChecking)
                        }
                    }
                    .padding()
                }
                .groupBoxStyle(ModernGroupBoxStyle())
            }
            .padding(24)
        }
        .navigationTitle("Updates")
        .alert(isPresented: $showingErrorAlert) {
            Alert(
                title: Text("Update Check Failed"),
                message: Text(errorMessage ?? "An unknown network error occurred. Please check your internet connection."),
                dismissButton: .default(Text("Dismiss"))
            )
        }
    }

    private func checkForUpdates() async {
        isChecking = true
        errorMessage = nil
        diagnosticLogs = ""
        defer { isChecking = false }

        diagnosticLogs += "[Network] Constructing API query for github releases...\n"
        do {
            checkResult = try await GitHubReleaseCheck.shared.checkLatestBuild()
            diagnosticLogs += "[Network] Successfully retrieved and parsed release data!\n"
        } catch {
            checkResult = nil
            showingErrorAlert = true
            if let checkError = error as? GitHubReleaseCheckError {
                errorMessage = checkError.localizedDescription
                diagnosticLogs += "[Error] Specialized GitHubReleaseCheckError occurred: \(checkError.localizedDescription)\n"
            } else {
                errorMessage = "Unable to check updates. \(error.localizedDescription)"
                diagnosticLogs += "[Error] Standard error occurred: \(error.localizedDescription)\n"
            }
        }
    }
}
