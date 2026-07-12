import SwiftUI

struct SCSetupOnboard: View {
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.dismiss) private var dismiss

    @State private var gitPath: String = ""
    @State private var githubToken: String = ""
    @State private var isDetecting = false
    @State private var errorMessage: String?
    @State private var activeSection: OnboardingSection = .overview

    enum OnboardingSection: String, CaseIterable, Identifiable {
        case overview = "Overview"
        case git = "Git Executable"
        case github = "GitHub Token"

        var id: String { rawValue }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Segmented picker controls active onboarding section (No Sidebar)
            Picker("Section", selection: $activeSection.animation(.easeInOut)) {
                ForEach(OnboardingSection.allCases) { section in
                    Text(section.rawValue).tag(section)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 24)
            .padding(.top, 20)
            .padding(.bottom, 10)

            Divider()

            ScrollView {
                VStack(spacing: 24) {
                    switch activeSection {
                    case .overview:
                        overviewSectionView
                            .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .move(edge: .leading).combined(with: .opacity)))
                    case .git:
                        gitPathSectionView
                            .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .move(edge: .leading).combined(with: .opacity)))
                    case .github:
                        githubTokenSectionView
                            .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .move(edge: .leading).combined(with: .opacity)))
                    }
                }
                .padding(24)
            }

            Divider()

            // Navigation Controls & Progress Preserver
            HStack {
                if activeSection != .overview {
                    Button("Previous") {
                        goToPrevious()
                    }
                    .buttonStyle(.bordered)
                }

                Spacer()

                if activeSection != .github {
                    Button("Next") {
                        goToNext()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                } else {
                    Button("Save and Continue") {
                        saveAndContinue()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
                    .disabled(gitPath.isEmpty || githubToken.isEmpty)
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
            .background(Color(NSColor.controlBackgroundColor))
        }
        .frame(width: 550, height: 480)
        .onAppear {
            gitPath = settings.gitPath
            githubToken = settings.httpsAuthToken
            if gitPath.isEmpty {
                detectGit()
            }
        }
    }

    // MARK: - Subviews

    private var overviewSectionView: some View {
        VStack(spacing: 20) {
            GroupBox {
                VStack(spacing: 16) {
                    Image(systemName: "arrow.triangle.pull")
                        .font(.system(size: 48))
                        .foregroundStyle(.orange)

                    Text("Source Control Workspace")
                        .font(.title2.bold())

                    Text("Welcome to SwiftCode Source Control Setup. Configure local Git execution pathways and register GitHub accounts to unlock full committing, branching, pulling, and pushing abilities.")
                        .font(.body)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                }
                .padding()
            }
            .groupBoxStyle(ModernGroupBoxStyle())
        }
    }

    private var gitPathSectionView: some View {
        VStack(spacing: 20) {
            GroupBox {
                VStack(alignment: .leading, spacing: 14) {
                    Label("Git Executable Configuration", systemImage: "terminal.fill")
                        .font(.headline)
                        .foregroundColor(.blue)

                    Text("Identify the location of the Git CLI executable on this Mac.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 8) {
                        TextField("/usr/bin/git", text: $gitPath)
                            .textFieldStyle(.roundedBorder)

                        Button("Detect") {
                            detectGit()
                        }
                        .disabled(isDetecting)

                        Button("Browse...") {
                            browseForGit()
                        }
                    }

                    Text("Standard macOS paths include /usr/bin/git or /usr/local/bin/git.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    if let error = errorMessage {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .padding(.top, 4)
                    }
                }
                .padding()
            }
            .groupBoxStyle(ModernGroupBoxStyle())
        }
    }

    private var githubTokenSectionView: some View {
        VStack(spacing: 20) {
            GroupBox {
                VStack(alignment: .leading, spacing: 14) {
                    Label("GitHub Authentication Integration", systemImage: "key.fill")
                        .font(.headline)
                        .foregroundColor(.green)

                    Text("Provide a Personal Access Token (PAT) with repo and workflow permissions to enable seamless syncing with remote repositories.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    SecureField("ghp_xxxxxxxxxxxx", text: $githubToken)
                        .textFieldStyle(.roundedBorder)

                    Link("Create a token on GitHub", destination: URL(string: "https://github.com/settings/tokens")!)
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                .padding()
            }
            .groupBoxStyle(ModernGroupBoxStyle())
        }
    }

    // MARK: - Navigation Actions

    private func goToNext() {
        if let idx = OnboardingSection.allCases.firstIndex(of: activeSection), idx < OnboardingSection.allCases.count - 1 {
            withAnimation {
                activeSection = OnboardingSection.allCases[idx + 1]
            }
        }
    }

    private func goToPrevious() {
        if let idx = OnboardingSection.allCases.firstIndex(of: activeSection), idx > 0 {
            withAnimation {
                activeSection = OnboardingSection.allCases[idx - 1]
            }
        }
    }

    private func detectGit() {
        isDetecting = true
        errorMessage = nil

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = ["git"]

        let pipe = Pipe()
        process.standardOutput = pipe

        do {
            try process.run()
            process.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines), !output.isEmpty {
                gitPath = output
            } else {
                errorMessage = "Could not automatically detect git. Please enter the path manually."
            }
        } catch {
            errorMessage = "Error detecting git: \(error.localizedDescription)"
        }

        isDetecting = false
    }

    private func browseForGit() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.message = "Select the git executable"

        if panel.runModal() == .OK, let url = panel.url {
            gitPath = url.path
        }
    }

    private func saveAndContinue() {
        settings.gitPath = gitPath
        settings.httpsAuthToken = githubToken
        KeychainService.shared.set(githubToken, forKey: KeychainService.githubToken)
        dismiss()
    }
}
