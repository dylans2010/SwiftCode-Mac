import SwiftCodeIDECore
import SwiftUI

/// Ported from SwiftCode-Legacy `SwiftCode/Views/GitHub/SourceControlView.swift`
/// (Dylan's own code; direct port authorised under MIT).
///
/// The two SwiftUI pieces of the standalone source-control workspace:
///
/// - `ConflictResolverWorkspaceView`: lists the working tree's conflicted
///   files and routes each one to the conflict resolver. Legacy drove this
///   through `GitViewModel` + `GitConflictResolverView`; this port reads
///   `GitRepository.status()` (files with `.conflicted`) and hands the
///   chosen file to `onResolveFile`, which the host wires to the
///   destination's conflict editor (`ConflictEditorController` /
///   `ConflictEditorShellModel` — AppKit, already in the destination).
/// - `UnifiedDiffView`: the working tree's unified diff. Legacy rendered
///   `GitDiffHunk`s from `GitViewModel.getDiff()` through a legacy
///   `GitDiffView`; this port loads `[DiffHunk]` from the staged
///   `GitRepository.diffHunks()` (Group A) and renders them inline with
///   +/- colouring (the destination has no `GitDiffView`).
///
/// The AppKit window shell (`SourceControlWindowController` /
/// `SourceControlWindowManager` in Legacy) is NOT ported here: the
/// destination's source control lives in the workspace window's navigator.
/// Hook: to restore a separate window, host `SourceControlNavigator` in
/// its own window via `WorkspaceWindowController` and embed these views
/// in it; until then they are usable as panes in the navigator.
@MainActor
public struct ConflictResolverWorkspaceView: View {
    public var repository: GitRepository
    /// Open the destination conflict editor for this (repository-relative) path.
    public var onResolveFile: (String) -> Void

    @State private var conflictedFiles: [String] = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    public init(repository: GitRepository, onResolveFile: @escaping (String) -> Void) {
        self.repository = repository
        self.onResolveFile = onResolveFile
    }

    public var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 16) {
                Label("Merge Conflict Resolver", systemImage: "arrow.triangle.merge")
                    .font(.title)
                    .bold()
                    .foregroundStyle(.red)
                    .padding(.top, 40)

                Text("Analyze and resolve conflict markers in the current workspace files.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)

                if isLoading {
                    ProgressView("Checking for conflicts…")
                        .controlSize(.small)
                } else if conflictedFiles.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "checkmark.shield.fill")
                            .font(.title)
                            .foregroundStyle(.green)
                        Text("No Conflicts Detected")
                            .font(.headline)
                        Text("Your working directory is clean of any active merge conflicts.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding()
                    .background(Color.secondary.opacity(0.08))
                    .cornerRadius(10)
                    .padding(.top, 20)
                } else {
                    List(conflictedFiles, id: \.self) { path in
                        HStack {
                            Image(systemName: "doc.text.fill")
                                .foregroundStyle(.red)
                            VStack(alignment: .leading) {
                                Text(URL(fileURLWithPath: path).lastPathComponent)
                                    .font(.headline)
                                Text(path)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("Resolve Conflicts") {
                                onResolveFile(path)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.red)
                        }
                        .padding(.vertical, 6)
                    }
                    .frame(height: 250)
                    .cornerRadius(10)
                    .padding(.horizontal)
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.subheadline)
                        .foregroundStyle(.red)
                }

                Button("Refresh") {
                    Task { await loadConflicts() }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Spacer()
            }
        }
        .task { await loadConflicts() }
    }

    private func loadConflicts() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        let repository = repository
        do {
            let status = try await Task.detached { try repository.status() }.value
            conflictedFiles = status
                .filter { $0.value == .conflicted }
                .map(\.key)
                .sorted()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

/// The working tree's unified diff, rendered hunk by hunk.
@MainActor
public struct UnifiedDiffView: View {
    public var repository: GitRepository

    @State private var hunks: [DiffHunk] = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    public init(repository: GitRepository) {
        self.repository = repository
    }

    public var body: some View {
        VStack {
            if isLoading {
                ProgressView("Loading unified diff…")
            } else if let errorMessage {
                Text(errorMessage)
                    .font(.subheadline)
                    .foregroundStyle(.red)
            } else if hunks.isEmpty {
                ContentUnavailableView(
                    "No Differences",
                    systemImage: "arrow.left.and.right",
                    description: Text("The working tree matches HEAD.")
                )
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(hunks) { hunk in
                            VStack(alignment: .leading, spacing: 0) {
                                Text("@@ -\(hunk.oldStart),\(hunk.oldCount) +\(hunk.newStart),\(hunk.newCount) @@")
                                    .font(.system(.caption, design: .monospaced).bold())
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(Color.secondary.opacity(0.12))
                                ForEach(hunk.lines.indices, id: \.self) { index in
                                    let line = hunk.lines[index]
                                    Text(line)
                                        .font(.system(.callout, design: .monospaced))
                                        .foregroundStyle(diffColor(for: line))
                                        .padding(.horizontal, 8)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .background(diffBackground(for: line))
                                }
                            }
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                    }
                    .padding()
                }
            }
        }
        .task { await loadDiff() }
    }

    private func diffColor(for line: String) -> Color {
        if line.hasPrefix("+") && !line.hasPrefix("+++") { return .green }
        if line.hasPrefix("-") && !line.hasPrefix("---") { return .red }
        return .primary
    }

    private func diffBackground(for line: String) -> Color {
        if line.hasPrefix("+") && !line.hasPrefix("+++") { return Color.green.opacity(0.08) }
        if line.hasPrefix("-") && !line.hasPrefix("---") { return Color.red.opacity(0.08) }
        return .clear
    }

    private func loadDiff() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        let repository = repository
        do {
            hunks = try await Task.detached { try repository.diffHunks() }.value
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
