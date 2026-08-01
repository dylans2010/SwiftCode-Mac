import SwiftUI

struct GistDiffView: View {
    let gistId: String
    let revision: GistRevision
    @EnvironmentObject private var gistService: GitHubGistService
    @Environment(\.dismiss) private var dismiss

    @State private var diffFiles: [GistFile] = []
    @State private var isLoading = false
    @State private var diffStyle: DiffStyle = .unified
    @State private var selectedFileIndex: Int = 0

    enum DiffStyle: String, CaseIterable, Identifiable {
        case unified = "Unified"
        case split = "Split"
        var id: String { self.rawValue }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Header Card
                    GroupBox {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Label("Diff Viewer", systemImage: "arrow.left.and.right.square.fill")
                                    .font(.headline)
                                    .foregroundColor(.orange)
                                Spacer()
                            }
                            Text("Revision: \(revision.version.prefix(7))")
                                .font(.system(.body, design: .monospaced))
                                .bold()

                            if let author = revision.user?.login {
                                Text("Committed by \(author) on \(revision.committedAt, style: .date)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(8)
                    }
                    .groupBoxStyle(ModernGroupBoxStyle())

                    if isLoading {
                        GroupBox {
                            HStack {
                                Spacer()
                                ProgressView("Loading Diffs...")
                                    .padding()
                                Spacer()
                            }
                        }
                        .groupBoxStyle(ModernGroupBoxStyle())
                    } else if diffFiles.isEmpty {
                        GroupBox {
                            ContentUnavailableView("No Diffs Found", systemImage: "doc.text")
                                .padding()
                        }
                        .groupBoxStyle(ModernGroupBoxStyle())
                    } else {
                        // File Selection Card (if more than 1 file)
                        if diffFiles.count > 1 {
                            GroupBox {
                                VStack(alignment: .leading, spacing: 12) {
                                    Label("Select File to View", systemImage: "doc.text")
                                        .font(.subheadline.bold())
                                        .foregroundColor(.blue)

                                    Picker("Files", selection: $selectedFileIndex) {
                                        ForEach(0..<diffFiles.count, id: \.self) { index in
                                            Text(diffFiles[index].filename).tag(index)
                                        }
                                    }
                                    .pickerStyle(.menu)
                                }
                                .padding(8)
                            }
                            .groupBoxStyle(ModernGroupBoxStyle())
                        }

                        // Diff Content Card
                        GroupBox {
                            VStack(alignment: .leading, spacing: 14) {
                                let indexToUse = min(selectedFileIndex, diffFiles.count - 1)
                                if indexToUse >= 0 {
                                    let selectedFile = diffFiles[indexToUse]
                                    HStack {
                                        Label(selectedFile.filename, systemImage: "doc.text.fill")
                                            .font(.headline)
                                            .foregroundColor(.green)
                                        Spacer()
                                        if let size = selectedFile.size {
                                            Text("\(size) bytes")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                    }

                                    if let patch = selectedFile.patch, !patch.isEmpty {
                                        ScrollView(.horizontal) {
                                            Text(patch)
                                                .font(.system(.body, design: .monospaced))
                                                .textSelection(.enabled)
                                                .lineSpacing(4)
                                                .padding()
                                                .background(Color.black.opacity(0.15))
                                                .cornerRadius(8)
                                        }
                                    } else {
                                        ScrollView(.horizontal) {
                                            Text(selectedFile.content.isEmpty ? "No content changes or binary file." : selectedFile.content)
                                                .font(.system(.body, design: .monospaced))
                                                .textSelection(.enabled)
                                                .lineSpacing(4)
                                                .padding()
                                                .background(Color.black.opacity(0.15))
                                                .cornerRadius(8)
                                        }
                                    }
                                }
                            }
                            .padding(8)
                        }
                        .groupBoxStyle(ModernGroupBoxStyle())
                    }
                }
                .padding(24)
            }
            .navigationTitle("Diff (\(revision.version.prefix(7)))")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .primaryAction) {
                    Picker("Style", selection: $diffStyle) {
                        ForEach(DiffStyle.allCases) { style in
                            Text(style.rawValue).tag(style)
                        }
                    }
                    .pickerStyle(.segmented)
                }
            }
        }
        .frame(width: 700, height: 650)
        .task {
            await loadDiff()
        }
    }

    private func loadDiff() async {
        isLoading = true
        do {
            let fetched = try await gistService.fetchGistAtRevision(gistId: gistId, sha: revision.version)
            diffFiles = fetched.files.values.sorted { $0.filename < $1.filename }
            selectedFileIndex = 0
        } catch {
            print("Failed to load diff: \(error)")
        }
        isLoading = false
    }
}
