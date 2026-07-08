import SwiftUI

struct SCSetupOnboard: View {
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.dismiss) private var dismiss

    @State private var gitPath: String = ""
    @State private var githubToken: String = ""
    @State private var isDetecting = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 20) {
            header

            VStack(alignment: .leading, spacing: 15) {
                gitPathSection
                githubTokenSection
            }
            .padding()
            .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))

            if let error = errorMessage {
                Text(error)
                    .foregroundStyle(.red)
                    .font(.caption)
            }

            Spacer()

            Button {
                saveAndContinue()
            } label: {
                Text("Save and Continue")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue, in: RoundedRectangle(cornerRadius: 10))
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
            .disabled(gitPath.isEmpty || githubToken.isEmpty)
        }
        .padding(30)
        .frame(width: 500, height: 450)
        .onAppear {
            gitPath = settings.gitPath
            githubToken = settings.httpsAuthToken
            if gitPath.isEmpty {
                detectGit()
            }
        }
    }

    private var header: some View {
        VStack(spacing: 8) {
            Image(systemName: "arrow.triangle.pull")
                .font(.system(size: 50))
                .foregroundStyle(.blue)

            Text("Source Control Setup")
                .font(.title.bold())

            Text("Configure Git and GitHub to start managing your code.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var gitPathSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Git Executable Path")
                .font(.headline)

            HStack {
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

            Text("Usually /usr/bin/git or /usr/local/bin/git")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var githubTokenSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("GitHub Personal Access Token")
                .font(.headline)

            SecureField("ghp_xxxxxxxxxxxx", text: $githubToken)
                .textFieldStyle(.roundedBorder)

            Link("Create a token on GitHub", destination: URL(string: "https://github.com/settings/tokens")!)
                .font(.caption)
                .foregroundStyle(.blue)
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
        // Also save to Keychain for GitHubService if needed
        KeychainService.shared.set(githubToken, forKey: KeychainService.githubToken)
        dismiss()
    }
}
