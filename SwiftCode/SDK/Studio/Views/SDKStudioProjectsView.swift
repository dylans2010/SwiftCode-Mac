//
//  SDKStudioProjectsView.swift
//
//  SwiftCode SDK — Studio project & extension creation hub.
//
//  Spec: Docs/Intro-to-SDK.md §13.3 — Studio is the ONLY UI surface where
//  SwiftCode platform projects and extensions may be created. The main
//  editor is restricted to editing; its New Project affordances redirect
//  here (enforcement hook documented in SwiftCode/SDK/Studio/agent_notes.md).
//
//  Scaffolding is implemented NATIVELY in Swift: template file contents are
//  embedded as string literals — faithful copies of
//  SwiftCode/SDK/TypeScript/templates/extension-typescript/,
//  SwiftCode/SDK/TypeScript/templates/project-typescript/, and the manifest
//  schema at SwiftCode/SDK/Contracts/Manifest/ — and written to the chosen
//  directory with placeholder substitution. No node process, no shell, no
//  network: the wizard works entirely from inside the app.
//
//  Swift 6.0, macOS 15. AppKit is imported only for NSOpenPanel (directory
//  picker) and NSWorkspace (Reveal in Finder); everything else is SwiftUI +
//  Foundation.

import AppKit // NSOpenPanel (directory picker), NSWorkspace (Reveal in Finder)
import Foundation
import SwiftUI

// MARK: - SDKStudioProjectsView

/// Studio's project/extension creation hub (spec §13.3).
///
/// This view is the exclusive creation surface for SwiftCode platform
/// projects and SDK extensions. Each card opens a wizard that really
/// creates the project on disk — there are no placeholder flows.
public struct SDKStudioProjectsView: View {

    public init() {}

    private enum SheetKind: String, Identifiable {
        case newExtension
        case newTypeScriptProject
        case newSwiftProject

        var id: String { rawValue }
    }

    @State private var activeSheet: SheetKind?

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                cards
            }
            .padding(28)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .sheet(item: $activeSheet) { kind in
            switch kind {
            case .newExtension:
                ScaffoldWizardView(config: .newExtension)
            case .newTypeScriptProject:
                ScaffoldWizardView(config: .newTypeScriptProject)
            case .newSwiftProject:
                ScaffoldWizardView(config: .newSwiftProject)
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Platform Projects")
                .font(.largeTitle)
                .fontWeight(.bold)
            Text("Studio is the only place in SwiftCode where platform projects and extensions can be created (spec §13.3). The main editor is for editing code — its New Project commands redirect here, so every platform project starts life under the SDK's manifest, capability, and packaging rules.")
                .foregroundStyle(.secondary)
                .frame(maxWidth: 680, alignment: .leading)
        }
    }

    private var cards: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: 16)], spacing: 16) {
            CreationCard(
                systemImage: "puzzlepiece.extension",
                title: "New Extension",
                description: "TypeScript extension with a swiftcode.json manifest, declared capabilities, and the @swiftcode/sdk runtime contract. Runs out-of-process under host capability controls.",
                buttonTitle: "Create Extension…"
            ) { activeSheet = .newExtension }

            CreationCard(
                systemImage: "chevron.left.forwardslash.chevron.right",
                title: "New TypeScript Project",
                description: "Standalone TypeScript project with the verified npm / tsc workflow. User-owned code — not subject to extension sandbox restrictions (spec §14.1).",
                buttonTitle: "Create TypeScript Project…"
            ) { activeSheet = .newTypeScriptProject }

            CreationCard(
                systemImage: "curlybraces",
                title: "New Swift Project",
                description: "Standalone SwiftUI macOS app scaffold. User-owned code with the ordinary Swift and Xcode workflow (spec §14.1).",
                buttonTitle: "Create Swift Project…"
            ) { activeSheet = .newSwiftProject }
        }
    }
}

// MARK: - CreationCard

private struct CreationCard: View {
    let systemImage: String
    let title: String
    let description: String
    let buttonTitle: String
    let action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: systemImage)
                .font(.title2)
                .foregroundStyle(.tint)
            Text(title)
                .font(.headline)
            Text(description)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
            Button(buttonTitle, action: action)
                .buttonStyle(.borderedProminent)
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 190, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(.separator, lineWidth: 1)
        )
    }
}

// MARK: - Wizard model

/// One input row in a scaffold wizard.
private struct WizardField: Identifiable {
    enum Kind {
        /// Single- or multi-line text. lines > 1 renders a TextEditor.
        case text(lines: Int)
        case directory
    }

    let key: String
    let label: String
    let placeholder: String
    let kind: Kind
    let help: String?
    let initialValue: String
    /// Returns a human-readable error, or nil when the value is acceptable.
    let validate: (String) -> String?

    var id: String { key }
}

private struct WizardBanner {
    let title: String
    let body: String
}

private enum WizardKind {
    case newExtension
    case newTypeScriptProject
    case newSwiftProject
}

private struct WizardConfig {
    let kind: WizardKind
    let title: String
    let subtitle: String
    let banner: WizardBanner?
    let fields: [WizardField]
}

// MARK: - ScaffoldWizardView

/// Generic creation wizard driven by a ``WizardConfig``.
///
/// Behavior contract: live per-field validation, the Create button stays
/// disabled until every field validates, the directory is chosen with a
/// native NSOpenPanel, scaffolding writes real files to disk, success shows
/// the real path with an Open in Finder button, and failure shows the real
/// error. The log area lists every file written.
private struct ScaffoldWizardView: View {
    let config: WizardConfig

    private enum Phase: Equatable {
        case editing
        case success(target: URL, written: [String])
        case failure(message: String)
    }

    @State private var values: [String: String]
    @State private var phase: Phase = .editing
    @State private var isWriting = false
    @State private var log: [String] = []
    @Environment(\.dismiss) private var dismiss

    init(config: WizardConfig) {
        self.config = config
        var initial: [String: String] = [:]
        for field in config.fields {
            initial[field.key] = field.initialValue
        }
        _values = State(initialValue: initial)
    }

    var body: some View {
        Group {
            switch phase {
            case .editing:
                formView
            case .success(let target, let written):
                successView(target: target, written: written)
            case .failure(let message):
                failureView(message: message)
            }
        }
        .frame(minWidth: 620, minHeight: 560)
        .padding(24)
    }

    // MARK: Form

    private var formView: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text(config.title)
                    .font(.title2)
                    .fontWeight(.semibold)
                Text(config.subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let banner = config.banner {
                bannerView(banner)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(config.fields) { field in
                        fieldRow(field)
                    }
                }
                .padding(.vertical, 4)
            }

