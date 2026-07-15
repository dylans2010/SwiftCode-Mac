import SwiftUI

struct UpdatesView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var isChecking = false
    @State private var checkResult: GitHubReleaseCheckResult?
    @State private var errorMessage: String?

    private var currentBuild: Int {
        Int(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0") ?? 0
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // 1. Current Version GroupBox
                GroupBox {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            Label("Current Version", systemImage: "info.circle")
                                .font(.headline)
                                .foregroundColor(.blue)
                            Spacer()
                        }

                        VStack(spacing: 10) {
                            HStack {
                                Text("App")
                                    .fontWeight(.medium)
                                Spacer()
                                Text("SwiftCode")
                                    .foregroundStyle(.secondary)
                            }
                            Divider()
                            HStack {
                                Text("Build")
                                    .fontWeight(.medium)
                                Spacer()
                                Text("\(currentBuild)")
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .padding()
                }
                .groupBoxStyle(ModernGroupBoxStyle())

                // 2. Latest GitHub Build GroupBox
                GroupBox {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            Label("GitHub Release Status", systemImage: "arrow.triangle.2.circlepath.circle.fill")
                                .font(.headline)
                                .foregroundColor(.green)
                            Spacer()
                        }

                        if isChecking {
                            HStack(spacing: 12) {
                                ProgressView()
                                Text("Checking Latest Build…")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 8)
                        } else if let result = checkResult {
                            VStack(spacing: 12) {
                                HStack {
                                    Text("Latest Tag")
                                        .fontWeight(.medium)
                                    Spacer()
                                    Text(result.latestTag)
                                        .foregroundStyle(.secondary)
                                }
                                Divider()
                                HStack {
                                    Text("Latest Build")
                                        .fontWeight(.medium)
                                    Spacer()
                                    Text("\(result.latestBuildNumber)")
                                        .foregroundStyle(.secondary)
                                }
                                Divider()
                                HStack {
                                    Text("Status")
                                        .fontWeight(.medium)
                                    Spacer()
                                    Text(result.isUpdateAvailable(currentBuild: currentBuild) ? "Update Available" : "You're Up To Date")
                                        .font(.caption.weight(.semibold))
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 4)
                                        .background(result.isUpdateAvailable(currentBuild: currentBuild) ? Color.orange.opacity(0.2) : Color.green.opacity(0.2))
                                        .foregroundStyle(result.isUpdateAvailable(currentBuild: currentBuild) ? .orange : .green)
                                        .clipShape(Capsule())
                                }
                            }
                            .padding(.vertical, 4)

                            if let releaseURL = result.releaseURL {
                                Link(destination: releaseURL) {
                                    Label("Open Release on GitHub", systemImage: "arrow.up.right.square")
                                        .font(.subheadline.weight(.semibold))
                                }
                                .padding(.top, 4)
                            }
                        } else if let errorMessage {
                            VStack(alignment: .leading, spacing: 6) {
                                Label("Update Check Failed", systemImage: "exclamationmark.triangle.fill")
                                    .foregroundStyle(.orange)
                                    .font(.headline)
                                Text(errorMessage)
                                    .foregroundStyle(.red)
                                    .font(.subheadline)
                            }
                        } else {
                            Text("Tap the button below to check for new build-* releases.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }

                        Divider()

                        Button {
                            Task { await checkForUpdates() }
                        } label: {
                            HStack {
                                Spacer()
                                Label("Check For Updates", systemImage: "arrow.clockwise")
                                    .font(.subheadline.weight(.semibold))
                                Spacer()
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .tint(.green)
                        .disabled(isChecking)
                    }
                    .padding()
                }
                .groupBoxStyle(ModernGroupBoxStyle())
            }
            .padding(24)
        }
        .navigationTitle("Updates")
    }

    private func checkForUpdates() async {
        isChecking = true
        errorMessage = nil
        defer { isChecking = false }

        do {
            checkResult = try await GitHubReleaseCheck.shared.checkLatestBuild()
        } catch {
            checkResult = nil
            if let checkError = error as? GitHubReleaseCheckError {
                errorMessage = checkError.localizedDescription
            } else {
                errorMessage = "Unable to check updates. \(error.localizedDescription)"
            }
        }
    }
}
