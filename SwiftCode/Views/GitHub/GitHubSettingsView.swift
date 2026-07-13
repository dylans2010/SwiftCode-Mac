import SwiftUI

@MainActor
struct GitHubSettingsView: View {
    let project: Project?

    @State private var token = ""
    @State private var gitName = ""
    @State private var gitEmail = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("GitHub & Git Settings")
                    .font(.title.bold())

                GroupBox {
                    VStack(alignment: .leading, spacing: 14) {
                        Label("Personal Access Token (PAT)", systemImage: "key.fill")
                            .font(.headline)
                            .foregroundStyle(.green)

                        Text("Configure a secure GitHub Personal Access Token to authenticate API queries, fetch repository lists, create pull requests, and pull/push changes.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        SecureField("ghp_xxxxxxxxxxxx", text: $token)
                            .textFieldStyle(.roundedBorder)

                        Button("Save Token") {
                            saveToken()
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.green)
                    }
                    .padding()
                }
                .groupBoxStyle(ModernGroupBoxStyle())

                GroupBox {
                    VStack(alignment: .leading, spacing: 14) {
                        Label("Git Committer Identity", systemImage: "person.text.rectangle.fill")
                            .font(.headline)
                            .foregroundStyle(.blue)

                        Text("Identify yourself as the author of local commits. Git embeds these details into commit metadata records.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        TextField("Full Name (e.g., Jane Doe)", text: $gitName)
                            .textFieldStyle(.roundedBorder)

                        TextField("Email Address (e.g., jane@example.com)", text: $gitEmail)
                            .textFieldStyle(.roundedBorder)

                        Button("Save Git Identity") {
                            saveIdentity()
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.blue)
                    }
                    .padding()
                }
                .groupBoxStyle(ModernGroupBoxStyle())
            }
            .padding(24)
        }
        .onAppear {
            token = KeychainService.shared.get(forKey: KeychainService.githubToken) ?? ""
            gitName = AppSettings.shared.gitUserName
            gitEmail = AppSettings.shared.gitUserEmail
        }
    }

    private func saveToken() {
        KeychainService.shared.set(token, forKey: KeychainService.githubToken)
        AppSettings.shared.httpsAuthToken = token
    }

    private func saveIdentity() {
        AppSettings.shared.gitUserName = gitName
        AppSettings.shared.gitUserEmail = gitEmail
    }
}