            if !log.isEmpty || isWriting {
                logView
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .disabled(isWriting)
                Button {
                    create()
                } label: {
                    if isWriting {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Text("Create")
                    }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(!isValid || isWriting)
            }
        }
    }

    private func bannerView(_ banner: WizardBanner) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "info.circle")
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 4) {
                Text(banner.title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Text(banner.body)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func fieldRow(_ field: WizardField) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(field.label)
                .font(.subheadline)
                .fontWeight(.medium)
            switch field.kind {
            case .text(let lines):
                if lines > 1 {
                    TextEditor(text: binding(for: field.key))
                        .frame(minHeight: 72)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .stroke(.separator, lineWidth: 1)
                        )
                } else {
                    TextField(field.placeholder, text: binding(for: field.key))
                        .textFieldStyle(.roundedBorder)
                }
            case .directory:
                HStack(spacing: 8) {
                    TextField(field.placeholder, text: binding(for: field.key))
                        .textFieldStyle(.roundedBorder)
                        .disabled(true)
                        .textSelection(.enabled)
                    Button("Browse…") {
                        browseDirectory(for: field.key)
                    }
                }
            }
            if let help = field.help {
                Text(help)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let error = fieldError(field) {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var logView: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(isWriting ? "Writing…" : "Written")
                .font(.subheadline)
                .fontWeight(.medium)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(log, id: \.self) { line in
                        Text(line)
                            .font(.caption)
                            .fontDesign(.monospaced)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 120)
            .padding(8)
            .background(Color(nsColor: .textBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
    }

    // MARK: Validation

    private func binding(for key: String) -> Binding<String> {
        Binding(
            get: { values[key] ?? "" },
            set: { values[key] = $0 }
        )
    }

    private func fieldError(_ field: WizardField) -> String? {
        field.validate(values[field.key] ?? "")
    }

    private var isValid: Bool {
        config.fields.allSatisfy { fieldError($0) == nil }
    }

    // MARK: Directory picking

    private func browseDirectory(for key: String) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.prompt = "Choose"
        panel.message = "Choose the project directory. It must be empty — use New Folder in the panel to create one."
        let current = values[key] ?? ""
        if !current.isEmpty {
            panel.directoryURL = URL(fileURLWithPath: current)
        }
        // runModal is synchronous: no escaping completion handler, no
        // Sendable or cross-executor concerns; the @State write below runs
        // on @MainActor exactly like a Button action.
        if panel.runModal() == .OK, let url = panel.url {
            values[key] = url.path
        }
    }

    // MARK: Creation

    /// Writes the project synchronously on the main actor. The write is a
    /// handful of small files (milliseconds); doing it inline keeps the
    /// whole flow on @MainActor with no Sendable or cross-executor hazards.
    private func create() {
        guard isValid, !isWriting else { return }
        guard let outDir = values["outDir"], !outDir.isEmpty else { return }
        let target = URL(fileURLWithPath: outDir)
        let snapshot = values
        isWriting = true
        log = []
        defer { isWriting = false }
        do {
            let written: [String]
            switch config.kind {
            case .newExtension:
                written = try ScaffoldEngine.scaffoldExtension(values: snapshot, target: target) { rel in
                    log.append("Wrote \(rel)")
                }
            case .newTypeScriptProject:
                written = try ScaffoldEngine.scaffoldTypeScriptProject(values: snapshot, target: target) { rel in
                    log.append("Wrote \(rel)")
                }
            case .newSwiftProject:
                written = try ScaffoldEngine.scaffoldSwiftProject(values: snapshot, target: target) { rel in
                    log.append("Wrote \(rel)")
                }
            }
            phase = .success(target: target, written: written)
        } catch {
            let message: String
            if let scaffoldError = error as? ScaffoldError {
                message = scaffoldError.message
            } else {
                message = error.localizedDescription
            }
            phase = .failure(message: message)
        }
    }

    // MARK: Result views

    private func successView(target: URL, written: [String]) -> some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.green)
            Text("Created \(written.count) files")
                .font(.title3)
                .fontWeight(.semibold)
            Text(target.path)
                .font(.callout)
                .fontDesign(.monospaced)
                .textSelection(.enabled)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 520)
            Text("Next: open a terminal in that directory and follow the README (npm install, build, test).")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 520)
            HStack(spacing: 12) {
                Button("Open in Finder") {
                    NSWorkspace.shared.open(target)
                }
                .buttonStyle(.borderedProminent)
                Button("Done") { dismiss() }
            }
            .padding(.top, 4)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func failureView(message: String) -> some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "xmark.octagon.fill")
                .font(.system(size: 48))
                .foregroundStyle(.red)
            Text("Creation failed")
                .font(.title3)
                .fontWeight(.semibold)
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 520)
            HStack(spacing: 12) {
                Button("Back") { phase = .editing }
                    .buttonStyle(.borderedProminent)
                Button("Close") { dismiss() }
            }
            .padding(.top, 4)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Wizard configurations

extension WizardConfig {

    static var newExtension: WizardConfig {
        WizardConfig(
            kind: .newExtension,
            title: "New Extension",
            subtitle: "TypeScript extension with a swiftcode.json manifest. Extensions run out-of-process under host capability controls and can never invoke Assist.",
            banner: WizardBanner(
                title: "Capabilities — fixed in v1",
                body: "Every generated extension declares exactly source-control.read (display repository status and diffs) and build.execute (run builds through SwiftCode's managed build service), matching the shipped template and the generator's manifest tests. Additional capabilities are not available in this release, so this is shown for transparency and is not editable."
            ),
            fields: [
                WizardField(
                    key: "id",
                    label: "Extension ID",
                    placeholder: "com.example.my-ext",
                    kind: .text(lines: 1),
                    help: "Reverse-DNS identifier. Also used as the install directory name.",
                    initialValue: "",
                    validate: Validators.extensionID
                ),
                WizardField(
                    key: "name",
                    label: "Display Name",
                    placeholder: "My Extension",
                    kind: .text(lines: 1),
                    help: "Human-readable name, shown in the manifest and README.",
                    initialValue: "",
                    validate: Validators.displayName
                ),
                WizardField(
                    key: "version",
                    label: "Version",
                    placeholder: "0.1.0",
                    kind: .text(lines: 1),
                    help: "Semantic version of the extension package.",
                    initialValue: "0.1.0",
                    validate: Validators.semver
                ),
                WizardField(
                    key: "description",
                    label: "Description",
                    placeholder: "What this extension does…",
                    kind: .text(lines: 3),
                    help: "Optional. Plain-language description, up to 1000 characters.",
                    initialValue: "",
                    validate: Validators.description
                ),
                WizardField(
                    key: "outDir",
                    label: "Project Directory",
                    placeholder: "No directory chosen",
                    kind: .directory,
                    help: "The extension project is created inside this directory. It must be empty or not exist yet.",
                    initialValue: "",
                    validate: Validators.targetDirectory
                ),
                WizardField(
                    key: "sdkPackage",
                    label: "SDK Package (@swiftcode/sdk)",
                    placeholder: "No SDK package located",
                    kind: .directory,
                    help: "Local @swiftcode/sdk package directory. The generated package.json depends on it via a file: URL — exactly what create-extension.mjs --sdk-path does. Auto-detected from the app bundle or SWIFTCODE_SDK_PACKAGE; override with Browse if needed.",
                    initialValue: ScaffoldEngine.defaultSDKPackageDir(),
                    validate: Validators.sdkPackage
                ),
            ]
        )
    }

    static var newTypeScriptProject: WizardConfig {
        WizardConfig(
            kind: .newTypeScriptProject,
            title: "New TypeScript Project",
            subtitle: "Standalone TypeScript project with the verified npm / tsc / node workflow. User-owned code — not subject to extension sandbox restrictions (spec §14.1).",
            banner: WizardBanner(
                title: "Standalone, not an extension",
                body: "This scaffold produces ordinary user-owned code: no swiftcode.json manifest, no capability declarations, no runtime sandbox. It builds and runs with the language's own toolchain."
            ),
            fields: [
                WizardField(
                    key: "name",
                    label: "Project Name",
                    placeholder: "My Project",
                    kind: .text(lines: 1),
                    help: "Human-readable name, shown in the README and source header.",
                    initialValue: "",
                    validate: Validators.displayName
                ),
                WizardField(
                    key: "slug",
                    label: "Package Name",
                    placeholder: "my-project",
                    kind: .text(lines: 1),
                    help: "npm package name: lowercase letters, digits, dots, hyphens, underscores, tildes.",
                    initialValue: "",
                    validate: Validators.npmSlug
                ),
                WizardField(
                    key: "version",
                    label: "Version",
                    placeholder: "0.1.0",
                    kind: .text(lines: 1),
                    help: "Semantic version of the package.",
                    initialValue: "0.1.0",
                    validate: Validators.semver
                ),
                WizardField(
                    key: "description",
                    label: "Description",
                    placeholder: "What this project does…",
                    kind: .text(lines: 3),
                    help: "Optional. Plain-language description, up to 1000 characters.",
                    initialValue: "",
                    validate: Validators.description
                ),
                WizardField(
                    key: "outDir",
                    label: "Project Directory",
                    placeholder: "No directory chosen",
                    kind: .directory,
                    help: "The project is created inside this directory. It must be empty or not exist yet.",
                    initialValue: "",
                    validate: Validators.targetDirectory
                ),
            ]
        )
    }

