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
                VStack(alignment: .leading, spacing: 20) {
                    // Header Card
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Hugging Face repositories host open-source AI models that can run locally when a compatible file is available.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.blue.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))

                    // How to find a model
                    VStack(alignment: .leading, spacing: 12) {
                        Label("How to find a model", systemImage: "sparkles")
                            .font(.headline)
                            .foregroundStyle(.orange)

                        VStack(alignment: .leading, spacing: 6) {
                            Text("1. Open huggingface.co")
                            Text("2. Choose a model repository")
                            Text("3. Copy the repository URL")
                        }
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.leading, 4)

                        Divider()
                            .padding(.vertical, 4)

                        Text("Example Link")
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)
                        Text("https://huggingface.co/microsoft/phi-3-mini-4k-instruct")
                            .font(.footnote.monospaced())
                            .foregroundStyle(.blue)
                            .padding(8)
                            .background(Color.black.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
                    }
                    .padding()
                    .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
                    .cornerRadius(12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.secondary.opacity(0.12), lineWidth: 1)
                    )

                    // Input Form Card
                    VStack(alignment: .leading, spacing: 14) {
                        Label("Paste HuggingFace Link", systemImage: "link")
                            .font(.headline)
                            .foregroundStyle(.blue)

                        TextField("https://huggingface.co/{author}/{model}", text: $repositoryLink)
                            .textFieldStyle(.roundedBorder)
                            .controlSize(.large)

                        Button {
                            Task { await fetchMetadata() }
                        } label: {
                            HStack {
                                if isLoadingMetadata {
                                    ProgressView().scaleEffect(0.6).padding(.trailing, 4)
                                } else {
                                    Image(systemName: "magnifyingglass")
                                }
                                Text("Fetch Model Info")
                                    .fontWeight(.bold)
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .disabled(isLoadingMetadata || repositoryLink.isEmpty)
                    }
                    .padding()
                    .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
                    .cornerRadius(12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.secondary.opacity(0.12), lineWidth: 1)
                    )

                    if let errorMessage {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.red)
                            Text(errorMessage)
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                    }

                    if let metadata = resolvedMetadata {
                        VStack(alignment: .leading, spacing: 12) {
                            Text(metadata.modelName)
                                .font(.title3.bold())
                                .foregroundStyle(.primary)

                            Text(metadata.description)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(3)

                            Divider()

                            HStack {
                                Label("Provider: \(metadata.providerName)", systemImage: "person.circle")
                                Spacer()
                                Label("Files: \(metadata.files.count)", systemImage: "doc.on.doc")
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)

                            HStack {
                                Label("Preferred File: \(metadata.preferredDownloadFile?.fileName ?? "None")", systemImage: "doc.text.fill")
                                    .font(.caption.monospaced())
                                    .foregroundStyle(.secondary)
                                Spacer()
                            }

                            Button {
                                startDownload(metadata)
                            } label: {
                                HStack {
                                    Image(systemName: "arrow.down.circle.fill")
                                    Text("Download Model")
                                        .fontWeight(.bold)
                                }
                                .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.large)
                            .disabled(manager.isModelInstalled(metadata.modelName))
                        }
                        .padding()
                        .background(Color.green.opacity(0.06))
                        .cornerRadius(12)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.green.opacity(0.2), lineWidth: 1)
                        )
                    }
                }
                .padding(24)
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
