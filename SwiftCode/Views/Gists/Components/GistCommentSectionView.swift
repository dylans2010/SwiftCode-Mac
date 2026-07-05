import SwiftUI

struct GistCommentSectionView: View {
    let gistId: String
    @EnvironmentObject private var gistService: GitHubGistService
    @State private var comments: [GistComment] = []
    @State private var newCommentBody = ""
    @State private var isLoading = false
    @State private var showAttachmentPicker = false

    var body: some View {
        VStack(spacing: 0) {
            if isLoading && comments.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if comments.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "bubble.left.and.bubble.right")
                        .font(.system(size: 40))
                        .foregroundStyle(.tertiary)
                    Text("No comments yet")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(comments) { comment in
                        commentRow(comment)
                            .listRowBackground(Color.clear)
                            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }

            Divider()

            VStack(spacing: 0) {
                MarkdownToolbar(
                    text: $newCommentBody,
                    onAttachFile: { showAttachmentPicker = true },
                    onMention: { newCommentBody += "@" }
                )

                HStack(alignment: .bottom, spacing: 12) {
                    TextEditor(text: $newCommentBody)
                        .font(.subheadline)
                        .frame(minHeight: 40, maxHeight: 120)
                        .padding(8)
                        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))
                        .scrollContentBackground(.hidden)

                    Button {
                        Task { await postComment() }
                    } label: {
                        Image(systemName: "paperplane.fill")
                            .font(.system(size: 18))
                            .foregroundStyle(.white)
                            .frame(width: 44, height: 44)
                            .background(Color.blue, in: Circle())
                    }
                    .disabled(newCommentBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .padding()
                .background(Color(red: 0.12, green: 0.12, blue: 0.16))
            }
        }
        .background(Color(red: 0.10, green: 0.10, blue: 0.14))
        .overlay {
            if showAttachmentPicker {
                FileImporterRepresentableView(
                    allowedContentTypes: [.item],
                    allowsMultipleSelection: true
                ) { urls in
                    showAttachmentPicker = false
                    for url in urls {
                        newCommentBody += "\n[Attached file: \(url.lastPathComponent)]"
                    }
                }
                .ignoresSafeArea()
            }
        }
        .task {
            await loadComments()
        }
    }

    private func commentRow(_ comment: GistComment) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                if let avatar = comment.user?.avatarUrl, let url = URL(string: avatar) {
                    AsyncImage(url: url) { image in
                        image.resizable()
                    } placeholder: {
                        Color.gray
                    }
                    .frame(width: 24, height: 24)
                    .clipShape(Circle())
                }

                Text(comment.user?.login ?? "anonymous")
                    .font(.caption.bold())
                    .foregroundStyle(.white)

                Text(comment.createdAt, style: .relative)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Text(comment.body)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.leading, 32)
        }
        .padding(.vertical, 8)
    }

    private func loadComments() async {
        isLoading = true
        do {
            comments = try await gistService.fetchComments(gistId: gistId)
        } catch {
            print("Failed to load comments: \(error)")
        }
        isLoading = false
    }

    private func postComment() async {
        guard !newCommentBody.isEmpty else { return }
        let body = newCommentBody
        newCommentBody = ""
        do {
            let newComment = try await gistService.createComment(gistId: gistId, body: body)
            comments.append(newComment)
        } catch {
            print("Failed to post comment: \(error)")
            newCommentBody = body
        }
    }
}