    static var newSwiftProject: WizardConfig {
        WizardConfig(
            kind: .newSwiftProject,
            title: "New Swift Project",
            subtitle: "Standalone SwiftUI macOS app scaffold. User-owned code with the ordinary Swift and Xcode workflow (spec §14.1).",
            banner: WizardBanner(
                title: "Scaffold contents",
                body: "Generates the Standalone-Swift template: App.swift (the @main entry point), ContentView.swift, a README with the Xcode setup steps, and a .gitignore. App identity (bundle ID, signing) is set on your own Xcode target, not in these files."
            ),
            fields: [
                WizardField(
                    key: "name",
                    label: "App Name",
                    placeholder: "MyApp",
                    kind: .text(lines: 1),
                    help: "Used as the Swift type name (e.g. MyApp becomes MyAppApp and MyApp.swift). Letters, digits, underscores; must start with a letter or underscore.",
                    initialValue: "",
                    validate: Validators.swiftTypeName
                ),
                WizardField(
                    key: "bundleId",
                    label: "Bundle Identifier",
                    placeholder: "com.example.myapp",
                    kind: .text(lines: 1),
                    help: "Reverse-DNS bundle identifier recorded in the README.",
                    initialValue: "",
                    validate: Validators.bundleID
                ),
                WizardField(
                    key: "outDir",
                    label: "Project Directory",
                    placeholder: "No directory chosen",
                    kind: .directory,
                    help: "The project is created inside this directory. It must be empty or not exist yet.",
                    initialValue: "",
                    validate: Validators.targetDirectory
                ),
            ]
        )
    }
}

// MARK: - Validators

/// Client-side validation mirroring the rules in
/// SwiftCode/SDK/TypeScript/cli/create-extension.mjs.
private enum Validators {

    static func extensionID(_ value: String) -> String? {
        let v = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if v.isEmpty { return "Required." }
        if v.count > 128 { return "Must be at most 128 characters." }
        if v.wholeMatch(of: #/^[A-Za-z][A-Za-z0-9-]*(\.[A-Za-z][A-Za-z0-9-]*)+$/#) == nil {
            return "Must be reverse-DNS: letters, digits, hyphens, at least one dot (e.g. com.example.my-ext)."
        }
        return nil
    }

    static func bundleID(_ value: String) -> String? {
        extensionID(value)
    }

    static func displayName(_ value: String) -> String? {
        let v = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if v.isEmpty { return "Required." }
        if v.count > 128 { return "Must be at most 128 characters." }
        return nil
    }

    static func semver(_ value: String) -> String? {
        let v = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if v.isEmpty { return "Required." }
        if v.wholeMatch(of: #/^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)(-((0|[1-9]\d*|\d*[a-zA-Z-][0-9a-zA-Z-]*)(\.(0|[1-9]\d*|\d*[a-zA-Z-][0-9a-zA-Z-]*))*))?(\+([0-9a-zA-Z-]+(\.[0-9a-zA-Z-]+)*))?$/#) == nil {
            return "Must be valid semantic versioning (e.g. 0.1.0)."
        }
        return nil
    }

    static func description(_ value: String) -> String? {
        if value.count > 1000 { return "Must be at most 1000 characters." }
        return nil
    }

    static func npmSlug(_ value: String) -> String? {
        let v = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if v.isEmpty { return "Required." }
        if v.wholeMatch(of: #/^[a-z0-9][a-z0-9._~-]*$/#) == nil {
            return "Lowercase letters, digits, dots, hyphens, underscores, tildes (e.g. my-project)."
        }
        return nil
    }

    static func swiftTypeName(_ value: String) -> String? {
        let v = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if v.isEmpty { return "Required." }
        if v.wholeMatch(of: #/^[A-Za-z_][A-Za-z0-9_]*$/#) == nil {
            return "Must be a valid Swift type name (e.g. MyApp)."
        }
        return nil
    }

    static func targetDirectory(_ value: String) -> String? {
        let path = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if path.isEmpty { return "Choose a project directory." }
        var isDir: ObjCBool = false
        let fm = FileManager.default
        if fm.fileExists(atPath: path, isDirectory: &isDir) {
            if !isDir.boolValue { return "That path is a file, not a directory." }
            let entries = (try? fm.contentsOfDirectory(atPath: path)) ?? []
            if !entries.isEmpty {
                return "Directory is not empty — choose an empty directory or create a new folder."
            }
        }
        return nil
    }

    static func sdkPackage(_ value: String) -> String? {
        let path = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if path.isEmpty {
            return "Locate the local @swiftcode/sdk package directory (SwiftCode/SDK/TypeScript/package in a checkout)."
        }
        do {
            try ScaffoldEngine.validateSDKPackage(at: path)
        } catch let error as ScaffoldError {
            return error.message
        } catch {
            return error.localizedDescription
        }
        return nil
    }
}

// MARK: - ScaffoldError

private enum ScaffoldError: Error {
    case targetNotEmpty(path: String)
    case writeFailed(path: String, underlying: Error)
    case invalidSDKPackage(path: String, reason: String)

    var message: String {
        switch self {
        case .targetNotEmpty(let path):
            return "The directory \(path) already exists and is not empty. Choose an empty directory or create a new folder."
        case .writeFailed(let path, let underlying):
            let where_ = path.isEmpty ? "the project" : path
            return "Failed to write \(where_): \(underlying.localizedDescription)"
        case .invalidSDKPackage(let path, let reason):
            return "Invalid SDK package at \(path): \(reason)."
        }
    }
}

// MARK: - TemplateFile

/// One file in an embedded template. `path` and `content` both undergo
/// placeholder substitution; `isJSON` selects JSON-escaped substitution
/// values so quotes and newlines in names/descriptions cannot break the
/// generated JSON (a deliberate hardening over the .mjs generator, which
/// substitutes raw).
private struct SDKTemplateFile {
    let path: String
    let content: String
    let isJSON: Bool
}

// MARK: - ScaffoldEngine

/// Native project scaffolding. Writes the embedded templates to disk with
/// placeholder substitution — the Swift equivalent of
/// SwiftCode/SDK/TypeScript/cli/create-extension.mjs, without requiring
/// node or the source tree at runtime.
private enum ScaffoldEngine {

    // MARK: Entry points

