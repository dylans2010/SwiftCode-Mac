import Foundation
import SwiftUI
import SwiftCodeExtensions
import SwiftCodeSDK
import SwiftCodeSDKStudio

// MARK: - SDKStudioProjectsView
//
// Legacy: `SwiftCode/SDK/Studio/Views/SDKStudioProjectsView.swift`.
// Creation cards for the three wizards, recent projects (persisted in
// UserDefaults, filtered to paths that still exist), and "Open Existing
// Project…". Directory picking is a path field in this target (pure
// SwiftUI — no AppKit panels in `swiftcode-ide`); the wizard validates the
// directory the same way Legacy's panel flow did (must be empty or
// nonexistent).

@MainActor
struct SDKStudioProjectsView: View {
    let editorState: SDKCodeEditorState
    let onOpenInCodeEditor: (URL) -> Void
    let onOpenInManifestEditor: (URL) -> Void

    @State private var activeWizard: SDKStudioWizardConfig?
    @State private var recentProjectPaths: [String] = []
    @State private var openPathText: String = ""
    @State private var openError: String?
    @State private var isPreparingExample = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Platform Projects")
                    .font(.title2.bold())
                Text("Create a new extension or project, or open an existing one. Extensions run out-of-process under host capability controls; standalone projects are ordinary user-owned code.")
                    .foregroundStyle(.secondary)
                creationCards
                sdkExample
                recentProjects
                openExisting
                if let openError {
                    Text(openError).foregroundStyle(.red)
                }
            }
            .padding()
        }
        .task { loadRecentProjects() }
        .sheet(isPresented: Binding(
            get: { activeWizard != nil },
            set: { if !$0 { activeWizard = nil } }
        )) {
            if let config = activeWizard {
                SDKStudioWizardSheet(config: config) { url in
                    SDKStudioRecentProjects.record(url)
                    loadRecentProjects()
                    onOpenInCodeEditor(url)
                }
            }
        }
    }

    private var creationCards: some View {
        HStack(spacing: 16) {
            SDKStudioCreationCard(title: "New Extension", subtitle: "TypeScript extension with a swiftcode.json manifest.",
                                  systemImage: "puzzlepiece.extension") {
                activeWizard = .newExtension
            }
            SDKStudioCreationCard(title: "New TypeScript Project", subtitle: "Standalone TypeScript project (npm / tsc / node).",
                                  systemImage: "chevron.left.forwardslash.chevron.right") {
                activeWizard = .newTypeScriptProject
            }
            SDKStudioCreationCard(title: "New Swift Project", subtitle: "Standalone SwiftUI macOS app scaffold.",
                                  systemImage: "folder.badge.gearshape") {
                activeWizard = .newSwiftProject
            }
        }
    }

    private var sdkExample: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("SDK Example").font(.headline)
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Repository Build Extension").font(.callout)
                    Text("A minimal working extension (\(SDKExampleManager.exampleID)) prepared from the SDK templates into your own projects folder. Open it to inspect the manifest, commands, and build setup.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button(isPreparingExample ? "Preparing…" : "Open Example") { openExample() }
                    .buttonStyle(.borderedProminent)
                    .disabled(isPreparingExample)
            }
        }
    }

    private func openExample() {
        isPreparingExample = true
        openError = nil
        Task {
            do {
                let url = try SDKExampleManager.prepareExampleProject()
                SDKStudioRecentProjects.record(url)
                loadRecentProjects()
                onOpenInCodeEditor(url)
            } catch let error as SDKExampleManager.SDKExampleError {
                switch error {
                case .templateNotFound:
                    openError = "The SDK example template was not found. Run Studio from a SwiftCode checkout or install the SDK templates."
                case .invalidTemplate(let reason):
                    openError = "The SDK example is invalid: \(reason)"
                case .preparationFailed(let reason):
                    openError = "Could not prepare the SDK example: \(reason)"
                }
            } catch {
                openError = error.localizedDescription
            }
            isPreparingExample = false
        }
    }

    private var recentProjects: some View {
        Group {
            HStack {
                Text("Recent Projects").font(.headline)
                Spacer()
                if !recentProjectPaths.isEmpty {
                    Button("Clear") {
                        SDKStudioRecentProjects.clear()
                        loadRecentProjects()
                    }
                }
            }
            if recentProjectPaths.isEmpty {
                Text("No recent projects yet. Create or open a project to see it here.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(recentProjectPaths, id: \.self) { path in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(URL(fileURLWithPath: path).lastPathComponent).font(.headline)
                            Text(path).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Open in Editor") { onOpenInCodeEditor(URL(fileURLWithPath: path)) }
                        Button("Manifest") { onOpenInManifestEditor(URL(fileURLWithPath: path)) }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }

    private var openExisting: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Open Existing Project…").font(.headline)
            HStack {
                TextField("/path/to/project", text: $openPathText)
                    .textFieldStyle(.roundedBorder)
                Button("Open") { openExistingProject() }
                    .buttonStyle(.borderedProminent)
            }
            Text("Enter a project folder path. It must contain a swiftcode.json, Package.swift, or .xcodeproj to be recognized.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func loadRecentProjects() {
        recentProjectPaths = SDKStudioRecentProjects.load()
    }

    private func openExistingProject() {
        let path = openPathText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty else { openError = "Enter a project folder path."; return }
        let url = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: url.path) else {
            openError = "No such folder: \(path)"
            return
        }
        do {
            let metadata = try ProjectInspector().inspect(at: path)
            _ = metadata
            openError = nil
            SDKStudioRecentProjects.record(url)
            loadRecentProjects()
            onOpenInCodeEditor(url)
        } catch {
            openError = error.localizedDescription
        }
    }
}

private struct SDKStudioCreationCard: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: systemImage).font(.title2)
                Text(title).font(.headline)
                Text(subtitle).font(.callout).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
        }
        .buttonStyle(.bordered)
    }
}

