import SwiftUI

public struct NSCloneView: View {
    @State private var cloneURL = ""
    @State private var successMsg = ""
    @State private var errorMsg = ""
    @State private var isLoading = false

    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Git Clone", systemImage: "plus.square.on.square")
                .font(.headline)
                .foregroundStyle(.green)

            Text("Clone a repository into your workspace.")
                .font(.caption)
                .foregroundStyle(.secondary)

            TextField("Repository URL...", text: $cloneURL)
                .textFieldStyle(.roundedBorder)
                .disabled(isLoading)

            if isLoading {
                ProgressView()
                    .progressViewStyle(.linear)
                    .padding(.vertical, 4)
            }

            if !successMsg.isEmpty {
                Text(successMsg)
                    .font(.caption)
                    .foregroundStyle(.green)
            }

            if !errorMsg.isEmpty {
                Text(errorMsg)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            Button("Clone Repository") {
                let urlStr = cloneURL.trimmingCharacters(in: .whitespacesAndNewlines)
                guard let remoteURL = URL(string: urlStr) else {
                    errorMsg = "Invalid repository URL."
                    return
                }

                Task {
                    isLoading = true
                    successMsg = ""
                    errorMsg = ""
                    do {
                        var repoName = remoteURL.deletingPathExtension().lastPathComponent
                        if repoName.isEmpty {
                            repoName = "ClonedRepository"
                        }

                        let destinationURL = CodingManager.shared.projectsRoot.appendingPathComponent(repoName)

                        if FileManager.default.fileExists(atPath: destinationURL.path) {
                            throw GitMenuBarError.gitError("Folder '\(repoName)' already exists.")
                        }

                        let token = APIKeyManager.shared.retrieveKey(service: .gitHub) ?? KeychainService.shared.get(forKey: KeychainService.githubToken)

                        try await GitService.shared.clone(remoteURL: remoteURL, destinationURL: destinationURL, token: token)

                        let project = try await ProjectSessionStore.shared.importProject(from: destinationURL)
                        await ProjectSessionStore.shared.openProject(project)

                        successMsg = "Successfully cloned and opened '\(repoName)'!"
                        cloneURL = ""
                    } catch {
                        errorMsg = "Failed: \(error.localizedDescription)"
                    }
                    isLoading = false
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .disabled(cloneURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isLoading)
        }
        .padding()
        .frame(width: 280)
    }
}
