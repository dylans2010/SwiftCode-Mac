import SwiftUI
import UIKit

struct ModelDownloadProgressView: View {
    let modelName: String
    let modelLink: String?
    let metadata: OfflineModelMetadata?
    let onComplete: (() async -> Void)?

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var downloader = OfflineModelDownloader.shared
    @State private var errorMessage: String?
    @State private var hasStarted = false
    @State private var statusMessage = "Preparing Download…"
    @State private var didCopyError = false
    @State private var hasCompleted = false

    private var titleText: String {
        if let metadata {
            return metadata.modelName
        }
        return modelName
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(titleText)
                .font(.headline)
                .lineLimit(2)

            if let modelLink {
                Text(modelLink)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            ProgressView(value: max(downloader.downloadPercentage, downloader.isDownloading ? 0.01 : 0), total: 100)
                .progressViewStyle(.linear)

            Text(statusMessage)
                .font(.caption)
                .foregroundStyle(.secondary)

            if let errorMessage {
                VStack(alignment: .leading, spacing: 6) {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                        .font(.caption)
                        .textSelection(.enabled)

                    Button {
                        copyErrorMessage(errorMessage)
                    } label: {
                        Label(didCopyError ? "Copied" : "Copy Error", systemImage: didCopyError ? "checkmark" : "doc.on.doc")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                }
            }

            HStack {
                if downloader.isDownloading {
                    Button("Continue On Background") {
                        dismiss()
                    }
                    .buttonStyle(.bordered)
                }

                Spacer()
                if downloader.isDownloading {
                    Button("Cancel") {
                        downloader.cancelCurrentDownload()
                    }
                    .buttonStyle(.bordered)
                } else {
                    Button("Close") {
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .padding()
        .task {
            guard !hasStarted else { return }
            hasStarted = true
            await startDownloadIfNeeded()
        }
        .onChange(of: downloader.isDownloading) { _, isDownloading in
            guard !isDownloading, hasStarted, !hasCompleted else { return }

            if let latestError = downloader.lastErrorMessage {
                statusMessage = "Download Failed"
                errorMessage = latestError
                return
            }

            hasCompleted = true
            statusMessage = "Completed"
            Task {
                await onComplete?()
            }
        }
        .onChange(of: downloader.currentFileName) { _, newValue in
            if !newValue.isEmpty {
                statusMessage = "Downloading \(newValue)"
            }
        }
    }

    private func startDownloadIfNeeded() async {
        do {
            let selectedMetadata: OfflineModelMetadata
            if let metadata {
                selectedMetadata = metadata
            } else if let modelLink {
                selectedMetadata = try await OfflineModelManager.shared.fetchModelMetadataFromLink(modelLink)
            } else {
                throw OfflineModelError.invalidHuggingFaceURL
            }

            if downloader.isDownloading,
               downloader.activeModel?.modelName == selectedMetadata.modelName {
                statusMessage = "Download In Progress…"
                return
            }

            statusMessage = "Starting Download…"
            downloader.startDownload(model: selectedMetadata)
        } catch {
            statusMessage = "Download Failed"
            errorMessage = detailedErrorMessage(for: error)
        }
    }


    @MainActor
    private func copyErrorMessage(_ message: String) {
        UIPasteboard.general.string = message
        UINotificationFeedbackGenerator().notificationOccurred(.success)

        didCopyError = true
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            didCopyError = false
        }
    }
    private func detailedErrorMessage(for error: Error) -> String {
        let nsError = error as NSError

        if let offlineError = error as? OfflineModelError {
            return "\(offlineError.localizedDescription)\n\nFull error: \(nsError)"
        }

        if nsError.domain == NSCocoaErrorDomain, nsError.code == NSFileWriteNoPermissionError {
            return "Cannot write model files due to insufficient permissions in the selected folder. Full error: \(nsError)"
        }

        if nsError.domain == NSURLErrorDomain {
            return "Network download failed. Full error: \(nsError)"
        }

        return "Full Error: \(nsError)"
    }
}
