import SwiftUI

// MARK: - Pull Request View

struct PullRequestView: View {
    let owner: String
    let repo: String
    let currentBranch: String
    let draftPayload: PullRequestDraftPayload?

    @State private var branches: [GitHubBranch] = []
    @State private var headBranch: String = ""
    @State private var baseBranch: String = "main"
    @State private var title: String = ""
    @State private var bodyText: String = ""
    @State private var reviewersInput: String = ""
    @State private var labelsInput: String = ""
    @State private var milestone: String = ""
    @State private var isDraft = false
    @State private var isSubmitting = false
    @State private var notification: PRNotification?
    @State private var createdPRURL: String?
    @State private var showSuccessSheet = false

    @Environment(\.dismiss) private var dismiss

    init(owner: String, repo: String, currentBranch: String, draftPayload: PullRequestDraftPayload? = nil) {
        self.owner = owner
        self.repo = repo
        self.currentBranch = currentBranch
        self.draftPayload = draftPayload
        _headBranch = State(initialValue: draftPayload == nil ? "" : currentBranch)
        _title = State(initialValue: draftPayload?.title ?? "")
        _bodyText = State(initialValue: draftPayload?.description ?? "")
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Card 1: Branch Target Selection
                    GroupBox {
                        VStack(alignment: .leading, spacing: 14) {
                            HStack {
                                Label("Compare & Pull Branches", systemImage: "arrow.triangle.branch")
                                    .font(.headline)
                                    .foregroundColor(.purple)
                                Spacer()
                            }

                            VStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text("Compare (Source)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    branchPicker(selection: $headBranch)
                                }

                                HStack {
                                    Spacer()
                                    Image(systemName: "arrow.down")
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                }

                                VStack(alignment: .leading, spacing: 6) {
                                    Text("Base (Target)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    branchPicker(selection: $baseBranch)
                                }

                                if headBranch == baseBranch && !headBranch.isEmpty {
                                    HStack(spacing: 6) {
                                        Image(systemName: "exclamationmark.triangle.fill")
                                            .foregroundStyle(.yellow)
                                            .font(.caption)
                                        Text("Source and target branches must be different.")
                                            .font(.caption)
                                            .foregroundStyle(.yellow)
                                    }
                                }
                            }
                        }
                        .padding()
                    }
                    .groupBoxStyle(ModernGroupBoxStyle())

                    // Card 2: Pull Request Title
                    GroupBox {
                        VStack(alignment: .leading, spacing: 14) {
                            HStack {
                                Label("Pull Request Title", systemImage: "textformat")
                                    .font(.headline)
                                    .foregroundColor(.orange)
                                Spacer()
                            }

                            TextField("Describe Changes concisely", text: $title)
                                .textFieldStyle(.roundedBorder)
                                .autocorrectionDisabled()
                        }
                        .padding()
                    }
                    .groupBoxStyle(ModernGroupBoxStyle())

                    // Card 3: Description Body
                    GroupBox {
                        VStack(alignment: .leading, spacing: 14) {
                            HStack {
                                Label("Pull Request Description", systemImage: "doc.text")
                                    .font(.headline)
                                    .foregroundColor(.blue)
                                Spacer()
                            }

                            TextEditor(text: $bodyText)
                                .frame(minHeight: 120)
                                .font(.body)
                                .cornerRadius(8)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                                )
                                .overlay(alignment: .topLeading) {
                                    if bodyText.isEmpty {
                                        Text("Add Description (Supports Markdown)")
                                            .font(.body)
                                            .foregroundStyle(.tertiary)
                                            .padding(.top, 8)
                                            .padding(.leading, 5)
                                            .allowsHitTesting(false)
                                    }
                                }
                        }
                        .padding()
                    }
                    .groupBoxStyle(ModernGroupBoxStyle())

                    // Card 4: Reviewers & Tags Options
                    GroupBox {
                        VStack(alignment: .leading, spacing: 14) {
                            HStack {
                                Label("Optional Configurations", systemImage: "slider.horizontal.3")
                                    .font(.headline)
                                    .foregroundColor(.green)
                                Spacer()
                            }

                            VStack(spacing: 12) {
                                optionalField(
                                    label: "Reviewers",
                                    placeholder: "username1, username2",
                                    text: $reviewersInput,
                                    icon: "person.2",
                                    hint: "Comma-separated GitHub usernames"
                                )

                                optionalField(
                                    label: "Labels",
                                    placeholder: "bug, enhancement",
                                    text: $labelsInput,
                                    icon: "tag",
                                    hint: "Comma-separated label names"
                                )

                                optionalField(
                                    label: "Milestone",
                                    placeholder: "v1.0.0",
                                    text: $milestone,
                                    icon: "flag",
                                    hint: "Milestone Title (Optional)"
                                )

                                HStack {
                                    Label("Draft Pull Request", systemImage: "doc.badge.clock")
                                        .font(.subheadline)
                                    Spacer()
                                    Toggle("", isOn: $isDraft)
                                        .labelsHidden()
                                        .tint(.orange)
                                }
                                .padding(8)
                                .background(Color.secondary.opacity(0.05))
                                .cornerRadius(6)
                            }
                        }
                        .padding()
                    }
                    .groupBoxStyle(ModernGroupBoxStyle())

