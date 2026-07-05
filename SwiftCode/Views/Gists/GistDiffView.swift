import SwiftUI

struct GistDiffView: View {
    let gistId: String
    let revision: GistRevision
    @EnvironmentObject private var gistService: GitHubGistService
    @Environment(\.dismiss) private var dismiss

    @State private var diffFiles: [GistFile] = []
    @State private var isLoading = false
    @State private var diffStyle: DiffStyle = .unified
    @State private var selectedFileID: UUID?

    enum DiffStyle: String, CaseIterable, Identifiable {
        case unified = "Unified"
        case split = "Split"
        var id: String { self.rawValue }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(red: 0.10, green: 0.10, blue: 0.14).ignoresSafeArea()

                if isLoading {
                    ProgressView("Fetching diff...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if diffFiles.isEmpty {
                    Text("No differences found")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    VStack(spacing: 0) {
                        GistFileTabBar(
                            files: diffFiles,
                            selectedFileID: $selectedFileID,
                            isEditing: false,
                            onRemoveFile: { _ in }
                        )

                        if let selectedFileIndex = diffFiles.firstIndex(where: { $0.id == selectedFileID }) {
                            diffContent(file: diffFiles[selectedFileIndex])
                        } else {
                            Text("Select a file to view differences")
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                    }
                }
            }
            .navigationTitle("Diff (\(revision.version.prefix(7)))")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") { dismiss() }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Picker("Style", selection: $diffStyle) {
                        ForEach(DiffStyle.allCases) { style in
                            Text(style.rawValue).tag(style)
                        }
                    }
                    .pickerStyle(.segmented)
                }
            }
            .task {
                await loadDiff()
            }
        }
    }

    private func diffContent(file: GistFile) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 4) {
                if let patch = file.patch {
                    if diffStyle == .unified {
                        unifiedDiff(patch: patch)
                    } else {
                        splitDiff(patch: patch)
                    }
                } else {
                    Text("No patch available for this file")
                        .foregroundStyle(.secondary)
                        .padding()
                }
            }
            .padding(16)
        }
    }

    private func unifiedDiff(patch: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(patch.components(separatedBy: .newlines), id: \.self) { line in
                lineRow(line: line)
            }
        }
    }

    private func splitDiff(patch: String) -> some View {
        let lines = patch.components(separatedBy: .newlines)
        let leftLines = lines.filter { !$0.hasPrefix("+") }
        let rightLines = lines.filter { !$0.hasPrefix("-") }

        return HStack(alignment: .top, spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(leftLines, id: \.self) { line in
                    lineRow(line: line)
                }
            }
            Divider()
            VStack(alignment: .leading, spacing: 2) {
                ForEach(rightLines, id: \.self) { line in
                    lineRow(line: line)
                }
            }
        }
    }

    private func lineRow(line: String) -> some View {
        Text(line)
            .font(.system(size: 13, design: .monospaced))
            .foregroundStyle(lineColor(line))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 4)
            .background(lineBackgroundColor(line))
    }

    private func lineColor(_ line: String) -> Color {
        if line.hasPrefix("+") { return .green }
        if line.hasPrefix("-") { return .red }
        return .white
    }

    private func lineBackgroundColor(_ line: String) -> Color {
        if line.hasPrefix("+") { return Color.green.opacity(0.1) }
        if line.hasPrefix("-") { return Color.red.opacity(0.1) }
        return .clear
    }

    private func loadDiff() async {
        isLoading = true
        do {
            let fetchedGist = try await gistService.fetchGistAtRevision(gistId: gistId, sha: revision.version)
            diffFiles = fetchedGist.files.values.sorted { $0.filename < $1.filename }
            selectedFileID = diffFiles.first?.id
        } catch {
            print("Failed to load diff: \(error)")
        }
        isLoading = false
    }
}
