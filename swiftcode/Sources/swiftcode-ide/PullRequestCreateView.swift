import Foundation
import SwiftCodeIDECore
import SwiftUI
import SwiftCodeAssistant
import SwiftCodeGitHub

struct PullRequestCreateView: View {
    var owner: String
    var repo: String

    @Environment(\.colorScheme) private var scheme
    @State private var headBranch = ""
    @State private var baseBranch = "main"
    @State private var title = ""
    @State private var bodyText = ""
    @State private var isDraft = false
    @State private var branches: [String] = []
    @State private var isLoadingBranches = false
    @State private var isCreating = false
    @State private var statusMessage: String?
    @State private var statusIsError = false
    @State private var createdURL: URL?

    private var client: GitHubClient {
        GitHubClient(tokenProvider: {
            CodingAssistantServices.shared.store.readString(SecretAccount.githubToken)
        })
    }

    private var canCreate: Bool {
        !owner.trimmingCharacters(in: .whitespaces).isEmpty
            && !repo.trimmingCharacters(in: .whitespaces).isEmpty
            && !headBranch.trimmingCharacters(in: .whitespaces).isEmpty
            && !baseBranch.trimmingCharacters(in: .whitespaces).isEmpty
            && !title.trimmingCharacters(in: .whitespaces).isEmpty
            && headBranch != baseBranch
    }

    var body: some View {
        let c = ShellColors(scheme)
        VStack(alignment: .leading, spacing: 10) {
            Text("Create Pull Request").font(ShellFonts.rowBold)
            HStack(spacing: 8) {
                TextField("Owner", text: .constant(owner))
                    .textFieldStyle(.roundedBorder)
                    .disabled(true)
                Text("/").foregroundStyle(c.secondaryLabel)
                TextField("Repository", text: .constant(repo))
                    .textFieldStyle(.roundedBorder)
                    .disabled(true)
            }
            Text("Head and base branches are loaded from GitHub. A token must be saved in Settings ▸ Coding Assistant ▸ GitHub, or creating the PR fails with the client's missing-token error.")
                .font(ShellFonts.small)
                .foregroundStyle(c.secondaryLabel)
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Head branch").font(ShellFonts.small).foregroundStyle(c.secondaryLabel)
                    Picker("Head branch", selection: $headBranch) {
                        ForEach(branches, id: \.self) { branch in
                            Text(verbatim: branch).tag(branch)
                        }
                    }
                    .pickerStyle(.menu)
                    .disabled(branches.isEmpty)
                }
                Image(systemName: "arrow.right")
                    .foregroundStyle(c.secondaryLabel)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Base branch").font(ShellFonts.small).foregroundStyle(c.secondaryLabel)
                    Picker("Base branch", selection: $baseBranch) {
                        ForEach(branches, id: \.self) { branch in
                            Text(verbatim: branch).tag(branch)
                        }
                    }
                    .pickerStyle(.menu)
                    .disabled(branches.isEmpty)
                }
                if isLoadingBranches { ProgressView().controlSize(.small) }
            }
            TextField("Title", text: $title)
                .textFieldStyle(.roundedBorder)
            Text("Description").font(ShellFonts.small).foregroundStyle(c.secondaryLabel)
            TextEditor(text: $bodyText)
                .font(.system(.body, design: .default))
                .frame(minHeight: 120)
                .border(c.fieldStroke)
            Toggle("Create as draft", isOn: $isDraft)
                .font(ShellFonts.row)
            HStack {
                Button("Create Pull Request") { create() }
                    .buttonStyle(.borderedProminent)
                    .disabled(!canCreate || isCreating)
                Button("Reload Branches") { loadBranches() }
                    .disabled(isLoadingBranches)
                Spacer()
            }
            if let createdURL {
                Link("Open pull request #\(createdURL.lastPathComponent) on GitHub", destination: createdURL)
                    .font(ShellFonts.small)
            }
            if let statusMessage {
                Text(verbatim: statusMessage)
                    .font(ShellFonts.small)
                    .foregroundStyle(statusIsError ? .red : .green)
            }
            Spacer()
        }
        .padding(12)
        .onAppear { loadBranches() }
    }

    private func loadBranches() {
        isLoadingBranches = true
        statusMessage = nil
        Task {
            do {
                let listed = try await client.listBranches(owner: owner, repo: repo, perPage: 100)
                branches = listed.map(\.name)
                if branches.contains("main") { baseBranch = "main" }
                else if let first = branches.first { baseBranch = first }
                if let first = branches.first(where: { $0 != baseBranch }) {
                    headBranch = first
                }
            } catch {
                statusIsError = true
                statusMessage = "Could not list branches: \(error.localizedDescription)"
            }
            isLoadingBranches = false
        }
    }

    private func create() {
        isCreating = true
        statusIsError = false
        createdURL = nil
        Task {
            do {
                let pr = try await client.createPullRequest(
                    owner: owner, repo: repo, title: title,
                    body: bodyText.isEmpty ? nil : bodyText,
                    head: headBranch, base: baseBranch, draft: isDraft)
                statusMessage = "Pull request #\(pr.number) created."
                createdURL = URL(string: pr.htmlUrl)
            } catch {
                statusIsError = true
                statusMessage = "Could not create the pull request: \(error.localizedDescription)"
            }
            isCreating = false
        }
    }
}