                    // Action Submission Card
                    GroupBox {
                        VStack(alignment: .leading, spacing: 14) {
                            if !canSubmit {
                                HStack(spacing: 8) {
                                    Image(systemName: "info.circle")
                                        .foregroundStyle(.secondary)
                                    Text(validationMessage)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }

                            Button {
                                Task { await submitPullRequest() }
                            } label: {
                                HStack {
                                    if isSubmitting {
                                        ProgressView().scaleEffect(0.9)
                                    } else {
                                        Image(systemName: isDraft ? "doc.badge.clock" : "arrow.triangle.pull")
                                    }
                                    Text(isDraft ? "Create Draft PR" : "Create Pull Request")
                                        .fontWeight(.semibold)
                                }
                                .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.large)
                            .tint(.purple)
                            .disabled(!canSubmit || isSubmitting)
                        }
                        .padding()
                    }
                    .groupBoxStyle(ModernGroupBoxStyle())
                }
                .padding(24)
            }
            .background(Color(NSColor.windowBackgroundColor))
            .navigationTitle("New Pull Request")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .overlay(alignment: .bottom) {
                if let n = notification {
                    prNotificationBanner(n)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .padding(.bottom, 16)
                }
            }
            .animation(.easeInOut(duration: 0.3), value: notification != nil)
            .sheet(isPresented: $showSuccessSheet) {
                successSheet
            }
        }
        .task { await loadBranches() }
        .onAppear {
            if let draftPayload {
                title = draftPayload.title
                bodyText = draftPayload.description
            }
        }
    }

    private func branchPicker(selection: Binding<String>) -> some View {
        Menu {
            ForEach(branches) { branch in
                Button {
                    selection.wrappedValue = branch.name
                } label: {
                    HStack {
                        Text(branch.name)
                        if selection.wrappedValue == branch.name {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            HStack {
                Text(selection.wrappedValue.isEmpty ? "Select Branch" : selection.wrappedValue)
                    .font(.subheadline)
                    .foregroundStyle(selection.wrappedValue.isEmpty ? Color.secondary : Color.primary)
                Spacer()
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }

    private func optionalField(label: String, placeholder: String, text: Binding<String>, icon: String, hint: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(label, systemImage: icon)
                .font(.caption.bold())
                .foregroundStyle(.secondary)
            TextField(placeholder, text: text)
                .textFieldStyle(.roundedBorder)
                .autocorrectionDisabled()
            Text(hint)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: - Success Sheet

    private var successSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 64))
                        .foregroundStyle(.green)

                    Text("Pull Request Created!")
                        .font(.title2.bold())

                    if let urlStr = createdPRURL, let url = URL(string: urlStr) {
                        Link(destination: url) {
                            Label("View On GitHub", systemImage: "safari")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(Color.orange, in: RoundedRectangle(cornerRadius: 12))
                                .foregroundStyle(.white)
                        }
                        .padding(.horizontal, 32)
                    }

                    Button("Done") {
                        showSuccessSheet = false
                        dismiss()
                    }
                    .buttonStyle(.bordered)
                }
                .padding(24)
            }
            .background(Color(NSColor.windowBackgroundColor))
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        showSuccessSheet = false
                        dismiss()
                    }
                }
            }
        }
    }

    // MARK: - PR Notification Banner

    private func prNotificationBanner(_ n: PRNotification) -> some View {
        HStack(spacing: 10) {
            Image(systemName: n.isError ? "xmark.circle.fill" : "checkmark.circle.fill")
                .foregroundStyle(n.isError ? .red : .green)
            Text(n.message)
                .font(.subheadline)
            Spacer()
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.ultraThinMaterial)
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(
                    n.isError ? Color.red.opacity(0.4) : Color.green.opacity(0.4),
                    lineWidth: 1
                ))
        )
        .padding(.horizontal, 16)
    }

    // MARK: - Validation

    private var canSubmit: Bool {
        !title.trimmingCharacters(in: .whitespaces).isEmpty &&
        !headBranch.isEmpty &&
        !baseBranch.isEmpty &&
        headBranch != baseBranch
    }

    private var validationMessage: String {
        if title.trimmingCharacters(in: .whitespaces).isEmpty { return "Enter a pull request title." }
        if headBranch.isEmpty { return "Select a source (compare) branch." }
        if baseBranch.isEmpty { return "Select a target (base) branch." }
        if headBranch == baseBranch { return "Source and target branches must be different." }
        return ""
    }

    // MARK: - Actions

    private func loadBranches() async {
        guard !owner.isEmpty else { return }
        do {
            let fetched = try await GitHubService.shared.listBranches(owner: owner, repo: repo)
            branches = fetched
            headBranch = draftPayload == nil ? currentBranch : headBranch
            baseBranch = fetched.first(where: { $0.name == "main" || $0.name == "master" })?.name
                ?? fetched.first(where: { $0.name != currentBranch })?.name
                ?? currentBranch
        } catch {
            // Silently fall back to empty list; user can still type branch names
        }
    }

    private func submitPullRequest() async {
        guard canSubmit else { return }
        isSubmitting = true
        defer { isSubmitting = false }

        let reviewersList = reviewersInput
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        let labelsList = labelsInput
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        do {
            let pr = try await GitHubService.shared.createPullRequest(
                owner: owner,
                repo: repo,
                title: title.trimmingCharacters(in: .whitespaces),
                body: bodyText,
                head: headBranch,
                base: baseBranch,
                reviewers: reviewersList,
                labels: labelsList,
                milestone: milestone.trimmingCharacters(in: .whitespaces),
                isDraft: isDraft
            )
            createdPRURL = pr.htmlUrl
            showSuccessSheet = true
        } catch {
            showNotification(error.localizedDescription, isError: true)
        }
    }

    private func showNotification(_ message: String, isError: Bool) {
        notification = PRNotification(message: message, isError: isError)
        Task {
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            notification = nil
        }
    }
}

// MARK: - Supporting Types

private struct PRNotification: Equatable {
    let message: String
    let isError: Bool
}