    static func scaffoldExtension(
        values: [String: String],
        target: URL,
        progress: (String) -> Void
    ) throws -> [String] {
        guard let id = values["id"], !id.isEmpty,
              let name = values["name"], !name.isEmpty,
              let version = values["version"], !version.isEmpty else {
            throw ScaffoldError.writeFailed(path: "", underlying: ScaffoldEngine.missingValuesError())
        }
        let description = values["description"] ?? ""
        let sdkPackageDir = (values["sdkPackage"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        try validateSDKPackage(at: sdkPackageDir)

        // id-slug: last DNS label of the id, lowercased — the npm package
        // name, exactly as create-extension.mjs derives it.
        let idSlug = id.split(separator: ".").last.map(String.init) ?? id
        let sdkFileURL = URL(fileURLWithPath: sdkPackageDir, isDirectory: true).absoluteString

        let rawSubs: [(String, String)] = [
            ("__EXTENSION_ID__", id),
            ("__EXTENSION_NAME__", name),
            ("__EXTENSION_VERSION__", version),
            ("__EXTENSION_DESCRIPTION__", description),
            ("__ID_SLUG__", idSlug.lowercased()),
            ("__SDK_FILE_URL__", sdkFileURL),
        ]
        let jsonSubs: [(String, String)] = rawSubs.map { ($0.0, jsonEscaped($0.1)) }
        return try writeFiles(extensionTemplateFiles, substitutions: rawSubs, jsonSubstitutions: jsonSubs, to: target, progress: progress)
    }

    static func scaffoldTypeScriptProject(
        values: [String: String],
        target: URL,
        progress: (String) -> Void
    ) throws -> [String] {
        guard let name = values["name"], !name.isEmpty,
              let slug = values["slug"], !slug.isEmpty,
              let version = values["version"], !version.isEmpty else {
            throw ScaffoldError.writeFailed(path: "", underlying: ScaffoldEngine.missingValuesError())
        }
        let description = values["description"] ?? ""
        let rawSubs: [(String, String)] = [
            ("__PROJECT_NAME__", name),
            ("__PROJECT_DESCRIPTION__", description),
            ("__PACKAGE_SLUG__", slug),
            ("__PROJECT_VERSION__", version),
        ]
        let jsonSubs: [(String, String)] = rawSubs.map { ($0.0, jsonEscaped($0.1)) }
        return try writeFiles(typeScriptProjectTemplateFiles, substitutions: rawSubs, jsonSubstitutions: jsonSubs, to: target, progress: progress)
    }

    static func scaffoldSwiftProject(
        values: [String: String],
        target: URL,
        progress: (String) -> Void
    ) throws -> [String] {
        guard let appName = values["name"], !appName.isEmpty,
              let bundleID = values["bundleId"], !bundleID.isEmpty else {
            throw ScaffoldError.writeFailed(path: "", underlying: ScaffoldEngine.missingValuesError())
        }
        // __ORGANIZATION__ is derived from the bundle ID (everything before the
        // last dot label), per the Standalone-Swift token contract: the README
        // instructs "Organization Identifier: __ORGANIZATION__ → the bundle
        // identifier becomes __BUNDLE_ID__".
        let organization: String = {
            var parts = bundleID.split(separator: ".")
            if parts.count > 1 {
                parts.removeLast()
            }
            return parts.joined(separator: ".")
        }()
        // No JSON files in this scaffold, so raw substitution everywhere.
        let subs: [(String, String)] = [
            ("__APP_NAME__", appName),
            ("__BUNDLE_ID__", bundleID),
            ("__ORGANIZATION__", organization),
        ]
        return try writeFiles(swiftProjectTemplateFiles, substitutions: subs, jsonSubstitutions: subs, to: target, progress: progress)
    }

    // MARK: SDK package resolution

    /// Locates the local @swiftcode/sdk package directory, mirroring the
    /// --sdk-path default of create-extension.mjs for the app context.
    ///
    /// Resolution order:
    /// 1. `swiftcode-sdk` resource directory inside the app bundle
    ///    containing package.json (the future packaging step).
    /// 2. `SWIFTCODE_SDK_PACKAGE` environment variable (tilde-expanded),
    ///    the dev escape hatch — same precedent as SWIFTCODE_NODE_PATH.
    ///
    /// Returns "" when nothing resolves; the wizard then requires the user
    /// to pick the directory explicitly instead of generating a broken
    /// package.json.
    static func defaultSDKPackageDir() -> String {
        let fm = FileManager.default
        if let resource = Bundle.main.resourceURL?.appendingPathComponent("SwiftCodeSDK/TypeScript/package"),
           fm.fileExists(atPath: resource.appendingPathComponent("package.json").path) {
            return resource.path
        }
        if let env = ProcessInfo.processInfo.environment["SWIFTCODE_SDK_PACKAGE"],
           !env.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let expanded = (env as NSString).expandingTildeInPath
            if fm.fileExists(atPath: (expanded as NSString).appendingPathComponent("package.json")) {
                return expanded
            }
        }
        let installed = SDKInstaller.defaultPrefix.appendingPathComponent("node_modules/@swiftcode/sdk")
        if case .ok = SDKInstaller.inspect() { return installed.path }
        return ""
    }

    /// Verifies the directory holds a package.json naming @swiftcode/sdk —
    /// the same check create-extension.mjs performs on --sdk-path.
    static func validateSDKPackage(at path: String) throws {
        let pkgURL = URL(fileURLWithPath: path).appendingPathComponent("package.json")
        guard let data = try? Data(contentsOf: pkgURL),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let name = obj["name"] as? String else {
            throw ScaffoldError.invalidSDKPackage(path: path, reason: "no readable package.json")
        }
        guard name == "@swiftcode/sdk" else {
            throw ScaffoldError.invalidSDKPackage(path: path, reason: "package.json names \"\(name)\", not \"@swiftcode/sdk\"")
        }
    }

    // MARK: File writing

    static func writeFiles(
        _ files: [SDKTemplateFile],
        substitutions: [(String, String)],
        jsonSubstitutions: [(String, String)],
        to target: URL,
        progress: (String) -> Void
    ) throws -> [String] {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        if fm.fileExists(atPath: target.path, isDirectory: &isDir) {
            guard isDir.boolValue else {
                throw ScaffoldError.targetNotEmpty(path: target.path)
            }
            let entries = (try? fm.contentsOfDirectory(atPath: target.path)) ?? []
            if !entries.isEmpty {
                throw ScaffoldError.targetNotEmpty(path: target.path)
            }
        }
        var written: [String] = []
        // Containment anchor: no template path may escape the target
        // directory, even after placeholder substitution. All current
        // template paths are static literals, so this is defense in depth
        // against a future template that puts a placeholder in a path.
        let targetPath = target.standardizedFileURL.path
        for file in files {
            let subs = file.isJSON ? jsonSubstitutions : substitutions
            let relativePath = applySubstitutions(subs, to: file.path)
            let content = applySubstitutions(subs, to: file.content)
            let url = target.appendingPathComponent(relativePath)
            let resolvedPath = url.standardizedFileURL.path
            guard resolvedPath == targetPath || resolvedPath.hasPrefix(targetPath + "/") else {
                throw ScaffoldError.writeFailed(
                    path: relativePath,
                    underlying: NSError(
                        domain: "SDKStudio.Scaffold",
                        code: 2,
                        userInfo: [NSLocalizedDescriptionKey: "A template path escapes the target directory."]
                    )
                )
            }
            do {
                try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: nil)
                try content.write(to: url, atomically: true, encoding: .utf8)
            } catch {
                throw ScaffoldError.writeFailed(path: relativePath, underlying: error)
            }
            written.append(relativePath)
            progress(relativePath)
        }
        return written
    }

    static func applySubstitutions(_ subs: [(String, String)], to text: String) -> String {
        var result = text
        for (placeholder, value) in subs {
            result = result.replacingOccurrences(of: placeholder, with: value)
        }
        return result
    }

    /// Minimal JSON string escaper for values substituted into .json
    /// template files.
    static func jsonEscaped(_ value: String) -> String {
        var out = ""
        out.reserveCapacity(value.count)
        for ch in value {
            switch ch {
            case "\\": out += "\\\\"
            case "\"": out += "\\\""
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            default:
                if let ascii = ch.asciiValue, ascii < 0x20 {
                    out += String(format: "\\u%04x", ascii)
                } else {
                    out.append(ch)
                }
            }
        }
        return out
    }

    private static func missingValuesError() -> Error {
        NSError(domain: "SDKStudio.Scaffold", code: 1, userInfo: [
            NSLocalizedDescriptionKey: "A required wizard value is missing."
        ])
    }

    // MARK: Embedded templates

