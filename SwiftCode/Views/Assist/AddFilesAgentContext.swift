import SwiftUI
import AppKit

public struct PendingFile: Identifiable {
    public let id: UUID = UUID()
    public let url: URL
    public var filename: String { url.lastPathComponent }
    public var status: Status

    public enum Status: Equatable {
        case queued
        case processing
        case completed(AgentFileContext)
        case failed(String)
    }
}

@MainActor
public struct AddFilesAgentContext: View {
    @Environment(\.dismiss) private var dismiss

    @Binding public var attachedFiles: [AgentFileContext]
    @Binding public var isProcessingFiles: Bool

    @State private var pendingFiles: [PendingFile] = []

    public init(attachedFiles: Binding<[AgentFileContext]>, isProcessingFiles: Binding<Bool>) {
        self._attachedFiles = attachedFiles
        self._isProcessingFiles = isProcessingFiles
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Label("Attach Files to Context", systemImage: "paperclip")
                    .font(.headline)
                    .foregroundColor(.orange)
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .disabled(isProcessingFiles)
            }
            .padding()
            .background(.thinMaterial)

            Divider()

            // Files List / Empty State
            ScrollView {
                VStack(spacing: 12) {
                    if pendingFiles.isEmpty && attachedFiles.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "doc.on.doc.fill")
                                .font(.system(size: 48))
                                .foregroundColor(.orange.opacity(0.4))
                                .padding(.top, 40)

                            Text("No files attached yet")
                                .font(.headline)

                            Text("Select source code, markdown documents, configuration files, images, or PDFs to feed directly into the agent's context.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 24)

                            Button {
                                selectFilesViaPicker()
                            } label: {
                                Label("Select Files...", systemImage: "plus")
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.orange)
                            .controlSize(.large)
                            .padding(.top, 12)
                        }
                    } else {
                        // Display combined list of existing attached files and new pending files
                        VStack(alignment: .leading, spacing: 8) {
                            Text("ATTACHED CONTEXT FILES")
                                .font(.caption2.bold())
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 4)

                            // Existing attached files
                            ForEach(attachedFiles) { file in
                                HStack {
                                    Image(systemName: "doc.fill")
                                        .foregroundColor(.orange)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(file.filename)
                                            .font(.subheadline.bold())
                                        Text("\(file.mimeType) • \(ByteCountFormatter.string(fromByteCount: file.size, countStyle: .file))")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()

                                    Text("Ready")
                                        .font(.caption2.bold())
                                        .foregroundColor(.green)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.green.opacity(0.12), in: Capsule())

                                    Button {
                                        attachedFiles.removeAll { $0.id == file.id }
                                    } label: {
                                        Image(systemName: "trash")
                                            .foregroundColor(.red)
                                    }
                                    .buttonStyle(.plain)
                                }
                                .padding(10)
                                .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                            }

                            // New Pending/processing files
                            ForEach(pendingFiles) { pending in
                                HStack {
                                    Image(systemName: "doc.badge.gearshape.fill")
                                        .foregroundColor(.blue)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(pending.filename)
                                            .font(.subheadline.bold())

                                        switch pending.status {
                                        case .queued:
                                            Text("Queued")
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                        case .processing:
                                            Text("Processing base64 context...")
                                                .font(.caption2)
                                                .foregroundColor(.orange)
                                        case .completed(let file):
                                            Text("\(file.mimeType) • \(ByteCountFormatter.string(fromByteCount: file.size, countStyle: .file))")
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                        case .failed(let error):
                                            Text(error)
                                                .font(.caption2)
                                                .foregroundColor(.red)
                                        }
                                    }
                                    Spacer()

                                    switch pending.status {
                                    case .queued:
                                        Image(systemName: "ellipsis")
                                            .foregroundColor(.secondary)
                                    case .processing:
                                        ProgressView()
                                            .scaleEffect(0.6)
                                    case .completed:
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundColor(.green)
                                    case .failed:
                                        Image(systemName: "exclamationmark.circle.fill")
                                            .foregroundColor(.red)
                                    }

                                    Button {
                                        pendingFiles.removeAll { $0.id == pending.id }
                                    } label: {
                                        Image(systemName: "xmark")
                                    }
                                    .buttonStyle(.plain)
                                    .disabled(pending.status == .processing)
                                }
                                .padding(10)
                                .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                            }
                        }
                        .padding()
                    }
                }
            }
            .frame(maxHeight: 320)

            Divider()

            // Footer
            HStack {
                if !pendingFiles.isEmpty || !attachedFiles.isEmpty {
                    Button {
                        selectFilesViaPicker()
                    } label: {
                        Label("Add More...", systemImage: "plus")
                    }
                    .buttonStyle(.bordered)
                    .disabled(isProcessingFiles)
                }

                Spacer()

                Button("Done") {
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
                .disabled(isProcessingFiles)
            }
            .padding()
            .background(.thinMaterial)
        }
        .frame(width: 440)
    }

    private func selectFilesViaPicker() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.title = "Select Source, Documents, or Images"
        panel.message = "Choose files to decode and insert as AI context."

        if panel.runModal() == .OK {
            let urls = panel.urls
            let newPending = urls.map { PendingFile(url: $0, status: .queued) }
            self.pendingFiles.append(contentsOf: newPending)

            // Process queue immediately
            Task {
                await processPendingQueue()
            }
        }
    }

    private func processPendingQueue() async {
        isProcessingFiles = true
        defer {
            isProcessingFiles = false
            // Clean up completed from pending list so they are not double-displayed
            pendingFiles.removeAll {
                if case .completed = $0.status { return true }
                return false
            }
        }

        for index in 0..<pendingFiles.count {
            guard pendingFiles[index].status == .queued else { continue }
            pendingFiles[index].status = .processing

            let url = pendingFiles[index].url
            do {
                let context = try await FileAgentHelper.processFile(at: url)
                pendingFiles[index].status = .completed(context)
                attachedFiles.append(context)
            } catch {
                pendingFiles[index].status = .failed(error.localizedDescription)
            }
        }
    }
}
