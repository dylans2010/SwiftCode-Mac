import SwiftUI

@MainActor
struct TagsView: View {
    let project: Project?
    @Binding var showSuccess: Bool
    @Binding var successMessage: String?
    @Binding var showError: Bool
    @Binding var errorMessage: String?

    @State private var tags: [String] = []
    @State private var isFetching = false
    @State private var newTagName = ""
    @State private var newTagMessage = ""
    @State private var showCreateTag = false

    var body: some View {
        VStack(spacing: 0) {
            // Header actions row
            HStack(spacing: 12) {
                Label("Repository Tags", systemImage: "tag.fill")
                    .font(.headline)
                    .foregroundStyle(.purple)

                Spacer()

                Button {
                    fetchTags()
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .disabled(isFetching)

                Button {
                    showCreateTag = true
                } label: {
                    Label("New Tag", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
                .tint(.purple)
            }
            .padding()
            .background(Color.secondary.opacity(0.03))

            Divider()

            if isFetching {
                GitHubLoadingView(message: "Loading tags...")
            } else if tags.isEmpty {
                GitHubEmptyStateView(
                    title: "No Tags Found",
                    description: "No Git tags have been recorded in this repository. Add a tag to mark release milestones.",
                    systemImage: "tag",
                    accentColor: .purple,
                    actionTitle: "Create First Tag"
                ) {
                    showCreateTag = true
                }
            } else {
                List(tags, id: \.self) { tag in
                    HStack(spacing: 16) {
                        Image(systemName: "tag.fill")
                            .foregroundStyle(.purple)
                            .font(.title3)

                        VStack(alignment: .leading, spacing: 4) {
                            Text(tag)
                                .font(.subheadline.bold())
                                .foregroundStyle(.primary)
                            Text("Git Release Tag")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()
                    }
                    .padding(.vertical, 6)
                }
            }
        }
        .onAppear {
            fetchTags()
        }
        .sheet(isPresented: $showCreateTag) {
            createTagSheet
        }
    }

    private var createTagSheet: some View {
        VStack(spacing: 20) {
            HStack {
                Label("New Tag", systemImage: "tag.fill")
                    .font(.headline)
                    .foregroundStyle(.purple)
                Spacer()
                Button("Cancel") {
                    showCreateTag = false
                }
                .buttonStyle(.bordered)
            }

            VStack(alignment: .leading, spacing: 14) {
                TextField("Tag Name (e.g. v1.0.0)", text: $newTagName)
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled()

                TextField("Annotation Message (Optional)", text: $newTagMessage)
                    .textFieldStyle(.roundedBorder)
            }
            .padding()

            Button {
                submitTag()
            } label: {
                Text("Create Tag")
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.purple)
            .disabled(newTagName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(24)
        .frame(width: 400)
    }

    private func fetchTags() {
        guard let project = project else { return }

        isFetching = true
        Task {
            do {
                let gitBinary = URL(fileURLWithPath: AppSettings.shared.gitPath.isEmpty ? "/usr/bin/git" : AppSettings.shared.gitPath)
                let result = try await ProcessRunnerTool.shared.run(
                    executableURL: gitBinary,
                    arguments: ["tag"],
                    workingDirectory: project.directoryURL
                )
                if result.exitCode == 0 {
                    let tagLines = result.stdout
                        .split(separator: "\n")
                        .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
                        .filter { !$0.isEmpty }
                    self.tags = tagLines
                }
            } catch {
                // Ignore silent catch
            }
            isFetching = false
        }
    }

    private func submitTag() {
        guard let project = project else { return }

        Task {
            do {
                let gitBinary = URL(fileURLWithPath: AppSettings.shared.gitPath.isEmpty ? "/usr/bin/git" : AppSettings.shared.gitPath)
                var args = ["tag", newTagName.trimmingCharacters(in: .whitespacesAndNewlines)]
                if !newTagMessage.isEmpty {
                    args.append(contentsOf: ["-m", newTagMessage])
                }

                let result = try await ProcessRunnerTool.shared.run(
                    executableURL: gitBinary,
                    arguments: args,
                    workingDirectory: project.directoryURL
                )

                if result.exitCode == 0 {
                    successMessage = "Tag \(newTagName) created successfully."
                    showSuccess = true
                    newTagName = ""
                    newTagMessage = ""
                    showCreateTag = false
                    fetchTags()
                } else {
                    errorMessage = "Failed to create tag: \(result.stderr)"
                    showError = true
                }
            } catch {
                errorMessage = "Failed to run tag command: \(error.localizedDescription)"
                showError = true
            }
        }
    }
}