    /// Faithful copies of SwiftCode/SDK/TypeScript/templates/extension-typescript/
    /// plus the manifest schema shipped beside every generated extension
    /// (the generator copies it from SwiftCode/SDK/Contracts/Manifest/).
    /// Template bodies are expanded from the real files at authoring time —
    /// see agent_notes.md.
    static let extensionTemplateFiles: [SDKTemplateFile] = [
        SDKTemplateFile(path: "swiftcode.json", content: #"""
{"$schema":"./schemas/swiftcode-extension-v1.schema.json","assist":{"requested":false},"capabilities":[{"id":"source-control.read","reason":"Display repository status and diffs."},{"id":"build.execute","reason":"Run builds through SwiftCode's managed build service."}],"contributes":{"commands":[{"id":"inspect-repository","title":"Inspect Repository"},{"id":"run-build","title":"Build Current Project"}]},"description":"__EXTENSION_DESCRIPTION__","id":"__EXTENSION_ID__","manifestVersion":1,"name":"__EXTENSION_NAME__","runtime":{"entrypoint":"dist/index.js","language":"typescript","minimumSwiftCodeVersion":"1.0.0"},"sdk":{"name":"@swiftcode/sdk","protocolVersion":1,"versionRange":"^1.0.0"},"type":"extension","version":"__EXTENSION_VERSION__"}
"""#, isJSON: true),
        SDKTemplateFile(path: "package.json", content: #"""
{"dependencies":{"@swiftcode/sdk":"__SDK_FILE_URL__"},"devDependencies":{"@types/node":"26.6.5","typescript":"7.0.2"},"name":"__ID_SLUG__","private":true,"scripts":{"build":"tsc -p tsconfig.json","test":"node --test","typecheck":"tsc --noEmit -p tsconfig.json"},"type":"module","version":"__EXTENSION_VERSION__"}
"""#, isJSON: true),
        SDKTemplateFile(path: "tsconfig.json", content: #"""
{"compilerOptions":{"declaration":true,"exactOptionalPropertyTypes":true,"module":"NodeNext","moduleResolution":"NodeNext","noUncheckedIndexedAccess":true,"outDir":"dist","rootDir":"src","skipLibCheck":true,"sourceMap":true,"strict":true,"target":"ES2022"},"exclude":["tests","dist","node_modules"],"include":["src/**/*.ts"]}
"""#, isJSON: true),
        SDKTemplateFile(path: "README.md", content: #"""
# __EXTENSION_NAME__

A SwiftCode TypeScript extension built with `@swiftcode/sdk`.

- **Capabilities:** `source-control.read`, `build.execute`
- **Commands:** `inspect-repository` (Inspect Repository), `run-build` (Build Current Project)
- **Assist:** not requested and not used (unavailable to extensions).

## Prerequisites

- Node.js 20+
- The SwiftCode host runtime (`swiftcode` CLI) — install/validate and dev
  commands below become available with the CLI phase of the SDK.

## Workflow

```sh
npm install     # install deps; @swiftcode/sdk resolves from the local SDK package
npm run build   # compile src/ → dist/ (must succeed before activation)
npm run typecheck  # strict type check without emitting
npm test        # run the manifest + extension test suites
```

`dist/index.js` is the runtime entrypoint declared in `swiftcode.json`
(`runtime.entrypoint`). The host activates the extension from the built
output — never from `src/` directly.

## Commands (arrive with the CLI phase)

The following scripts are part of the SDK CLI story; they are available
once the `swiftcode` CLI ships:

```sh
npx swiftcode validate   # validate swiftcode.json + package contents against the schema
npx swiftcode dev        # run the extension in development mode against a local host
npx swiftcode package    # package the extension for installation (spec §17)
```

Until the CLI lands, `validate` is covered by `npm test` (the manifest
suite checks capabilities, Assist posture, commands, and the entrypoint
against the shipped schema) and packaging/installation is not yet
implemented — do not invent a package format.

## Manifest

`swiftcode.json` declares the extension identity, capabilities, contributed
commands, and the SDK/protocol versions it was built against. The schema
pointer `$schema` resolves to `schemas/swiftcode-extension-v1.schema.json`,
which the generator copies into every generated project from
`SwiftCode/SDK/Contracts/Manifest/swiftcode-extension-v1.schema.json` —
a single source of truth, never a dead URL.

## Build targets

The `run-build` command calls `build.run({ target: "" })` with an empty
target: the host resolves the default scheme/build target of the currently
open SwiftCode project. The extension never hardcodes a target name that
might not exist in the user's project.

"""#, isJSON: false),
        SDKTemplateFile(path: "src/extension.ts", content: #"""
import type { SwiftCodeContext } from "@swiftcode/sdk";
import { createInspectRepositoryCommand } from "./commands/inspect-repository.js";
import { createRunBuildCommand } from "./commands/run-build.js";

/**
 * Live command registrations owned by this activation. Every registration is
 * disposed when the extension deactivates, and also unwound if activation
 * fails partway through, so a partially-initialized extension never leaves
 * commands behind.
 */
const registrations: Array<{ dispose(): void }> = [];

export async function activate(context: SwiftCodeContext): Promise<void> {
  try {
    registrations.push(context.commands.register(createInspectRepositoryCommand(context)));
    registrations.push(context.commands.register(createRunBuildCommand(context)));
  } catch (error) {
    for (const registration of registrations.splice(0)) {
      registration.dispose();
    }
    throw error;
  }
}

export async function deactivate(): Promise<void> {
  for (const registration of registrations.splice(0)) {
    registration.dispose();
  }
}

"""#, isJSON: false),
        SDKTemplateFile(path: "src/index.ts", content: #"""
import type { SwiftCodeExtension } from "@swiftcode/sdk";
import { activate, deactivate } from "./extension.js";

const extension: SwiftCodeExtension = {
  id: "__EXTENSION_ID__",
  activate,
  deactivate,
};

export default extension;

"""#, isJSON: false),
        SDKTemplateFile(path: "src/commands/inspect-repository.ts", content: #"""
import type { SwiftCodeContext } from "@swiftcode/sdk";

/**
 * "inspect-repository" command.
 *
 * Fetches the live repository status from the host's source-control service,
 * logs a summary, and returns the status object unchanged. No data is
 * fabricated: the caller receives exactly what the host reports.
 */
export function createInspectRepositoryCommand(context: SwiftCodeContext) {
  return {
    id: "inspect-repository",
    title: "Inspect Repository",
    execute: async () => {
      const status = await context.sourceControl.getStatus();
      context.log.info("Repository status retrieved", {
        isRepository: status.isRepository,
      });
      return status;
    },
  };
}

"""#, isJSON: false),
        SDKTemplateFile(path: "src/commands/run-build.ts", content: #"""
import type { SwiftCodeContext } from "@swiftcode/sdk";

/**
 * "run-build" command.
 *
 * Starts a host-managed build and streams its output events to the extension
 * log, then awaits the final build result.
 *
 * Convention: an empty `target` string asks the host to resolve the default
 * scheme/build target of the currently open SwiftCode project. The extension
 * deliberately never hardcodes a target name that might not exist in the
 * user's project — if the host cannot resolve a default, `run()` rejects
 * with a typed build error and the rejection propagates to the caller.
 */
export function createRunBuildCommand(context: SwiftCodeContext) {
  return {
    id: "run-build",
    title: "Build Current Project",
    execute: async () => {
      const handle = await context.build.run({ target: "" });
      // BuildOutputEvent.text (spec §12.4's illustrative `message` became `text`
      // in the finalized @swiftcode/sdk contract, mirroring the host's
      // SDKBuildOutputEvent.text). No output is fabricated or dropped: every
      // streamed event is logged, and stream consumption does not affect wait().
      for await (const event of handle.output) {
        context.log.info(event.text);
      }
      return await handle.wait();
    },
  };
}

"""#, isJSON: false),
        SDKTemplateFile(path: "tests/extension.test.mjs", content: #"""
// Extension lifecycle tests — run with `node --test tests/` AFTER `npm run build`.
// Loads the real compiled dist/index.js and exercises activate/deactivate
// through a recording test harness (test double at the unit-test boundary,
// per spec §12.5 — the extension code under test is the real compiled code).
import { describe, it } from "node:test";
import assert from "node:assert/strict";
import { pathToFileURL, fileURLToPath } from "node:url";
import path from "node:path";

const root = path.dirname(path.dirname(fileURLToPath(import.meta.url)));
const extensionUrl = pathToFileURL(path.join(root, "dist", "index.js")).href;
const { default: extension } = await import(extensionUrl);

// Minimal harness shaped like the host's SwiftCodeContext surface used here:
// commands.register records and returns a disposable; other surfaces throw
// so any accidental call to an unimplemented surface fails loudly.
function makeContext() {
  const disposed = [];
  const registered = [];
  return {
    disposed,
    registered,
    context: {
      commands: {
        register(command) {
          registered.push(command);
          return {
            dispose() {
              disposed.push(command.id);
            },
          };
        },
      },
      sourceControl: {
        getStatus() {
          throw new Error("getStatus must not run in lifecycle tests");
        },
      },
      build: {
        run() {
          throw new Error("build.run must not run in lifecycle tests");
        },
      },
      log: { info() {} },
    },
  };
}

describe("extension", () => {
  it("default export carries id, activate, deactivate", () => {
    assert.equal(typeof extension.id, "string");
    assert.ok(extension.id.length > 0);
    assert.equal(typeof extension.activate, "function");
    assert.equal(typeof extension.deactivate, "function");
  });

  it("activate registers inspect-repository and run-build", async () => {
    const { context, registered } = makeContext();
    await extension.activate(context);
    assert.deepEqual(
      registered.map((c) => c.id),
      ["inspect-repository", "run-build"]
    );
    for (const command of registered) {
      assert.equal(typeof command.execute, "function");
    }
    await extension.deactivate(); // leave a clean slate for other tests
  });

  it("deactivate disposes every registration", async () => {
    const { context, disposed } = makeContext();
    await extension.activate(context);
    await extension.deactivate();
    assert.deepEqual(disposed.sort(), ["inspect-repository", "run-build"]);
  });

  it("a partial activation failure unwinds registrations and rethrows", async () => {
    const first = makeContext();
    const { context } = first;
    let calls = 0;
    const failing = {
      ...context,
      commands: {
        register(command) {
          calls += 1;
          if (calls === 2) throw new Error("registration failed");
          return context.commands.register(command);
        },
      },
    };
    await assert.rejects(() => extension.activate(failing), /registration failed/);
    assert.deepEqual(first.disposed, ["inspect-repository"]);
  });
});

// Working harness for the command handlers: records every call the handlers
// make against the host API surface, so the tests prove the handlers use the
// real contract (method names, payload shapes, streaming iteration).
function makeLiveContext({ status, buildResult, buildEvents }) {
  const calls = { getStatus: 0, run: [], logged: [] };
  const registered = [];
  const context = {
    commands: {
      register(command) {
        registered.push(command);
        return { dispose() {} };
      },
    },
    sourceControl: {
      async getStatus() {
        calls.getStatus += 1;
        return status;
      },
    },
    build: {
      async run(request) {
        calls.run.push(request);
        const events = (async function* () {
          for (const event of buildEvents) yield event;
        })();
        return {
          id: "handle-1",
          output: events,
          async wait() {
            return buildResult;
          },
          async cancel() {},
        };
      },
    },
    log: {
      info(message, fields) {
        calls.logged.push([message, fields]);
      },
    },
  };
  return { context, registered, calls };
}

describe("command handlers", () => {
  it("inspect-repository returns the host status unchanged and logs isRepository", async () => {
    const status = {
      isRepository: true,
      branchName: "main",
      ahead: 0,
      behind: 0,
      stagedCount: 1,
      unstagedCount: 0,
      untrackedCount: 0,
      files: [],
    };
    const { context, registered, calls } = makeLiveContext({
      status,
      buildResult: null,
      buildEvents: [],
    });
    await extension.activate(context);
    const command = registered.find((c) => c.id === "inspect-repository");
    const result = await command.execute();
    assert.equal(calls.getStatus, 1);
    assert.equal(result, status); // no fabrication: the host object is returned as-is
    assert.deepEqual(calls.logged, [["Repository status retrieved", { isRepository: true }]]);
    await extension.deactivate();
  });

  it("run-build uses host-resolved default target, streams output, returns wait()", async () => {
    const buildResult = {
      status: "succeeded",
      durationSeconds: 1.2,
      errorCount: 0,
      warningCount: 0,
      diagnostics: [],
      correlationId: "corr-1",
    };
    const buildEvents = [
      { kind: "stdout", text: "Compiling…", timestamp: 1 },
      { kind: "status", text: "Build succeeded", timestamp: 2 },
    ];
    const { context, registered, calls } = makeLiveContext({
      status: null,
      buildResult,
      buildEvents,
    });
    await extension.activate(context);
    const command = registered.find((c) => c.id === "run-build");
    const result = await command.execute();
    // Empty target = host resolves the default scheme of the open project.
    assert.deepEqual(calls.run, [{ target: "" }]);
    assert.deepEqual(
      calls.logged.map(([message]) => message),
      ["Compiling…", "Build succeeded"]
    );
    assert.equal(result, buildResult);
    await extension.deactivate();
  });
});

"""#, isJSON: false),
        SDKTemplateFile(path: "tests/manifest.test.mjs", content: #"""
// Manifest contract tests — run with `node --test tests/` AFTER `npm run build`.
// Reads the real swiftcode.json and asserts the Phase-1 capability set and
// Assist posture required of every generated extension.
import { describe, it } from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { existsSync } from "node:fs";
import { fileURLToPath } from "node:url";
import path from "node:path";

const root = path.dirname(path.dirname(fileURLToPath(import.meta.url)));
const manifestPath = path.join(root, "swiftcode.json");
const schemaPath = path.join(root, "schemas", "swiftcode-extension-v1.schema.json");

const manifest = JSON.parse(await readFile(manifestPath, "utf8"));
const schema = JSON.parse(await readFile(schemaPath, "utf8"));
const knownCapabilityIds = new Set(schema.properties.capabilities.items.properties.id.enum);

describe("manifest", () => {
  it("declares exactly source-control.read and build.execute", () => {
    const ids = manifest.capabilities.map((c) => c.id);
    assert.deepEqual(ids, ["source-control.read", "build.execute"]);
  });

  it("does not request Assist", () => {
    assert.equal(manifest.assist.requested, false);
  });

  it("contributes exactly inspect-repository and run-build", () => {
    const ids = manifest.contributes.commands.map((c) => c.id);
    assert.deepEqual(ids, ["inspect-repository", "run-build"]);
  });

  it("every capability id is a real, grantable registry id from the shipped schema", () => {
    for (const cap of manifest.capabilities) {
      assert.ok(knownCapabilityIds.has(cap.id), `unknown capability id: ${cap.id}`);
      assert.notEqual(cap.id, "assist.invoke");
    }
  });

  it("entrypoint resolves to a file that exists (after npm run build)", () => {
    assert.equal(manifest.runtime.entrypoint, "dist/index.js");
    assert.ok(
      existsSync(path.join(root, manifest.runtime.entrypoint)),
      `entrypoint missing: ${manifest.runtime.entrypoint} — run npm run build first`
    );
  });

  it("id, name, version are consistent between manifest and package.json", async () => {
    const pkg = JSON.parse(await readFile(path.join(root, "package.json"), "utf8"));
    assert.equal(manifest.version, pkg.version);
    assert.ok(/^[A-Za-z][A-Za-z0-9-]*(\.[A-Za-z][A-Za-z0-9-]*)+$/.test(manifest.id));
  });
});

"""#, isJSON: false),
        SDKTemplateFile(path: "schemas/swiftcode-extension-v1.schema.json", content: #"""
{"$schema":"https://json-schema.org/draft/2020-12/schema","additionalProperties":false,"description":"JSON Schema for swiftcode.json (manifestVersion 1). This schema is the formalization of Docs/Intro-to-SDK.md §7 and the fixed Phase 1 decisions in SwiftCode/SDK/Documentation/SDK-Architecture.md (capability IDs ADR §7, error codes ADR §8). Forward compatibility is handled by explicit new schema versions (manifestVersion 2, new file), NOT by silent extra fields: additionalProperties is false at the top level and on capability/command objects. Constraints that cannot be expressed in draft 2020-12 (duplicate capability/command ids, entrypoint file existence, package-level checks from spec §7.2) are enforced by the strict manifest/package validator (Phase 1 work item P1b), not by this schema.","properties":{"$schema":{"description":"Pointer to the schema this manifest was authored against. In a packaged extension this MUST point to the schema file shipped with the SDK inside the extension package (e.g. \"./schemas/swiftcode-extension-v1.schema.json\") or a verified official URL. Dead URLs are rejected at install time per spec §7.1.","type":"string"},"assist":{"additionalProperties":false,"description":"Assist-related declaration. DESCRIPTIVE METADATA ONLY in this release: a manifest \"assist\": {\"requested\": true} does NOT grant Assist access. Assist is unavailable to extensions, period (ADR §9): any assist.invoke request -> typed ASSIST_DENIED + audit event. The future Assist authorization flow is not implemented and no dormant bypass is added.","properties":{"requested":{"description":"Whether the extension declares interest in Assist capabilities. False for the first extension.","type":"boolean"}},"required":["requested"],"type":"object"},"capabilities":{"description":"Capability grant requests. A valid manifest is a request, not an authorization token: each id still requires an explicit user grant via the CapabilityBroker, and unknown ids are rejected with UNKNOWN_CAPABILITY (never silently reinterpreted). Duplicate ids are rejected by the host validator; this schema cannot express per-property uniqueness inside arrays.","items":{"additionalProperties":false,"properties":{"id":{"description":"Capability IDs fixed for Phase 1+ (ADR §7; semantics per spec §8.1). No other ids may appear. Note: \"assist.invoke\" is never grantable in this release (any request -> ASSIST_DENIED + audit event).","enum":["project.read","workspace.read","workspace.write","source-control.read","source-control.write","build.execute","task.execute","network.request","ui.contribute","credentials.use","assist.invoke"],"type":"string"},"reason":{"description":"Non-empty, plain-language justification shown to the user in the grant approval UI.","maxLength":500,"minLength":1,"type":"string"}},"required":["id","reason"],"type":"object"},"maxItems":32,"minItems":1,"type":"array"},"contributes":{"additionalProperties":false,"description":"UI contributions. In this release only the command model is supported (no arbitrary native UI injection). Today's CommandPaletteView.CommandAction enum is closed, so command contributions need a new open registry on the host side.","properties":{"commands":{"description":"Contributed commands. Command ids must be unique within the array; uniqueness is enforced by the host validator (not expressible per-property in this draft).","items":{"additionalProperties":false,"properties":{"id":{"description":"Machine identifier for the command, lowercase alphanumeric plus hyphens.","maxLength":64,"pattern":"^[a-z0-9-]+$","type":"string"},"title":{"description":"Human-readable command title shown in the UI.","maxLength":128,"minLength":1,"type":"string"}},"required":["id","title"],"type":"object"},"maxItems":64,"minItems":1,"type":"array"}},"required":["commands"],"type":"object"},"description":{"maxLength":1000,"type":"string"},"id":{"description":"Reverse-DNS extension identifier, e.g. \"com.example.repository-build-extension\". Used as the install-directory name and the identity bound to the runtime session; extension-supplied identity is never trusted beyond this validated value.","maxLength":128,"pattern":"^[A-Za-z][A-Za-z0-9-]*(\\.[A-Za-z][A-Za-z0-9-]*)+$","type":"string"},"manifestVersion":{"const":1,"description":"Manifest schema generation. This file defines generation 1. Unsupported generations are rejected with MANIFEST_UNSUPPORTED_VERSION.","type":"integer"},"name":{"maxLength":128,"minLength":1,"type":"string"},"runtime":{"additionalProperties":false,"properties":{"entrypoint":{"description":"Path of the entrypoint file RELATIVE to the package root. Must not be absolute and must not contain \"..\" segments; escaping the package root is rejected with PATH_TRAVERSAL. Existence inside the validated package is checked at install time (schema cannot check the filesystem).","maxLength":256,"pattern":"^(?![/\\\\])(?!.*\\.\\.)[^\\x00]+$","type":"string"},"language":{"description":"Only TypeScript extensions are supported in this release (Python deferred per ADR §12).","enum":["typescript"],"type":"string"},"minimumSwiftCodeVersion":{"description":"Minimum host SwiftCode version this extension requires (semver).","maxLength":64,"pattern":"^(0|[1-9]\\d*)\\.(0|[1-9]\\d*)\\.(0|[1-9]\\d*)(-((0|[1-9]\\d*|\\d*[a-zA-Z-][0-9a-zA-Z-]*)(\\.(0|[1-9]\\d*|\\d*[a-zA-Z-][0-9a-zA-Z-]*))*))?(\\+([0-9a-zA-Z-]+(\\.[0-9a-zA-Z-]+)*))?$","type":"string"}},"required":["language","entrypoint","minimumSwiftCodeVersion"],"type":"object"},"sdk":{"additionalProperties":false,"properties":{"name":{"const":"@swiftcode/sdk","description":"The SDK package name this extension is built against.","type":"string"},"protocolVersion":{"const":1,"description":"Host/runtime IPC contract version. Mismatches are rejected with IPC_PROTOCOL_MISMATCH.","type":"integer"},"versionRange":{"description":"npm-style semver range for the SDK version, e.g. \"^1.0.0\". Incompatible ranges are rejected with INCOMPATIBLE_SDK_VERSION. This schema checks the character set only; real range satisfaction is evaluated by the host validator.","maxLength":64,"minLength":1,"pattern":"^[\\^~>=<\\d\\.\\-xX\\*\\|\\s,]+$","type":"string"}},"required":["name","versionRange","protocolVersion"],"type":"object"},"type":{"const":"extension","description":"Reserved for future package kinds (themes, plugins, ...). Only \"extension\" exists in v1.","type":"string"},"version":{"description":"Full semver 2.0.0 of the extension package.","maxLength":64,"pattern":"^(0|[1-9]\\d*)\\.(0|[1-9]\\d*)\\.(0|[1-9]\\d*)(-((0|[1-9]\\d*|\\d*[a-zA-Z-][0-9a-zA-Z-]*)(\\.(0|[1-9]\\d*|\\d*[a-zA-Z-][0-9a-zA-Z-]*))*))?(\\+([0-9a-zA-Z-]+(\\.[0-9a-zA-Z-]+)*))?$","type":"string"}},"required":["manifestVersion","id","name","version","type","runtime","sdk","capabilities"],"title":"SwiftCode Extension Manifest","type":"object"}
"""#, isJSON: false),
    ]

    /// Faithful copies of SwiftCode/SDK/TypeScript/templates/project-typescript/.
    static let typeScriptProjectTemplateFiles: [SDKTemplateFile] = [
        SDKTemplateFile(path: "package.json", content: #"""
{"dependencies":{},"description":"__PROJECT_DESCRIPTION__","devDependencies":{"@types/node":"26.6.5","typescript":"7.0.2"},"name":"__PACKAGE_SLUG__","private":true,"scripts":{"build":"tsc -p tsconfig.json","test":"node --test","typecheck":"tsc --noEmit -p tsconfig.json"},"type":"module","version":"__PROJECT_VERSION__"}
"""#, isJSON: true),
        SDKTemplateFile(path: "tsconfig.json", content: #"""
{"compilerOptions":{"declaration":true,"exactOptionalPropertyTypes":true,"module":"NodeNext","moduleResolution":"NodeNext","noUncheckedIndexedAccess":true,"outDir":"dist","rootDir":"src","skipLibCheck":true,"sourceMap":true,"strict":true,"target":"ES2022","types":["node"]},"exclude":["tests","dist","node_modules"],"include":["src/**/*.ts"]}
"""#, isJSON: true),
        SDKTemplateFile(path: "README.md", content: #"""
# __PROJECT_NAME__

SwiftCode standalone TypeScript project (spec §14.1). User-owned code using
the ordinary Node.js workflow.

__PROJECT_DESCRIPTION__

## Develop

```sh
npm install     # install dev dependencies (typescript, @types/node)
npm run build   # compile src/ -> dist/
npm run typecheck
npm test        # run tests (build first)
node dist/index.js
```

TypeScript `7.0.2` and `@types/node` `26.6.5` are pinned in `package.json`.

"""#, isJSON: false),
        SDKTemplateFile(path: "src/index.ts", content: #"""
/**
 * __PROJECT_NAME__ — SwiftCode standalone TypeScript project.
 *
 * A standalone project is user-owned code: it uses the language's ordinary
 * development workflow (npm / tsc / node) and is not subject to extension
 * sandbox restrictions (spec §14.1).
 */
import { createRequire } from "node:module";
import { pathToFileURL } from "node:url";

// createRequire keeps this working under NodeNext ESM without needing
// resolveJsonModule; the name always reflects the real package.json.
const require = createRequire(import.meta.url);
const pkg = require("../package.json") as { name?: string; version?: string };

export function greeting(): string {
  return `Hello from ${pkg.name ?? "swiftcode-project"} v${pkg.version ?? "0.0.0"}!`;
}

export function main(): void {
  console.log(greeting());
}

// Run only when executed directly (`node dist/index.js`), not when imported
// by the test suite.
if (process.argv[1] !== undefined) {
  const entryUrl = pathToFileURL(process.argv[1]).href;
  if (import.meta.url === entryUrl) {
    main();
  }
}

"""#, isJSON: false),
        SDKTemplateFile(path: "tests/hello.test.mjs", content: #"""
/**
 * hello.test.mjs — smoke test for the generated standalone project.
 *
 * Runs the compiled entry point for real and asserts its output contains
 * the package name read from the real package.json. Bare `node --test`
 * (see package.json) discovers this file; the entry point must be built
 * (`npm run build`) before `npm test`.
 */
import { describe, it } from "node:test";
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { readFileSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const root = path.dirname(path.dirname(fileURLToPath(import.meta.url)));
const pkg = JSON.parse(readFileSync(path.join(root, "package.json"), "utf8"));
const entry = path.join(root, "dist", "index.js");

function escapeRegExp(s) {
  return s.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}

describe("standalone project", () => {
  it("entry point runs and prints a hello containing the package name", () => {
    const res = spawnSync(process.execPath, [entry], { encoding: "utf8" });
    assert.equal(res.status, 0, `dist/index.js exited ${res.status}: ${res.stderr}`);
    assert.match(res.stdout, new RegExp(escapeRegExp(pkg.name)));
  });

  it("greeting() reflects the package name and version", async () => {
    const mod = await import(entry);
    const expected = `Hello from ${pkg.name} v${pkg.version}!`;
    assert.equal(mod.greeting(), expected);
  });
});

"""#, isJSON: false),
    ]

    /// Standalone-Swift template (SwiftCode/SDK/Templates/Standalone-Swift/).
    /// Token contract (see SwiftCode/SDK/Templates/agent_notes.md): __APP_NAME__,
    /// __BUNDLE_ID__, __ORGANIZATION__ — literal substitution across every file;
    /// template.json is wizard metadata and is NOT copied into the project.
    static let swiftProjectTemplateFiles: [SDKTemplateFile] = [
        SDKTemplateFile(path: "App.swift", content: #"""
import SwiftUI

@main
struct __APP_NAME__App: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

"""#, isJSON: false),
        SDKTemplateFile(path: "ContentView.swift", content: #"""
import SwiftUI

struct ContentView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "app.fill")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("__APP_NAME__")
                .font(.title)
            Text("A SwiftCode standalone project. This is your own code — build, sign, and ship it with the normal Xcode workflow.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
        .frame(minWidth: 380, minHeight: 240)
    }
}

#Preview {
    ContentView()
}

"""#, isJSON: false),
        SDKTemplateFile(path: "README.md", content: #"""
# __APP_NAME__

A standalone macOS app scaffold created with the SwiftCode SDK (SwiftCode SDK §14.1).
This is **your own code** — the SDK only provided this starting template. There are no
extension-style sandbox restrictions on a standalone project; build, sign, and distribute
it exactly like any other native Mac app.

## Open / build / run

### In Xcode (recommended)

1. Create a new macOS App project: **File → New → Project → macOS → App**.
2. Product Name: `__APP_NAME__`; Organization Identifier: `__ORGANIZATION__` →
   the bundle identifier becomes `__BUNDLE_ID__`.
3. Language: Swift, Interface: SwiftUI. Uncheck the options you don't need (tests are fine).
4. Replace the generated files with `App.swift` and `ContentView.swift` from this folder.
5. Build and run with **⌘R**.

### From the terminal

```sh
# List schemes once the .xcodeproj exists
xcodebuild -list -project __APP_NAME__.xcodeproj

# Build
xcodebuild -project __APP_NAME__.xcodeproj -scheme __APP_NAME__ -configuration Debug build

# Run the built app
open "build/Debug/__APP_NAME__.app"
```

## What to change first

1. **App structure** — `App.swift` is the `@main` entry point. Rename the struct freely;
   only the `@main` attribute and the `Scene` body matter.
2. **Main view** — `ContentView.swift` holds the starter view. Replace its body with your
   real UI; native macOS conventions (toolbar, sidebar, menus) apply as usual.
3. **App identity** — bundle ID `__BUNDLE_ID__` and the version/marketing fields live in
   your Xcode target (Signing & Capabilities), not in these source files.
4. **Entitlements** — add an entitlements file only if your app needs sandbox capabilities
   (network client, files, etc.); a plain app needs none.
5. **Assets** — replace the system icon with real app icons in `Assets.xcassets`.

## Notes

- Requires macOS 14+ and a current Xcode with the Swift toolchain.
- This template is deliberately minimal: two Swift files and no asset catalogs or
  entitlements. Add Swift packages, menus, or persistence the way you normally would.

"""#, isJSON: false),
        SDKTemplateFile(path: ".gitignore", content: #"""
# macOS / Xcode

build/
DerivedData/
*.pbxuser
*.mode1v3
*.mode2v3
*.perspectivev3
*.xccheckout
xcuserdata/
*.moved-aside
*.xcuserstate
*.xcscmblueprint
*.xcsettings

# Swift Package Manager

.swiftpm/
.build/
Packages/

# Xcode generated

*.dSYM.zip
*.dSYM

# macOS

.DS_Store
.AppleDouble
.LSOverride
._*
.Spotlight-V100
.Trashes

"""#, isJSON: false),
    ]
}
