import SwiftUI

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
        .navigationTitle("GitHub API Debug")
    }

    private func testGitHubConnection() {
        isTesting = true
        testResult = "Testing..."

        Task {
            do {
                let repos = try await GitHubService.shared.listUserRepositories()
                await MainActor.run {
                    isTesting = false
                    testResult = "Success! Found \(repos.count) repositories."
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
