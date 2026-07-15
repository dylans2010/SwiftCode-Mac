import SwiftUI
import os.log

private let logger = Logger(subsystem: "com.swiftcode.SourceControl", category: "GitConflictResolverView")

@MainActor
struct GitConflictResolverView: View {
    let conflictedFile: GitFileStatus
    var gitViewModel: GitViewModel
    var onDismiss: () -> Void

    // State of file contents & resolution
    @State private var localContent = ""
    @State private var remoteContent = ""
    @State private var mergedContent = ""

    @State private var conflictBlocks: [ConflictBlock] = []
    @State private var activeBlockIndex = 0

    // Loading states
    @State private var isLoading = true
    @State private var errorMessage = ""

    // AI suggestion states
    @State private var isRunningAIResolution = false
    @State private var aiSuggestionText = ""

    struct ConflictBlock: Identifiable, Equatable {
        let id = UUID()
        let currentText: String
        let incomingText: String
        let range: Range<String.Index>
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Label("Merge Conflict Resolver", systemImage: "arrow.triangle.merge")
                    .font(.headline)
                    .foregroundStyle(.red)

                Spacer()

                Button("Cancel") {
                    onDismiss()
                }
                .buttonStyle(.bordered)
            }
            .padding()
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            if isLoading {
                VStack {
                    ProgressView().controlSize(.small)
                    Text("Reading conflicted file markers...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if !errorMessage.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle.fill").font(.largeTitle).foregroundStyle(.red)
                    Text("Resolution Failed").font(.headline)
                    Text(errorMessage).font(.caption).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                mainConflictWorkspace
            }
        }
        .frame(width: 800, height: 600)
        .onAppear {
            parseConflictFile()
        }
    }

    private var mainConflictWorkspace: some View {
        VStack(spacing: 0) {
            // Sub-header stats & controls
            HStack {
                Text("File: \(conflictedFile.path.lastPathComponent)")
                    .font(.subheadline.bold())

                Spacer()

                if !conflictBlocks.isEmpty {
                    HStack {
                        Button {
                            if activeBlockIndex > 0 { activeBlockIndex -= 1 }
                        } label: {
                            Image(systemName: "chevron.left")
                        }
                        .disabled(activeBlockIndex == 0)

                        Text("Conflict \(activeBlockIndex + 1) of \(conflictBlocks.count)")
                            .font(.caption.bold())

                        Button {
                            if activeBlockIndex < conflictBlocks.count - 1 { activeBlockIndex += 1 }
                        } label: {
                            Image(systemName: "chevron.right")
                        }
                        .disabled(activeBlockIndex == conflictBlocks.count - 1)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.secondary.opacity(0.12))
                    .cornerRadius(4)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(Color.secondary.opacity(0.02))

            Divider()

            // Side-by-Side View of the Active Conflict Block
            HSplitView {
                // Left pane: Current change (HEAD)
                VStack(alignment: .leading, spacing: 0) {
                    Text("CURRENT CHANGE (HEAD)")
                        .font(.caption2.bold())
                        .foregroundStyle(.orange)
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.orange.opacity(0.1))

                    Divider()

                    ScrollView {
                        Text(activeBlockIndex < conflictBlocks.count ? conflictBlocks[activeBlockIndex].currentText : "No conflict block")
                            .font(.system(size: 11, design: .monospaced))
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .background(Color.black.opacity(0.85))

                    Button("Accept Current") {
                        acceptActiveChange(useCurrent: true)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .padding(8)
                    .frame(maxWidth: .infinity)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                // Right pane: Incoming change
                VStack(alignment: .leading, spacing: 0) {
                    Text("INCOMING CHANGE")
                        .font(.caption2.bold())
                        .foregroundStyle(.blue)
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.blue.opacity(0.1))

                    Divider()

                    ScrollView {
                        Text(activeBlockIndex < conflictBlocks.count ? conflictBlocks[activeBlockIndex].incomingText : "No conflict block")
                            .font(.system(size: 11, design: .monospaced))
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .background(Color.black.opacity(0.85))

                    Button("Accept Incoming") {
                        acceptActiveChange(useCurrent: false)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .padding(8)
                    .frame(maxWidth: .infinity)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(height: 220)

            Divider()

            // Manual Live Editor & Validation Output Pane
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("RESOLVED OUTPUT EDITOR (LIVE PREVIEW)")
                        .font(.caption2.bold())
                        .foregroundStyle(.green)

                    Spacer()

                    Button("Accept Both (Combined)") {
                        acceptBothChanges()
                    }
                    .buttonStyle(.plain)
                    .font(.caption)
                    .foregroundStyle(Color.accentColor)

                    Text("•").font(.caption).foregroundStyle(.secondary)

                    Button {
                        runAIConflictResolution()
                    } label: {
                        Label(isRunningAIResolution ? "Explaining..." : "AI Resolve Suggestion", systemImage: "sparkles")
                            .font(.caption)
                            .foregroundStyle(.purple)
                    }
                    .buttonStyle(.plain)
                    .disabled(isRunningAIResolution)
                }
                .padding(8)
                .background(Color.green.opacity(0.06))

                Divider()

                // Merged manual text editor area
                TextEditor(text: $mergedContent)
                    .font(.system(size: 11, design: .monospaced))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(8)
                    .background(Color(NSColor.controlBackgroundColor))

                Divider()

                // AI suggestions console
                if !aiSuggestionText.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("AI Recommended Resolution:").font(.caption.bold()).foregroundStyle(.purple)
                        ScrollView {
                            Text(aiSuggestionText)
                                .font(.system(size: 10, design: .monospaced))
                                .padding(6)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.black.opacity(0.1))
                                .cornerRadius(4)
                        }
                        .frame(height: 60)
                    }
                    .padding(8)
                    Divider()
                }

                // Resolution save and stage checks
                HStack {
                    // Validation label
                    let markersCount = countConflictMarkers(mergedContent)
                    if markersCount > 0 {
                        Label("\(markersCount) conflict markers remaining!", systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.red)
                    } else {
                        Label("Conflict markers resolved!", systemImage: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.green)
                    }

                    Spacer()

                    Button {
                        executeSaveAndResolve()
                    } label: {
                        Text("Save & Stage File")
                            .fontWeight(.bold)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
                    .disabled(markersCount > 0)
                }
                .padding(12)
                .background(Color(NSColor.windowBackgroundColor))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - Local marker parses logic

    private func parseConflictFile() {
        isLoading = true
        errorMessage = ""

        do {
            let path = conflictedFile.path
            let content = try String(contentsOf: path, encoding: .utf8)
            mergedContent = content

            // Find git conflict blocks natively
            var blocks: [ConflictBlock] = []
            let lines = content.components(separatedBy: .newlines)

            var isInsideConflict = false
            var currentBlockLines: [String] = []
            var incomingBlockLines: [String] = []
            var separatorPassed = false

            for line in lines {
                if line.hasPrefix("<<<<<<<") {
                    isInsideConflict = true
                    currentBlockLines = []
                    incomingBlockLines = []
                    separatorPassed = false
                } else if line.hasPrefix("=======") {
                    separatorPassed = true
                } else if line.hasPrefix(">>>>>>>") {
                    isInsideConflict = false
                    let current = currentBlockLines.joined(separator: "\n")
                    let incoming = incomingBlockLines.joined(separator: "\n")
                    blocks.append(ConflictBlock(currentText: current, incomingText: incoming, range: content.startIndex..<content.endIndex))
                } else if isInsideConflict {
                    if separatorPassed {
                        incomingBlockLines.append(line)
                    } else {
                        currentBlockLines.append(line)
                    }
                }
            }

            self.conflictBlocks = blocks
            if blocks.isEmpty {
                // Since we are running on real data, if no conflict markers are parsed, let conflictBlocks remain empty so the safety validator warns the user
                self.conflictBlocks = []
            }

            activeBlockIndex = 0
            isLoading = false
        } catch {
            errorMessage = "Failed to open file: \(error.localizedDescription)"
            isLoading = false
        }
    }

    private func acceptActiveChange(useCurrent: Bool) {
        guard activeBlockIndex < conflictBlocks.count else { return }
        let block = conflictBlocks[activeBlockIndex]
        let chosenText = useCurrent ? block.currentText : block.incomingText

        // Replace conflict blocks in the merged live text natively
        // Find markers inside text and replace first occurrence
        let lines = mergedContent.components(separatedBy: .newlines)
        var newLines: [String] = []
        var insideTargetConflict = false
        var conflictCounter = 0

        for line in lines {
            if line.hasPrefix("<<<<<<<") {
                if conflictCounter == activeBlockIndex {
                    insideTargetConflict = true
                    newLines.append(chosenText)
                } else {
                    newLines.append(line)
                }
            } else if line.hasPrefix("=======") {
                if !insideTargetConflict {
                    newLines.append(line)
                }
            } else if line.hasPrefix(">>>>>>>") {
                if insideTargetConflict {
                    insideTargetConflict = false
                    conflictCounter += 1
                } else {
                    newLines.append(line)
                }
            } else if !insideTargetConflict {
                newLines.append(line)
            }
        }

        mergedContent = newLines.joined(separator: "\n")
    }

    private func acceptBothChanges() {
        guard activeBlockIndex < conflictBlocks.count else { return }
        let block = conflictBlocks[activeBlockIndex]
        let combined = block.currentText + "\n" + block.incomingText

        let lines = mergedContent.components(separatedBy: .newlines)
        var newLines: [String] = []
        var insideTargetConflict = false
        var conflictCounter = 0

        for line in lines {
            if line.hasPrefix("<<<<<<<") {
                if conflictCounter == activeBlockIndex {
                    insideTargetConflict = true
                    newLines.append(combined)
                } else {
                    newLines.append(line)
                }
            } else if line.hasPrefix("=======") {
                if !insideTargetConflict {
                    newLines.append(line)
                }
            } else if line.hasPrefix(">>>>>>>") {
                if insideTargetConflict {
                    insideTargetConflict = false
                    conflictCounter += 1
                } else {
                    newLines.append(line)
                }
            } else if !insideTargetConflict {
                newLines.append(line)
            }
        }

        mergedContent = newLines.joined(separator: "\n")
    }

    private func countConflictMarkers(_ text: String) -> Int {
        let lines = text.components(separatedBy: .newlines)
        return lines.filter { $0.hasPrefix("<<<<<<<") }.count
    }

    private func executeSaveAndResolve() {
        do {
            // Overwrite local file with resolved merged text
            try mergedContent.write(to: conflictedFile.path, atomically: true, encoding: .utf8)

            // Stage file natively
            Task {
                await gitViewModel.stage(conflictedFile)
                await gitViewModel.refreshStatus()
                onDismiss()
            }
        } catch {
            logger.error("Conflict resolution save failed: \(error.localizedDescription)")
        }
    }

    private func runAIConflictResolution() {
        guard activeBlockIndex < conflictBlocks.count else { return }
        isRunningAIResolution = true
        aiSuggestionText = ""

        let block = conflictBlocks[activeBlockIndex]

        let prompt = """
        You are an expert AI Git Conflict Resolution Engineer.
        Analyze this conflict block from '\(conflictedFile.path.lastPathComponent)':

        <<<<<<< CURRENT CHANGE (HEAD)
        \(block.currentText)
        =======
        \(block.incomingText)
        >>>>>>> INCOMING BRANCH CHANGE

        Explain:
        1. What each branch change is doing.
        2. Propose a final clean merged code resolution combining both changes safely.
        Provide the output in exactly 3 lines:
        1. [Explanation] Brief explanation of what the conflict means.
        2. [Merged suggestion code] A clean suggested merged output.
        3. [Best Resolution Route] Recommendation (e.g. Accept Both or Current).
        """

        Task {
            do {
                let response = try await LLMService.shared.generateResponse(prompt: prompt, useContext: false)
                aiSuggestionText = response.trimmingCharacters(in: .whitespacesAndNewlines)
            } catch {
                aiSuggestionText = "AI Suggestion failed: \(error.localizedDescription)"
            }
            isRunningAIResolution = false
        }
    }
}
