// Ported from SwiftCode-Legacy `SwiftCode/Views/Developer/GitHubAPIDebug/GitHubAPIDebugView.swift` (Dylan's own code; direct port authorised under MIT).
// Audit A: MISSING at bc28f653. Static port only — no Swift toolchain here; build verification pending on Dylan's Mac.
// Adaptation: Legacy read the token from `KeychainService` and fetched
// repos through `GitHubService` — neither exists in production.
// Production equivalents: the token lives in the assistant's secret
// store (`SecretAccount.githubToken`, keychain on macOS) and the API
// client is `GitHubClient` (SwiftCodeGitHub), which reads the token via
// its `tokenProvider` on each request and throws `GitHubError
// .missingToken` when there is none. Same behaviour, same messages.
import SwiftUI
import SwiftCodeUI
import SwiftCodeAssistant
import SwiftCodeGitHub

struct GitHubAPIDebugView: View {
    @State private var isTesting = false
    @State private var testResult: String?
    @State private var resultColor: Color = .primary

    var body: some View {
        Form {
            Section("Manual Testing") {
                Button(action: testGitHubConnection) {
                    if isTesting {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("Test GET /user (Check Connection)")
                    }
                }
                .disabled(isTesting)

                if let result = testResult {
                    Text(result)
                        .font(.caption.monospaced())
                        .foregroundStyle(resultColor)
                }
            }

            Section("Info") {
                Text("This tests the current GitHub token by attempting to fetch the user's repositories.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .liquidGlass(style: .subtle, cornerRadius: 12)
        .navigationTitle("GitHub API Debug")
    }

    private func testGitHubConnection() {
        isTesting = true
        testResult = "Testing..."

        Task {
            do {
                let store = defaultSecretStore()
                let client = GitHubClient(tokenProvider: { store.readString(SecretAccount.githubToken) })
                let user = try await client.getAuthenticatedUser()
                let repos = try await client.listUserRepositories()
                await MainActor.run {
                    isTesting = false
                    testResult = "Success! Connected as \(user.login). Found \(repos.count) repositories."
                    resultColor = .green
                }
            } catch {
                await MainActor.run {
                    isTesting = false
                    testResult = "Error: \(error.localizedDescription)"
                    resultColor = .red
                }
            }
        }
    }
}
