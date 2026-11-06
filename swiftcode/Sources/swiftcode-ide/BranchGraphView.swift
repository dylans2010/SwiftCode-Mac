import Foundation
import SwiftUI

// Branch graph, adapted from Legacy's
// `SwiftCode/Views/Collaboration/BranchGraphView.swift` and
// `CollaborationBranchGraphView.swift`. The destination has branch
// history as a list (`SwiftCodeUI/SourceControl/BranchHistoryController.swift`,
// `SwiftCodeIDECore/Model/GitHistory.swift`) but no graph rendering, so
// this is a real one: it runs `git log --graph --oneline --all
// --decorate` in the repository and renders the actual graph output,
// with the branch list alongside. No graph is invented — when git
// fails, the error is shown instead of a placeholder drawing.

/// Renders the real `git log --graph` output for a repository.
struct BranchGraphView: View {
    /// The working directory of the git repository.
    var repositoryURL: URL

    @Environment(\.colorScheme) private var scheme
    @State private var graphLines: [String] = []
    @State private var branches: [String] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var selectedBranch: String?

    var body: some View {
        let c = ShellColors(scheme)
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text("Branch Graph").font(ShellFonts.rowBold)
                Spacer()
                if !branches.isEmpty {
                    Picker("Branch", selection: $selectedBranch) {
                        Text("All branches").tag(nil as String?)
                        ForEach(branches, id: \.self) { branch in
                            Text(verbatim: branch).tag(branch as String?)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(maxWidth: 220)
                }
                Button("Refresh") { reload() }
                    .disabled(isLoading)
            }
            .padding(10)
            if let error = errorMessage {
                Text(verbatim: error)
                    .font(ShellFonts.small)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 10)
                    .padding(.bottom, 6)
            }
            Hairline(color: c.separator)
            if isLoading && graphLines.isEmpty {
                ProgressView("Loading graph…").padding()
            } else if graphLines.isEmpty {
                ContentUnavailableView(
                    "No commits",
                    systemImage: "point.3.connected.trianglepath.dotted",
                    description: Text("This repository has no commits to graph, or git could not read it.")
                )
            } else {
                ScrollView([.horizontal, .vertical]) {
                    Text(verbatim: graphLines.joined(separator: "\n"))
                        .font(.system(.body, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .textSelection(.enabled)
                }
            }
        }
        .onAppear { reload() }
        .onChange(of: selectedBranch) { _, _ in reloadGraph() }
    }

    private func reload() {
        reloadBranches()
        reloadGraph()
    }

    private func reloadBranches() {
        Task {
            let result = await BranchGraphRunner.run(
                git: ["branch", "--format=%(refname:short)"],
                in: repositoryURL)
            switch result {
            case .success(let output):
                branches = output
                    .components(separatedBy: .newlines)
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty }
            case .failure:
                branches = []
            }
        }
    }

    private func reloadGraph() {
        isLoading = true
        errorMessage = nil
        Task {
            var args = ["log", "--graph", "--oneline", "--decorate", "-n", "200"]
            if let branch = selectedBranch {
                args.append(branch)
            } else {
                args.append("--all")
            }
            let result = await BranchGraphRunner.run(git: args, in: repositoryURL)
            switch result {
            case .success(let output):
                graphLines = output.components(separatedBy: .newlines)
            case .failure(let error):
                graphLines = []
                errorMessage = error
            }
            isLoading = false
        }
    }
}

/// Runs git and returns its stdout, or a human-readable failure.
/// `git` is resolved from the PATH so a developer's installed git is
/// used rather than a hardcoded location that may not exist.
enum BranchGraphRunner {
    static func run(git arguments: [String], in directory: URL) async -> Result<String, String> {
        await Task.detached(priority: .userInitiated) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = ["git"] + arguments
            process.currentDirectoryURL = directory
            let pipe = Pipe()
            let errorPipe = Pipe()
            process.standardOutput = pipe
            process.standardError = errorPipe
            do {
                try process.run()
            } catch {
                return .failure("Could not run git: \(error.localizedDescription)")
            }
            process.waitUntilExit()
            let output = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            guard process.terminationStatus == 0 else {
                let detail = String(decoding: errorPipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                return .failure(detail.isEmpty
                    ? "git exited with status \(process.terminationStatus)"
                    : detail)
            }
            return .success(output)
        }.value
    }
}
