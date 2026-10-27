import SwiftUI

/// Settings destination for software updates.
///
/// This view is only a control surface for `AppUpdateService` (Sparkle 2).
/// It performs no version checking, downloading or installation itself,
/// and it no longer links out to GitHub as an install path — the old
/// `GitHubReleaseCheck` flow (which only opened a release page) was
/// removed with this view's rewrite.
///
/// The same view is embedded from `SettingsView`, `GeneralSettingsView`
/// (as a sheet) and `NativeUpdatesSettingsView`; all three routes now
/// reach the same updater.
struct UpdatesView: View {
    @ObservedObject private var updates = AppUpdateService.shared

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
                        Text("Keep SwiftCode up to date with verified releases.")
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
                                Text(AppUpdateConfiguration.currentDisplayVersion)
                                    .foregroundStyle(.secondary)
                            }
                            Divider()
                            HStack {
                                Text("Build Number")
                                    .fontWeight(.medium)
                                Spacer()
                                Text(AppUpdateConfiguration.currentBuildVersion)
                                    .font(.system(.body, design: .monospaced))
                                    .foregroundStyle(.secondary)
                            }
                            Divider()
                            HStack {
                                Text("Update Feed")
                                    .fontWeight(.medium)
                                Spacer()
                                Text(AppUpdateConfiguration.feedURLString)
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
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

                        if updates.isChecking {
                            VStack(spacing: 14) {
                                ProgressView()
                                    .progressViewStyle(.circular)
                                Text("Checking the update feed…")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 20)
                        } else if let pending = updates.pendingUpdate {
                            VStack(spacing: 14) {
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("New Update Available!")
                                            .font(.headline)
                                            .foregroundColor(.orange)
                                        Text("SwiftCode \(pending.displayVersion) is ready to install.")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Image(systemName: "arrow.down.circle.fill")
                                        .font(.title)
                                        .foregroundColor(.orange)
                                }
                                Button("Show Update Window") {
                                    updates.bringUpdateWindowToFront()
                                }
                                .buttonStyle(.borderedProminent)
                                .frame(maxWidth: .infinity)
                            }
                        } else if updates.lastCheckWasUpToDate {
                            VStack(spacing: 14) {
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("You’re Fully Up To Date")
                                            .font(.headline)
                                            .foregroundColor(.green)
                                        Text("SwiftCode is running the latest available version.")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Image(systemName: "checkmark.seal.fill")
                                        .font(.title)
                                        .foregroundColor(.green)
                                }
                                if let lastCheck = updates.lastCheckDate {
                                    Text("Last checked \(lastCheck, style: .relative).")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        } else if let errorMessage = updates.lastErrorMessage {
                            VStack(alignment: .leading, spacing: 12) {
                                Label("Update Check Failed", systemImage: "exclamationmark.triangle.fill")
                                    .foregroundColor(.red)
                                    .font(.headline)
                                Text(errorMessage)
                                    .font(.subheadline)
                                    .foregroundColor(.red)
                                    .padding()
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(Color.red.opacity(0.08))
                                    .cornerRadius(8)
                            }
                        } else if let startupError = updates.startupErrorMessage {
                            VStack(alignment: .leading, spacing: 12) {
                                Label("Updater Could Not Start", systemImage: "exclamationmark.triangle.fill")
                                    .foregroundColor(.red)
                                    .font(.headline)
                                Text(startupError)
                                    .font(.subheadline)
                                    .foregroundColor(.red)
                                    .padding()
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(Color.red.opacity(0.08))
                                    .cornerRadius(8)
                                Text("SwiftCode still runs normally. Fix the updater configuration and use Check for Updates to try again.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        } else {
                            VStack(spacing: 8) {
                                Text("Check for updates to see the latest version of SwiftCode.")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.center)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                        }

                        Divider()

                        Button {
                            updates.checkForUpdates()
                        } label: {
                            Label(
                                updates.lastErrorMessage != nil ? "Retry Check" : "Check for Updates Now",
                                systemImage: "arrow.clockwise"
                            )
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .tint(.blue)
                        .disabled(updates.isChecking || updates.sessionInProgress)
                    }
                    .padding()
                }
                .groupBoxStyle(ModernGroupBoxStyle())

                // 3. Automatic Updates Card
                GroupBox {
                    VStack(alignment: .leading, spacing: 16) {
                        Label("Automatic Updates", systemImage: "gearshape.fill")
                            .font(.headline)
                            .foregroundColor(.blue)
                        Toggle(
                            "Check for updates automatically",
                            isOn: Binding(
                                get: { updates.automaticallyChecksForUpdates },
                                set: { updates.automaticallyChecksForUpdates = $0 }
                            )
                        )
                        Toggle(
                            "Automatically download and install updates in the future",
                            isOn: Binding(
                                get: { updates.automaticallyDownloadsUpdates },
                                set: { updates.automaticallyDownloadsUpdates = $0 }
                            )
                        )
                        .disabled(!updates.allowsAutomaticUpdates)
                        Text("Automatic checks run about once a day. Manual checks always work, even when automatic checking is off. Skipped versions are remembered by the updater; a manual check re-offers a skipped version.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if !updates.publicKeyConfigured {
                            Label(
                                "No EdDSA public key (SUPublicEDKey) is configured yet. Update discovery works, but Sparkle will refuse to install updates until a key is generated and embedded. See Docs/Updates.md.",
                                systemImage: "exclamationmark.triangle.fill"
                            )
                            .font(.caption)
                            .foregroundStyle(.orange)
                            .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding()
                }
                .groupBoxStyle(ModernGroupBoxStyle())
            }
            .padding(24)
        }
        .navigationTitle("Updates")
    }
}