// MARK: - Wizard sheet

@MainActor
private struct SDKStudioWizardSheet: View {
    let config: SDKStudioWizardConfig
    let onCreated: (URL) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var values: [String: String]
    @State private var phase: Phase = .editing
    @State private var log: [String] = []

    private enum Phase {
        case editing
        case success(target: URL, written: [String])
        case failure(message: String)
    }

    init(config: SDKStudioWizardConfig, onCreated: @escaping (URL) -> Void) {
        self.config = config
        self.onCreated = onCreated
        var initial: [String: String] = [:]
        for field in config.fields { initial[field.key] = field.initialValue }
        _values = State(initialValue: initial)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(config.title).font(.title2.bold())
            Text(config.subtitle).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 6) {
                Text(config.bannerTitle).font(.headline)
                Text(config.bannerBody).font(.callout).foregroundStyle(.secondary)
            }
            .padding()
            .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
            switch phase {
            case .editing:
                editingView
            case .success(let target, let written):
                VStack(alignment: .leading, spacing: 8) {
                    Text("Created \(target.lastPathComponent)").font(.headline)
                    Text(target.path).font(.callout.monospaced())
                    ForEach(written, id: \.self) { Text($0).font(.caption) }
                    HStack(spacing: 12) {
                        Button("Open in Editor") {
                            dismiss()
                            onCreated(target)
                        }
                        .buttonStyle(.borderedProminent)
                        Button("Close") { dismiss() }
                    }
                }
            case .failure(let message):
                VStack(alignment: .leading, spacing: 8) {
                    Text("Could not create the project").font(.headline)
                    Text(message).foregroundStyle(.red)
                    Button("Back") { phase = .editing }
                        .buttonStyle(.borderedProminent)
                }
            }
            Spacer()
        }
        .padding()
        .frame(minWidth: 560, minHeight: 520)
    }

    private var editingView: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(config.fields) { field in
                fieldRow(field)
            }
            if !log.isEmpty {
                Text(log.joined(separator: "\n")).font(.caption.monospaced())
            }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Create") { create() }
                    .buttonStyle(.borderedProminent)
                    .disabled(!isValid)
            }
        }
    }

    private func fieldRow(_ field: SDKStudioWizardField) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(field.label).font(.headline)
                Spacer()
                if let error = fieldError(field) {
                    Text(error).font(.caption).foregroundStyle(.red)
                }
            }
            switch field.kind {
            case .text(let lines):
                if lines > 1 {
                    TextEditor(text: binding(for: field.key))
                        .frame(height: CGFloat(lines) * 22)
                        .border(Color.secondary.opacity(0.3))
                } else {
                    TextField(field.placeholder, text: binding(for: field.key))
                        .textFieldStyle(.roundedBorder)
                }
            case .directory:
                HStack {
                    TextField(field.placeholder, text: binding(for: field.key))
                        .textFieldStyle(.roundedBorder)
                    Button("Browse…") { browseDirectory(for: field.key) }
                }
            }
            Text(field.help).font(.caption).foregroundStyle(.secondary)
        }
    }

    private func binding(for key: String) -> Binding<String> {
        Binding(
            get: { values[key] ?? "" },
            set: { values[key] = $0 }
        )
    }

    private func fieldError(_ field: SDKStudioWizardField) -> String? {
        field.validate(values[field.key] ?? "")
    }

    private var isValid: Bool {
        config.fields.allSatisfy { fieldError($0) == nil }
    }

    private func browseDirectory(for key: String) {
        // Pure-SwiftUI target: no file panel. The user types or pastes a
        // path; validation (empty / non-empty) runs the same as Legacy's.
        // The macOS AppKit shell can replace this with an NSOpenPanel.
        values[key] = values[key] ?? ""
    }

    private func create() {
        do {
            var progress: [String] = []
            let result = try SDKStudioScaffold.create(config: config, values: values) { file in
                progress.append(file)
            }
            log = progress
            phase = .success(target: result.target, written: result.written)
        } catch {
            phase = .failure(message: error.localizedDescription)
        }
    }
}
