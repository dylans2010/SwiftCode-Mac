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
            ZStack {
                Color(red: 0.08, green: 0.08, blue: 0.12).ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 20) {
                        branchSelectionSection
                        titleSection
                        descriptionSection
                        optionalSection
                        submitSection
                    }
                    .padding()
                }
            }
            .navigationTitle("New Pull Request")
            .navigationBarTitleDisplayMode(.inline)
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
        .preferredColorScheme(.dark)
        .task { await loadBranches() }
        .onAppear {
            if let draftPayload {
                title = draftPayload.title
                bodyText = draftPayload.description
            }
        }
    }

    // MARK: - Branch Selection

    private var branchSelectionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Branches", icon: "arrow.triangle.branch", color: .purple)

            VStack(spacing: 12) {
                // Compare (head) branch
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

                // Base (target) branch
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
            .padding()
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
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
                    .foregroundStyle(selection.wrappedValue.isEmpty ? Color.secondary : Color.white)
                Spacer()
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
        }
    }

    // MARK: - Title Section

    private var titleSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Title", icon: "textformat", color: .orange)

            TextField("Describe Changes", text: $title)
                .textFieldStyle(.roundedBorder)
                .autocorrectionDisabled()
                .padding(.horizontal, 1)
        }
    }

    // MARK: - Description Section

    private var descriptionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Description", icon: "doc.text", color: .blue)

            TextEditor(text: $bodyText)
                .frame(minHeight: 120)
                .font(.body)
                .foregroundStyle(.white)
                .scrollContentBackground(.hidden)
                .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
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
    }

    // MARK: - Optional Fields Section

    private var optionalSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeader("Options", icon: "slider.horizontal.3", color: .green)

            VStack(spacing: 12) {
                // Reviewers
                optionalField(
                    label: "Reviewers",
                    placeholder: "username1, username2",
                    text: $reviewersInput,
                    icon: "person.2",
                    hint: "Comma-separated GitHub usernames"
                )

                // Labels
                optionalField(
                    label: "Labels",
                    placeholder: "bug, enhancement",
                    text: $labelsInput,
                    icon: "tag",
                    hint: "Comma-separated label names"
                )

                // Milestone
                optionalField(
                    label: "Milestone",
                    placeholder: "v1.0.0",
                    text: $milestone,
                    icon: "flag",
                    hint: "Milestone Title (Optional)"
                )

                // Draft toggle
                HStack {
                    Label("Draft PR", systemImage: "doc.badge.clock")
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                    Spacer()
                    Toggle("", isOn: $isDraft)
                        .labelsHidden()
                        .tint(.orange)
                }
                .padding(12)
                .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
            }
            .padding()
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        }
    }

    private func optionalField(label: String, placeholder: String, text: Binding<String>, icon: String, hint: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(label, systemImage: icon)
                .font(.caption.bold())
                .foregroundStyle(.secondary)
            TextField(placeholder, text: text)
                .textFieldStyle(.roundedBorder)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
            Text(hint)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: - Submit Section

    private var submitSection: some View {
        VStack(spacing: 12) {
            // Validation summary
            if !canSubmit {
                HStack(spacing: 8) {
                    Image(systemName: "info.circle")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                    Text(validationMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 4)
            }

            Button {
                Task { await submitPullRequest() }
            } label: {
                HStack {
                    if isSubmitting {
                        ProgressView().scaleEffect(0.9).tint(.white)
                    } else {
                        Image(systemName: isDraft ? "doc.badge.clock" : "arrow.triangle.pull")
                    }
                    Text(isDraft ? "Create Draft PR" : "Create Pull Request")
                        .font(.headline)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(canSubmit ? Color.purple : Color.secondary.opacity(0.3),
                            in: RoundedRectangle(cornerRadius: 12))
                .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
            .disabled(!canSubmit || isSubmitting)
        }
    }

    // MARK: - Success Sheet

    private var successSheet: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(.green)

                Text("Pull Request Created!")
                    .font(.title2.bold())
                    .foregroundStyle(.white)

                if let urlStr = createdPRURL, let url = URL(string: urlStr) {
                    Link(destination: url) {
                        Label("View On GitHub", systemImage: "safari")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(.orange, in: RoundedRectangle(cornerRadius: 12))
                            .foregroundStyle(.white)
                    }
                    .padding(.horizontal, 32)
                }

                Button("Done") {
                    showSuccessSheet = false
                    dismiss()
                }
                .foregroundStyle(.secondary)
            }
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(red: 0.08, green: 0.08, blue: 0.12).ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        showSuccessSheet = false
                        dismiss()
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Notification Banner

    private func prNotificationBanner(_ n: PRNotification) -> some View {
        HStack(spacing: 10) {
            Image(systemName: n.isError ? "xmark.circle.fill" : "checkmark.circle.fill")
                .foregroundStyle(n.isError ? .red : .green)
            Text(n.message)
                .font(.subheadline)
                .foregroundStyle(.white)
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

    // MARK: - Helper Views

    private func sectionHeader(_ title: String, icon: String, color: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(color)
            Text(title)
                .font(.headline)
                .foregroundStyle(.white)
        }
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
            // PLACEHOLDER: POST /repos/{owner}/{repo}/pulls
            // Returns the created PR object including its HTML URL.
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
