import Foundation
import SwiftUI

// MARK: - SDKCodeBuildRunView
//
// Build/run toolbar + panel for the Studio code editor: a kind picker
// (xcodebuild / npm / node), a scheme/entry field, Build/Run, and Stop —
// all wired to `SDKCodeBuildRunner` with the active project root. Output
// streams live into the editor console (`SDKCodeEditorState`); this view
// only shows the running state.
//
// Disabled states are honest: with no project root, every action is
// disabled with a tooltip explaining why; while a run is in flight, the
// start controls are disabled and only Stop is enabled.

public struct SDKCodeBuildRunView: View {

    /// The active project root, or `nil` when no project is open. When
    /// `nil`, all actions are disabled.
    private let projectRoot: URL?

    /// The editor session whose console receives live build/run output.
    @ObservedObject private var editorState: SDKCodeEditorState

    private let runner: SDKCodeBuildRunner

    @State private var kind: SDKBuildRunKind = .xcodebuildSwift
    @State private var schemeOrEntry: String = ""
    @State private var runningTaskID: UUID?

    public init(
        projectRoot: URL?,
        editorState: SDKCodeEditorState,
        runner: SDKCodeBuildRunner = .shared
    ) {
        self.projectRoot = projectRoot
        self.editorState = editorState
        self.runner = runner
    }

    private var hasProjectRoot: Bool { projectRoot != nil }
    private var isRunning: Bool { runningTaskID != nil }
    private var canStart: Bool { hasProjectRoot && !isRunning }

    private var actionLabel: String {
        kind == .nodeScript ? "Run" : "Build"
    }

    private var startHelp: String {
        if !hasProjectRoot {
            return "Open a project to build or run."
        }
        if isRunning {
            return "A build or run is already in progress."
        }
        switch kind {
        case .xcodebuildSwift:
            return "Build the Xcode project with the managed build service."
        case .typescriptExtension:
            return "Run the project's build script (npm run build)."
        case .nodeScript:
            return "Run the script with node."
        }
    }

    private var fieldPlaceholder: String {
        switch kind {
        case .xcodebuildSwift:
            return "Scheme (blank = auto-detect)"
        case .typescriptExtension:
            return "Uses the package.json \"build\" script"
        case .nodeScript:
            return "Script path, e.g. dist/index.js"
        }
    }

    private var fieldHelp: String {
        switch kind {
        case .xcodebuildSwift:
            return "Xcode scheme to build. Blank lets the project resolver pick the scheme."
        case .typescriptExtension:
            return "The manifest's build script is used; no entry is needed."
        case .nodeScript:
            return "Script path relative to the project root."
        }
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Picker("Kind", selection: $kind) {
                    ForEach(SDKBuildRunKind.allCases, id: \.self) { kind in
                        Text(kind.displayName).tag(kind)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 380)
                .disabled(!canStart)
                .help("What to build or run.")

                TextField("Scheme or entry", text: $schemeOrEntry, prompt: Text(fieldPlaceholder))
                    .textFieldStyle(.roundedBorder)
                    .disabled(!canStart || kind == .typescriptExtension)
                    .help(fieldHelp)

                Spacer()

                Button(actionLabel) { start() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canStart)
                    .help(startHelp)

                Button("Stop", role: .destructive) { stop() }
                    .disabled(!isRunning)
                    .help(isRunning ? "Terminate the running build or process." : "Nothing is running.")
            }

            statusLine
        }
        .padding(8)
    }

    private var statusLine: some View {
        Group {
            if isRunning {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("\(kind.displayName) running…")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } else if !hasProjectRoot {
                Text("Open a project to enable build & run.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                Text(hintText)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var hintText: String {
        switch kind {
        case .xcodebuildSwift:
            return "Builds the Xcode project at the project root with the managed build service."
        case .typescriptExtension:
            return "Runs \"npm run build\" in the project root."
        case .nodeScript:
            return "Runs the script with node in the project root."
        }
    }

    // MARK: - Actions

    private func start() {
        guard let root = projectRoot, !isRunning else { return }
        let entry = schemeOrEntry.trimmingCharacters(in: .whitespacesAndNewlines)
        let request = SDKBuildRunRequest(
            projectRoot: root,
            kind: kind,
            schemeOrEntry: entry.isEmpty ? nil : entry
        )
        runningTaskID = request.taskID
        let runner = runner
        let editorState = editorState
        Task {
            await runner.run(request, into: editorState)
            runningTaskID = nil
        }
    }

    private func stop() {
        guard let taskID = runningTaskID else { return }
        let runner = runner
        Task {
            await runner.cancel(taskID: taskID)
        }
    }
}
