import SwiftUI

struct ModelLinkInstallGuideView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var manager = OfflineModelManager.shared

    @State private var repositoryLink = ""
    @State private var resolvedMetadata: OfflineModelMetadata?
    @State private var errorMessage: String?
    @State private var isLoadingMetadata = false
    @State private var pendingDownloadMetadata: OfflineModelMetadata?
    @State private var pendingDownloadLink: String?

    let onInstalled: () async -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Hugging Face repositories host open-source AI models that can run locally when a compatible file is available.")
                        .font(.callout)

                    Text("How to find a model")
                        .font(.headline)
                    Text("1. Open huggingface.co\n2. Choose a model repository\n3. Copy the repository URL")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Text("Example Link")
                        .font(.headline)
                    Text("https://huggingface.co/microsoft/phi-3-mini-4k-instruct")
                        .font(.footnote.monospaced())
                        .foregroundStyle(.secondary)

                    Divider()

                    Text("Paste HuggingFace Link")
                        .font(.headline)

                    TextField("https://huggingface.co/{author}/{model}", text: $repositoryLink)
                        .textInputAutocapitalization(.never)
#if canImport(UIKit)
                        .autocorrectionDisabled(true)
#endif
                        .textFieldStyle(.roundedBorder)

                    Button("Fetch Model Info") {
                        Task { await fetchMetadata() }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isLoadingMetadata || repositoryLink.isEmpty)

                    if let errorMessage {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                            .font(.caption)
                    }

                    if let metadata = resolvedMetadata {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(metadata.modelName)
                                .font(.headline)
                            Text(metadata.description)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text("Provider: \(metadata.providerName)")
                                .font(.caption)
                            Text("Compatible files: \(metadata.files.count)")
                                .font(.caption)
                            Text("Preferred: \(metadata.preferredDownloadFile?.fileName ?? "None")")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            Button("Download Model") {
                                startDownload(metadata)
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(manager.isModelInstalled(metadata.modelName))
                        }
                        .padding()
                        .background(Color.secondary.opacity(0.1))
                        .cornerRadius(12)
                    }
                }
                .padding()
            }
            .navigationTitle("Install Through Link")
            .sheet(item: $pendingDownloadMetadata) { metadata in
                ModelDownloadProgressView(
                    modelName: metadata.modelName,
                    modelLink: pendingDownloadLink,
                    metadata: metadata
                ) {
                    await onInstalled()
                    dismiss()
                }
                .presentationDetents([.height(280)])
                .presentationDragIndicator(.visible)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }

    private func fetchMetadata() async {
        errorMessage = nil
        resolvedMetadata = nil

        guard manager.validateRepositoryURL(repositoryLink) else {
            errorMessage = OfflineModelError.invalidHuggingFaceURL.localizedDescription
            return
        }

        isLoadingMetadata = true
        defer { isLoadingMetadata = false }

        do {
            let metadata = try await manager.fetchModelMetadataFromLink(repositoryLink)
            resolvedMetadata = metadata
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func startDownload(_ metadata: OfflineModelMetadata) {
        errorMessage = nil
        pendingDownloadLink = repositoryLink.trimmingCharacters(in: .whitespacesAndNewlines)
        pendingDownloadMetadata = metadata
    }
}
