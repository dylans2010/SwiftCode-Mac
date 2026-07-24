import SwiftUI

@MainActor
struct GitCommitComposerView: View {
    @Binding var message: String
    let gitViewModel: GitViewModel
    let onCommit: () -> Void

    @State private var commitType = "feat"
    @State private var scope = ""
    @State private var title = ""
    @State private var bodyText = ""
    @State private var coAuthor = ""
    @State private var isSigning = false
    @State private var isAmending = false
    @State private var noVerify = false
    @State private var isGeneratingAI = false
    @State private var showAdvanced = false

    private let commitTypes = [
        "feat": "New Feature",
        "fix": "Bug Fix",
        "docs": "Documentation",
        "style": "Styling/Formatting",
        "refactor": "Refactoring",
        "test": "Testing",
        "chore": "Maintenance",
        "perf": "Performance",
        "ci": "CI/CD"
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Label("Commit Composer", systemImage: "pencil.and.outline")
                    .font(.headline)
                    .foregroundStyle(.orange)

                Spacer()

                if isGeneratingAI {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Button {
                        generateAICommitMessage()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "sparkles")
                                .foregroundStyle(.purple)
                            Text("AI Draft")
                                .font(.caption.bold())
                        }
                    }
                    .buttonStyle(.bordered)
                    .help("Review diff and suggest a commit message using AI")
                }
            }

            // Composer fields
            VStack(spacing: 10) {
                // Conventional Commit Type
                HStack {
                    Text("Type")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                        .frame(width: 50, alignment: .leading)

                    Picker("", selection: $commitType) {
                        ForEach(commitTypes.keys.sorted(), id: \.self) { key in
                            Text("\(key) - \(commitTypes[key] ?? "")").tag(key)
                        }
                    }
                    .pickerStyle(.menu)
                }

                // Scope & Title
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Scope")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.secondary)
                        TextField("e.g. ui", text: $scope)
                            .textFieldStyle(.roundedBorder)
                    }
                    .frame(width: 80)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Summary Title")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.secondary)
                        TextField("Summarize changes in 50 chars", text: $title)
                            .textFieldStyle(.roundedBorder)
                    }
                }

                // Detailed Body
                VStack(alignment: .leading, spacing: 4) {
                    Text("Detailed Description (Body)")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)

                    TextEditor(text: $bodyText)
                        .font(.system(.body, design: .monospaced))
                        .frame(minHeight: 80, maxHeight: 150)
                        .cornerRadius(6)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                        )
                }

                // Co-Author & Advanced Options
                DisclosureGroup("Advanced & Options", isExpanded: $showAdvanced) {
                    VStack(alignment: .leading, spacing: 10) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Co-Author")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.secondary)
                            TextField("Name <email>", text: $coAuthor)
                                .textFieldStyle(.roundedBorder)
                        }
                        .padding(.top, 4)

                        HStack(spacing: 16) {
                            Toggle("Sign Commit", isOn: $isSigning)
                                .toggleStyle(.checkbox)
                            Toggle("Amend Last", isOn: $isAmending)
                                .toggleStyle(.checkbox)
                            Toggle("Bypass Hooks", isOn: $noVerify)
                                .toggleStyle(.checkbox)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .font(.caption)

                // Action Commit Button
                Button(action: {
                    message = assembleMessage()
                    onCommit()
                    // Clear fields after successful commit triggers
                    title = ""
                    bodyText = ""
                }) {
                    Label("Commit to Local Branch", systemImage: "arrow.triangle.branch")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
                .controlSize(.large)
                .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(12)
        .background(Color(NSColor.windowBackgroundColor).opacity(0.4))
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.secondary.opacity(0.15), lineWidth: 1)
        )
        .onChange(of: commitType) { _, _ in updateParentBinding() }
        .onChange(of: scope) { _, _ in updateParentBinding() }
        .onChange(of: title) { _, _ in updateParentBinding() }
        .onChange(of: bodyText) { _, _ in updateParentBinding() }
        .onChange(of: coAuthor) { _, _ in updateParentBinding() }
    }

    private func updateParentBinding() {
        message = assembleMessage()
    }

    private func assembleMessage() -> String {
        var msg = commitType
        let cleanScope = scope.trimmingCharacters(in: .whitespacesAndNewlines)
        if !cleanScope.isEmpty {
            msg += "(\(cleanScope))"
        }
        msg += ": \(title.trimmingCharacters(in: .whitespacesAndNewlines))"

        let cleanBody = bodyText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !cleanBody.isEmpty {
            msg += "\n\n\(cleanBody)"
        }

        let cleanCoAuthor = coAuthor.trimmingCharacters(in: .whitespacesAndNewlines)
        if !cleanCoAuthor.isEmpty {
            msg += "\n\nCo-authored-by: \(cleanCoAuthor)"
        }

        return msg
    }

    private func generateAICommitMessage() {
        isGeneratingAI = true
        Task {
            do {
                let hunks = await gitViewModel.getDiff()
                var diffText = ""
                for hunk in hunks {
                    diffText += "Hunk: \(hunk.header)\n"
                    for line in hunk.lines {
                        diffText += "\(line)\n"
                    }
                }

                if diffText.isEmpty {
                    if let files = gitViewModel.status?.files {
                        diffText = "Modified Files:\n" + files.map { "\($0.status.rawValue): \($0.path)" }.joined(separator: "\n")
                    }
                }

                if diffText.isEmpty {
                    diffText = "No changes found in active working copy."
                }

                let prompt = """
                You are a Git commit expert. Review the following Git diff and generate a clear, professional, conventional commit message.
                Follow the Conventional Commits specification (e.g. feat(scope): message).
                Return ONLY a JSON object with the following keys, and NO other text, markdown formatting, or triple backticks:
                {
                  "type": "feat|fix|chore|docs|refactor|test|style|perf|ci",
                  "scope": "short scope if applicable, otherwise empty",
                  "title": "short summary under 50 characters",
                  "body": "optional longer description of changes"
                }

                Git Diff:
                \(diffText.prefix(2500))
                """

                let response = try await LLMService.shared.generateExternalResponse(prompt: prompt, useContext: false)

                // Sanitize and decode JSON
                let cleanResponse = response.trimmingCharacters(in: .whitespacesAndNewlines)
                    .replacingOccurrences(of: "```json", with: "")
                    .replacingOccurrences(of: "```", with: "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)

                if let data = cleanResponse.data(using: .utf8),
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: String] {
                    if let t = json["type"], !t.isEmpty { commitType = t }
                    if let s = json["scope"] { scope = s }
                    if let ti = json["title"] { title = ti }
                    if let b = json["body"] { bodyText = b }
                } else {
                    // Fallback to plain parsing
                    commitType = "chore"
                    scope = ""
                    title = "update codebase"
                    bodyText = response
                }
            } catch {
                title = "code changes"
                bodyText = "Failed to run AI Model: \(error.localizedDescription)"
            }
            updateParentBinding()
            isGeneratingAI = false
        }
    }
}
