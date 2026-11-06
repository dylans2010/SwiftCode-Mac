import AppKit
import SwiftCodeAssistant
import SwiftCodeIDECore
import SwiftUI

/// Ported from SwiftCode-Legacy `SwiftCode/Views/GitHub/SCSetupOnboard.swift`
/// (Dylan's own code; direct port authorised under MIT).
///
/// First-run setup wizard: Overview → Git Executable → GitHub Token,
/// with Next / Previous and Save and Continue.
///
/// Adaptations for the destination:
/// - Legacy read/wrote `@EnvironmentObject AppSettings` (gitPath,
///   httpsAuthToken) + `KeychainService`. This port stores the git path in
///   the `git_executable_path` UserDefaults key — the same key
///   `GitRepository.resolvedGitPath()` reads — and the GitHub token in the
///   `SecretStore` under `SecretAccount.githubToken` (the same account
///   `GitHubClient(tokenProvider:)` reads), so both settings take effect
///   immediately.
/// - Git detection uses `GitRepository.isGitInstalled()` (staged Group A
///   addition) plus a browse button (NSOpenPanel) to pick the git binary.
/// - Legacy-only `.sourceControlEmbedded()` / `.liquidGlass` dropped.
///
/// Hook: present from the app's first-run / welcome flow when git is not
/// installed or no GitHub token is stored; `onFinished` continues into
/// the workspace.
@MainActor
public struct SCSetupOnboard: View {
    public var store: SecretStore
    public var onFinished: () -> Void

    @State private var step: Step = .overview
    @State private var gitPath: String = GitRepository.resolvedGitPath()
    @State private var gitFound = GitRepository.isGitInstalled()
    @State private var token = ""
    @State private var tokenSaved = false
    @State private var errorMessage: String?

    public enum Step: Int, CaseIterable {
        case overview = 0
        case gitExecutable = 1
        case githubToken = 2

        var title: String {
            switch self {
            case .overview: return "Overview"
            case .gitExecutable: return "Git Executable"
            case .githubToken: return "GitHub Token"
            }
        }
    }

    public init(store: SecretStore = defaultSecretStore(), onFinished: @escaping () -> Void) {
        self.store = store
        self.onFinished = onFinished
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 8) {
                ForEach(Step.allCases, id: \.rawValue) { item in
                    Label(item.title, systemImage: item.rawValue <= step.rawValue ? "checkmark.circle.fill" : "circle")
                        .font(.subheadline)
                        .foregroundStyle(item == step ? .primary : .secondary)
                    if item != .githubToken {
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
            }

            switch step {
            case .overview: overviewStep
            case .gitExecutable: gitStep
            case .githubToken: tokenStep
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.subheadline)
                    .foregroundStyle(.red)
            }

            Spacer()

            HStack {
                Button("Previous") {
                    if let previous = Step(rawValue: step.rawValue - 1) {
                        step = previous
                    }
                }
                .buttonStyle(.bordered)
                .disabled(step == .overview)

                Spacer()

                if step == .githubToken {
                    Button("Save and Continue") {
                        saveAndFinish()
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    Button("Next") {
                        if let next = Step(rawValue: step.rawValue + 1) {
                            step = next
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(step == .gitExecutable && !gitFound)
                }
            }
        }
        .padding(24)
        .frame(width: 560, height: 420)
    }

    private var overviewStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Set Up Source Control")
                .font(.title2.bold())
            Text("SwiftCode needs two things to work with git and GitHub: a git executable on this Mac, and a GitHub personal access token for the GitHub API. This wizard checks both and saves them.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Label("Git: \(gitFound ? "found at \(gitPath)" : "not found")", systemImage: gitFound ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(gitFound ? .green : .orange)
            Label("GitHub token: \(store.readString(SecretAccount.githubToken)?.isEmpty == false ? "saved" : "not saved")", systemImage: "key.fill")
                .foregroundStyle(.secondary)
        }
    }

    private var gitStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Git Executable")
                .font(.title2.bold())
            Text("SwiftCode runs the git command-line tools. Pick the git binary, or browse for one if it was not found automatically.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            HStack {
                TextField("/usr/bin/git", text: $gitPath)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
                    .onChange(of: gitPath) { _, newValue in
                        gitFound = !newValue.isEmpty && FileManager.default.isExecutableFile(atPath: newValue)
                    }
                Button("Browse…") {
                    let panel = NSOpenPanel()
                    panel.canChooseDirectories = false
                    panel.canChooseFiles = true
                    panel.allowsMultipleSelection = false
                    panel.prompt = "Choose Git"
                    if panel.runModal() == .OK, let url = panel.url {
                        gitPath = url.path
                        gitFound = FileManager.default.isExecutableFile(atPath: url.path)
                    }
                }
                .buttonStyle(.bordered)
            }
            if gitFound {
                Label("Git found at \(gitPath).", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else {
                Label("No usable git at that path. Install Git from git-scm.com or browse to the binary.", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            }
        }
    }

    private var tokenStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("GitHub Token")
                .font(.title2.bold())
            Text("A personal access token lets SwiftCode list repositories, branches, commits, pull requests, and workflow runs. Create one at github.com → Settings → Developer settings → Personal access tokens (classic) with the repo scope.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            SecureField("GitHub personal access token", text: $token)
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))
            Text("The token is stored in the keychain, never in plain text.")
                .font(.caption)
                .foregroundStyle(.secondary)
            if tokenSaved {
                Label("Token saved.", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }
        }
    }

    private func saveAndFinish() {
        errorMessage = nil
        UserDefaults.standard.set(gitPath, forKey: "git_executable_path")
        let trimmedToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedToken.isEmpty {
            do {
                try store.write(Data(trimmedToken.utf8), for: SecretAccount.githubToken)
                tokenSaved = true
            } catch {
                errorMessage = "Could not save the token: \(error.localizedDescription)"
                return
            }
        }
        onFinished()
    }
}
