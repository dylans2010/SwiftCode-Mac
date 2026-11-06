import SwiftCodeIDECore
import SwiftUI

/// Ported from SwiftCode-Legacy `SwiftCode/Views/GitHub/TagsView.swift`
/// (Dylan's own code; direct port authorised under MIT).
///
/// Tags list for the repository, with a create-tag sheet (name + annotation
/// message) and delete. Legacy drove this through `Project` +
/// `AppSettings.gitPath` + `ProcessRunnerTool`; this port takes the
/// `GitRepository` directly and runs real git operations:
///
/// - List/refresh → `GitRepository.tags()`
/// - Create → `GitRepository.createTag(name:message:)` (annotated when a
///   message is given, lightweight otherwise)
/// - Delete → `GitRepository.deleteTag(_:)` (local tag; pushing the deletion
///   is a remote operation and is intentionally not done here)
///
/// Hook: present from the source-control navigator's Tags group (a Tags
/// group already exists in `SourceControlNavigatorModel`); the navigator
/// can pass its repository through.
@MainActor
public struct TagsView: View {
    public var repository: GitRepository

    @State private var tags: [String] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showCreateSheet = false
    @State private var newTagName = ""
    @State private var newTagMessage = ""
    @State private var tagPendingDelete: String?

    public init(repository: GitRepository) {
        self.repository = repository
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Label("Tags", systemImage: "tag")
                    .font(.headline)
                Spacer()
                Button {
                    Task { await loadTags() }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(isLoading)
                Button("New Tag…") { showCreateSheet = true }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            }
            .padding()

            if isLoading {
                ProgressView("Loading tags…")
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding()
            } else if tags.isEmpty {
                ContentUnavailableView(
                    "No Tags",
                    systemImage: "tag",
                    description: Text("This repository has no tags yet.")
                )
            } else {
                List(tags, id: \.self) { tag in
                    HStack {
                        Image(systemName: "tag.fill")
                            .foregroundStyle(.secondary)
                        Text(tag)
                            .font(.system(.body, design: .monospaced))
                        Spacer()
                        Button("Delete", role: .destructive) {
                            tagPendingDelete = tag
                        }
                        .buttonStyle(.borderless)
                        .controlSize(.small)
                    }
                }
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.subheadline)
                    .foregroundStyle(.red)
                    .padding()
            }
        }
        .task { await loadTags() }
        .sheet(isPresented: $showCreateSheet) {
            createTagSheet
        }
        .alert("Delete tag?", isPresented: Binding(
            get: { tagPendingDelete != nil },
            set: { if !$0 { tagPendingDelete = nil } }
        )) {
            Button("Delete", role: .destructive) {
                if let tag = tagPendingDelete {
                    Task { await deleteTag(tag) }
                }
            }
            Button("Cancel", role: .cancel) { tagPendingDelete = nil }
        } message: {
            Text("This deletes the local tag \(tagPendingDelete ?? ""). It does not delete the tag on any remote.")
        }
    }

    private var createTagSheet: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("New Tag")
                .font(.headline)
            TextField("Tag name (e.g. v1.2.0)", text: $newTagName)
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))
            TextField("Annotation message (optional — empty makes a lightweight tag)", text: $newTagMessage)
                .textFieldStyle(.roundedBorder)
            HStack {
                Spacer()
                Button("Cancel") { showCreateSheet = false }
                    .buttonStyle(.bordered)
                Button("Create Tag") {
                    Task { await createTag() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(newTagName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 400)
    }

    private func loadTags() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            tags = try await Task.detached {
                try self.repository.tags().map(\.name)
            }.value.sorted()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func createTag() async {
        let name = newTagName.trimmingCharacters(in: .whitespaces)
        let message = newTagMessage.trimmingCharacters(in: .whitespaces)
        do {
            try await Task.detached {
                try self.repository.createTag(name, message: message.isEmpty ? nil : message)
            }.value
            newTagName = ""
            newTagMessage = ""
            showCreateSheet = false
            await loadTags()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func deleteTag(_ tag: String) async {
        tagPendingDelete = nil
        do {
            try await Task.detached {
                try self.repository.deleteTag(tag)
            }.value
            await loadTags()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
