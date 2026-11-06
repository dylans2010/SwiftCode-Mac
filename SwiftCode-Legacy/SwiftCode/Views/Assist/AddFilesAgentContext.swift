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
    @State private var hoveredFileID: UUID? = nil

    public init(attachedFiles: Binding<[AgentFileContext]>, isProcessingFiles: Binding<Bool>) {
        self._attachedFiles = attachedFiles
        self._isProcessingFiles = isProcessingFiles
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Elegant Native Header
            HStack(spacing: 12) {
                Image(systemName: "paperclip.circle.fill")
                    .font(.title2)
                    .foregroundColor(.orange)
                    .shadow(color: .orange.opacity(0.3), radius: 4)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Context Attachments")
                        .font(.headline)
                        .foregroundColor(.primary)
                    Text("Feed source files directly into the AI's short-term memory")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.secondary)
                        .padding(5)
                        .background(Color.secondary.opacity(0.12), in: Circle())
                }
                .buttonStyle(.plain)
                .disabled(isProcessingFiles)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .background(.thinMaterial)

            Divider()

            // Main Content Area
            ScrollView {
                VStack(spacing: 16) {
                    if pendingFiles.isEmpty && attachedFiles.isEmpty {
                        // Breathtaking Empty State Redesign
                        VStack(spacing: 16) {
                            ZStack {
                                Circle()
                                    .fill(Color.orange.opacity(0.08))
                                    .frame(width: 80, height: 80)

                                Image(systemName: "doc.on.doc.fill")
                                    .font(.system(size: 36))
                                    .foregroundColor(.orange)
                                    .shadow(color: .orange.opacity(0.4), radius: 6)
                            }
                            .padding(.top, 40)

                            VStack(spacing: 6) {
                                Text("No attachments yet")
                                    .font(.headline)
                                    .foregroundColor(.primary)

                                Text("Select Swift files, documentation, JSON assets, or config files to equip the agent with relevant local code context.")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal, 32)
                                    .lineSpacing(4)
                            }

                            Button {
                                selectFilesViaPicker()
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "plus")
                                        .font(.system(size: 12, weight: .bold))
                                    Text("Add Files...")
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.orange)
                            .controlSize(.large)
                            .padding(.top, 12)
                            .padding(.bottom, 40)
                        }
                    } else {
                        // High-Fidelity Desktop Card List
                        VStack(alignment: .leading, spacing: 12) {
                            Text("ATTACHED CONTEXT FILES (\(attachedFiles.count + pendingFiles.count))")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.secondary)
                                .padding(.horizontal, 4)

                            // Existing attached files card
                            ForEach(attachedFiles) { file in
                                HStack(spacing: 12) {
                                    // Custom high-fidelity extension-aware icons
                                    ZStack {
                                        RoundedRectangle(cornerRadius: 8)
                                            .fill(iconColor(for: file.extension).opacity(0.12))
                                            .frame(width: 38, height: 38)

                                        Image(systemName: iconName(for: file.extension))
                                            .font(.system(size: 18))
                                            .foregroundColor(iconColor(for: file.extension))
                                    }

                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(file.filename)
                                            .font(.subheadline.bold())
                                            .foregroundColor(.primary)
                                        Text("\(file.mimeType.uppercased()) • \(ByteCountFormatter.string(fromByteCount: file.size, countStyle: .file))")
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                    }

                                    Spacer()

                                    // Interactive Status Chip
                                    HStack(spacing: 4) {
                                        Circle()
                                            .fill(Color.green)
                                            .frame(width: 5, height: 5)
                                        Text("Active Context")
                                            .font(.system(size: 9, weight: .bold))
                                            .foregroundColor(.green)
                                    }
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.green.opacity(0.08), in: Capsule())

                                    Button {
                                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                            attachedFiles.removeAll { $0.id == file.id }
                                        }
                                    } label: {
                                        Image(systemName: "trash")
                                            .foregroundColor(.red.opacity(hoveredFileID == file.id ? 1.0 : 0.6))
                                            .font(.body)
                                    }
                                    .buttonStyle(.plain)
                                    .onHover { isHovered in
                                        hoveredFileID = isHovered ? file.id : nil
                                    }
                                    .help("Remove file from context")
                                }
                                .padding(10)
                                .background(Color.secondary.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10)
                                        .stroke(Color.secondary.opacity(0.08), lineWidth: 1)
                                )
                                .transition(.scale.combined(with: .opacity))
                            }

                            // Processing / pending files card
                            ForEach(pendingFiles) { pending in
                                HStack(spacing: 12) {
                                    ZStack {
                                        RoundedRectangle(cornerRadius: 8)
                                            .fill(Color.blue.opacity(0.12))
                                            .frame(width: 38, height: 38)

                                        Image(systemName: "doc.badge.gearshape.fill")
                                            .font(.system(size: 18))
                                            .foregroundColor(.blue)
                                    }

                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(pending.filename)
                                            .font(.subheadline.bold())
                                            .foregroundColor(.primary)

                                        switch pending.status {
                                        case .queued:
                                            Text("Queued in processing pipeline...")
                                                .font(.caption2)
                                                .foregroundColor(.secondary)
                                        case .processing:
                                            Text("Computing Base64 payload & chunking...")
                                                .font(.caption2)
                                                .foregroundColor(.orange)
                                        case .completed(let file):
                                            Text("\(file.mimeType) • \(ByteCountFormatter.string(fromByteCount: file.size, countStyle: .file))")
                                                .font(.caption2)
                                                .foregroundColor(.secondary)
                                        case .failed(let error):
                                            Text(error)
                                                .font(.caption2)
                                                .foregroundColor(.red)
                                        }
                                    }

                                    Spacer()

                                    // Dynamic Progress / Error Badges
                                    switch pending.status {
                                    case .queued:
                                        Text("Queued")
                                            .font(.system(size: 9, weight: .bold))
                                            .foregroundColor(.secondary)
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 4)
                                            .background(Color.secondary.opacity(0.12), in: Capsule())
                                    case .processing:
                                        HStack(spacing: 6) {
                                            ProgressView()
                                                .scaleEffect(0.5)
                                                .tint(.orange)
                                            Text("Encoding")
                                                .font(.system(size: 9, weight: .bold))
                                                .foregroundColor(.orange)
                                        }
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(Color.orange.opacity(0.08), in: Capsule())
                                    case .completed:
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundColor(.green)
                                    case .failed:
                                        Text("Failed")
                                            .font(.system(size: 9, weight: .bold))
                                            .foregroundColor(.red)
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 4)
                                            .background(Color.red.opacity(0.08), in: Capsule())
                                    }

                                    Button {
                                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                            pendingFiles.removeAll { $0.id == pending.id }
                                        }
                                    } label: {
                                        Image(systemName: "xmark.circle")
                                            .foregroundColor(.secondary)
                                    }
                                    .buttonStyle(.plain)
                                    .disabled(pending.status == .processing)
                                }
                                .padding(10)
                                .background(Color.secondary.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10)
                                        .stroke(Color.secondary.opacity(0.08), lineWidth: 1)
                                )
                                .transition(.scale.combined(with: .opacity))
                            }
                        }
                        .padding(20)
                    }
                }
            }
            .frame(maxHeight: 380)

            Divider()

            // Footer Bar
            HStack(spacing: 12) {
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
                .controlSize(.large)
                .disabled(isProcessingFiles)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .background(.thinMaterial)
        }
        .frame(width: 480)
        .animation(.spring(response: 0.35, dampingFraction: 0.82), value: pendingFiles.count)
        .animation(.spring(response: 0.35, dampingFraction: 0.82), value: attachedFiles.count)
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
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                self.pendingFiles.append(contentsOf: newPending)
            }

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
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                pendingFiles.removeAll {
                    if case .completed = $0.status { return true }
                    return false
                }
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

    private func iconName(for ext: String) -> String {
        switch ext.lowercased() {
        case "swift": return "swift"
        case "md", "txt": return "doc.text.fill"
        case "json", "plist", "xml": return "doc.badge.gearshape.fill"
        case "pdf": return "doc.richtext.fill"
        case "png", "jpg", "jpeg", "gif", "webp": return "photo.fill"
        default: return "doc.fill"
        }
    }

    private func iconColor(for ext: String) -> Color {
        switch ext.lowercased() {
        case "swift": return .orange
        case "md", "txt": return .blue
        case "json", "plist", "xml": return .purple
        case "pdf": return .red
        case "png", "jpg", "jpeg", "gif", "webp": return .green
        default: return .secondary
        }
    }
}
