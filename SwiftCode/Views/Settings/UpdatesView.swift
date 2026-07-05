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
        NavigationStack {
            Form {
                Section("Current Version") {
                    LabeledContent("App", value: "SwiftCode")
                    LabeledContent("Build", value: "\(currentBuild)")
                }

                Section("Latest GitHub Build") {
                    if isChecking {
                        HStack(spacing: 12) {
                            ProgressView()
                            Text("Checking Latest Build…")
                                .foregroundStyle(.secondary)
                        }
                    } else if let result = checkResult {
                        LabeledContent("Latest Tag", value: result.latestTag)
                        LabeledContent("Latest Build", value: "\(result.latestBuildNumber)")

                        HStack {
                            Text("Status")
                            Spacer()
                            Text(result.isUpdateAvailable(currentBuild: currentBuild) ? "Update Available" : "You're Up To Date")
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(result.isUpdateAvailable(currentBuild: currentBuild) ? Color.orange.opacity(0.2) : Color.green.opacity(0.2))
                                .foregroundStyle(result.isUpdateAvailable(currentBuild: currentBuild) ? .orange : .green)
                                .clipShape(Capsule())
                        }

                        if let releaseURL = result.releaseURL {
                            Link(destination: releaseURL) {
                                Label("Open Release on GitHub", systemImage: "arrow.up.right.square")
                            }
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
                            .foregroundStyle(.secondary)
                    }

                    Button {
                        Task { await checkForUpdates() }
                    } label: {
                        Label("Check For Updates", systemImage: "arrow.clockwise")
                    }
                    .disabled(isChecking)
                }
            }
            .navigationTitle("Updates")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
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
