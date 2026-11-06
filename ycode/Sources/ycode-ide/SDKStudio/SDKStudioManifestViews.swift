import Foundation
import SwiftUI
import YcodeExtensions
import YcodeSDKStudio

// MARK: - Manifest capability categories
//
// Legacy: `SDKManifestEditorView.swift` / `SDKManifestInspectorView.swift`
// filter the 35 canonical capabilities into All / Enabled Only / Project /
// Source Control / Build / UI & Views / Security & AI.

enum SDKManifestCapabilityCategory: String, CaseIterable {
    case all = "All"
    case enabledOnly = "Enabled Only"
    case project = "Project"
    case sourceControl = "Source Control"
    case build = "Build"
    case ui = "UI & Views"
    case security = "Security & AI"

    func matches(_ capability: SDKCapabilityID, enabledIDs: Set<String>) -> Bool {
        switch self {
        case .all: return true
        case .enabledOnly: return enabledIDs.contains(capability.rawValue)
        case .project:
            return [.projectRead, .workspaceRead, .workspaceWrite, .docsSearch, .symbolsBrowse, .dictionaryOpen]
                .contains(capability)
        case .sourceControl:
            return capability == .sourceControlRead || capability == .sourceControlWrite
        case .build:
            return capability == .buildExecute || capability == .taskExecute || capability == .terminalSandbox
        case .ui:
            return [.uiContribute, .previewLive, .simulatorView, .uiBuilderOpen, .virtualizationView,
                    .deployConsoleView, .dbExploreView, .ciVisualWF, .deviceConnectOpen, .useSwiftCodeModel,
                    .sandboxView, .assistUI, .assistHeadless, .assistMainView].contains(capability)
        case .security:
            return capability.rawValue.hasPrefix("use.Security") || capability == .credentialsUse
                || capability == .networkRequest || capability == .assistInvoke
        }
    }
}

func sdkManifestRiskColor(_ riskLevel: String) -> Color {
    switch riskLevel {
    case "low": return .green
    case "medium": return .blue
    case "high": return .orange
    default: return .red
    }
}

// MARK: - Manifest editor
//
// Legacy: `SwiftCode/SDK/Studio/Views/SDKManifestEditorView.swift` (visual
// + raw editing of `swiftcode.json`, capability toggles with reasons,
// contributed commands, diagnostics, malformed-JSON fallback) and the
// editor half of `SDKManifestInspectorView.swift`. Edits go through
// Ycode's `SwiftCodeManifest` (unknown top-level keys preserved in
// `unknownFields`, so visual editing never destroys them) and validation
// is Ycode's strict `SwiftCodeManifestValidator`. "Pre-authorize" writes
// grants through the Studio grant seam (`SDKStudioGrantStore`), backed
// by the real `PermissionManager` by default.

@MainActor
struct SDKManifestEditorView: View {
    let manifestFileURL: URL?
    @Bindable var editorState: SDKCodeEditorState

    @State private var manifest: SwiftCodeManifest?
    @State private var rawText: String = ""
    @State private var showingRaw: Bool = false
    @State private var parseError: String?
    @State private var diagnostics: [ManifestDiagnostic] = []
    @State private var capabilitySearchQuery: String = ""
    @State private var selectedCategory: SDKManifestCapabilityCategory = .all
    @State private var isDirty: Bool = false
    @State private var statusBanner: String?
    @State private var newCommandID: String = ""
    @State private var newCommandTitle: String = ""
    @State private var grantedCapabilityIDs: Set<String> = []

    init(manifestFileURL: URL?, editorState: SDKCodeEditorState) {
        self.manifestFileURL = manifestFileURL
        self.editorState = editorState
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if let parseError {
                Text(parseError)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.red.opacity(0.1))
            }
            if let statusBanner {
                Text(statusBanner)
                    .font(.callout)
                    .foregroundStyle(.green)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.green.opacity(0.1))
            }
            if showingRaw {
                TextEditor(text: $rawText)
                    .font(.body.monospaced())
                    .onChange(of: rawText) { _, _ in
                        isDirty = true
                        recomputeDiagnostics()
                    }
            } else if let manifest {
                ScrollView {
                    visualEditor(manifest)
                        .padding()
                }
            } else {
                SDKStudioEmptyState(title: "No Manifest", systemImage: "doc.badge.gearshape", description: "Open a project with a swiftcode.json to edit its manifest.")
            }
            diagnosticsFooter
        }
        .task { loadFromDisk() }
        .onChange(of: manifestFileURL) { _, _ in loadFromDisk() }
    }

    private var header: some View {
        HStack {
            Text(manifestFileURL?.lastPathComponent ?? "swiftcode.json").font(.headline)
            if isDirty { Text("• Edited").font(.caption).foregroundStyle(.orange) }
            Spacer()
            Picker("Mode", selection: $showingRaw) {
                Text("Visual").tag(false)
                Text("Raw JSON").tag(true)
            }
            .pickerStyle(.segmented)
            .frame(width: 180)
            Button("Reload") { loadFromDisk() }
            Button("Save") { save() }
                .buttonStyle(.borderedProminent)
                .disabled(!isDirty || manifest == nil)
        }
        .padding(8)
    }

    private func visualEditor(_ manifest: SwiftCodeManifest) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            identitySection(manifest)
            runtimeSection(manifest)
            sdkSection(manifest)
            capabilitiesSection(manifest)
            commandsSection(manifest)
        }
    }

    private func identitySection(_ manifest: SwiftCodeManifest) -> some View {
        SDKStudioGroupBox("Extension Identity") {
            VStack(alignment: .leading, spacing: 8) {
                LabeledContent("ID") {
                    TextField("com.example.my-extension", text: binding(\.id))
                        .textFieldStyle(.roundedBorder)
                }
                LabeledContent("Name") {
                    TextField("Display name", text: binding(\.name))
                        .textFieldStyle(.roundedBorder)
                }
                LabeledContent("Version") {
                    TextField("1.0.0", text: binding(\.version))
                        .textFieldStyle(.roundedBorder)
                }
                LabeledContent("Description") {
                    TextField("What this extension does…", text: binding(\.description))
                        .textFieldStyle(.roundedBorder)
                }
                LabeledContent("Type") {
                    Picker("Type", selection: binding(\.type)) {
                        Text("extension").tag("extension")
                        Text("application").tag("application")
                    }
                    .pickerStyle(.menu)
                }
            }
        }
    }

    private func runtimeSection(_ manifest: SwiftCodeManifest) -> some View {
        SDKStudioGroupBox("Runtime") {
            VStack(alignment: .leading, spacing: 8) {
                LabeledContent("Language") {
                    Text(manifest.runtime.language)
                }
                LabeledContent("Entrypoint") {
                    TextField("dist/index.js", text: binding(\.runtime.entrypoint))
                        .textFieldStyle(.roundedBorder)
                }
                LabeledContent("Minimum SwiftCode") {
                    TextField("1.0.0", text: binding(\.runtime.minimumSwiftCodeVersion))
                        .textFieldStyle(.roundedBorder)
                }
            }
        }
    }

    private func sdkSection(_ manifest: SwiftCodeManifest) -> some View {
        SDKStudioGroupBox("SDK") {
            VStack(alignment: .leading, spacing: 8) {
                LabeledContent("Name") { Text(manifest.sdk.name) }
                LabeledContent("Version Range") {
                    TextField("^1.0.0", text: binding(\.sdk.versionRange))
                        .textFieldStyle(.roundedBorder)
                }
                LabeledContent("Protocol") { Text("\(manifest.sdk.protocolVersion)") }
            }
        }
    }

    private func capabilitiesSection(_ manifest: SwiftCodeManifest) -> some View {
        SDKStudioGroupBox("Capabilities & Permission Justifications (\(manifest.capabilities.count)/\(SDKCapabilityID.allCases.count))") {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    TextField("Filter capabilities by ID…", text: $capabilitySearchQuery)
                        .textFieldStyle(.roundedBorder)
                    Picker("Category", selection: $selectedCategory) {
                        ForEach(SDKManifestCapabilityCategory.allCases, id: \.self) { category in
                            Text(category.rawValue).tag(category)
                        }
                    }
                    .pickerStyle(.menu)
                }
                Text("\(manifest.capabilities.count) enabled")
                    .font(.caption).foregroundStyle(.secondary)
                ForEach(filteredCapabilities(manifest), id: \.rawValue) { capability in
                    capabilityRow(capability, manifest: manifest)
                }
                Button("Pre-authorize enabled capabilities") {
                    preauthorize(manifest: manifest)
                }
                .help("Pre-authorize all enabled manifest capabilities in the grant store for this extension ID")
                .disabled(manifest.capabilities.isEmpty)
            }
        }
    }

    private func capabilityRow(_ capability: SDKCapabilityID, manifest: SwiftCodeManifest) -> some View {
        let enabledIndex = manifest.capabilities.firstIndex(where: { $0.id == capability.rawValue })
        return HStack(alignment: .top, spacing: 8) {
            Toggle(isOn: Binding(
                get: { enabledIndex != nil },
                set: { newValue in toggleCapability(capability, enable: newValue) }
            )) { EmptyView() }
            .labelsHidden()
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(capability.rawValue).font(.callout.monospaced())
                    Text(capability.riskLevel)
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(sdkManifestRiskColor(capability.riskLevel).opacity(0.15),
                                    in: Capsule())
                    if !capability.isGrantable {
                        Text("restricted").font(.caption2).foregroundStyle(.red)
                    }
                    if grantedCapabilityIDs.contains(capability.rawValue) {
                        Text("granted").font(.caption2).foregroundStyle(.green)
                    }
                }
                if let idx = enabledIndex {
                    TextField("Why is this capability needed?", text: Binding(
                        get: { manifest.capabilities[idx].reason },
                        set: { newReason in
                            updateManifest { $0.capabilities[idx].reason = newReason }
                        }
                    ))
                    .textFieldStyle(.roundedBorder)
                }
            }
        }
    }

    private func commandsSection(_ manifest: SwiftCodeManifest) -> some View {
        SDKStudioGroupBox("Contributed Commands (\(manifest.contributes?.commands.count ?? 0))") {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(manifest.contributes?.commands ?? [], id: \.id) { command in
                    HStack {
                        Text(command.id).font(.callout.monospaced())
                        Text(command.title).foregroundStyle(.secondary)
                        Spacer()
                        Button("Remove") { removeCommand(command.id) }
                            .font(.caption)
                    }
                }
                HStack {
                    TextField("command id", text: $newCommandID)
                        .textFieldStyle(.roundedBorder)
                    TextField("Title", text: $newCommandTitle)
                        .textFieldStyle(.roundedBorder)
                    Button("Add") { addCommand() }
                        .disabled(newCommandID.isEmpty || newCommandTitle.isEmpty)
                }
            }
        }
    }

    private var diagnosticsFooter: some View {
        VStack(alignment: .leading, spacing: 2) {
            Divider()
            if diagnostics.isEmpty {
                Text("Manifest passes all syntactic, semantic, entrypoint, and capability checks.")
                    .font(.caption).foregroundStyle(.green)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
            } else {
                ForEach(diagnostics) { diag in
                    HStack(spacing: 6) {
                        Image(systemName: diag.severity == .error ? "xmark.octagon.fill" : "exclamationmark.triangle.fill")
                            .foregroundStyle(diag.severity == .error ? Color.red : Color.orange)
                        Text("[\(diag.field)] \(diag.message)")
                            .font(.caption)
                        if !diag.suggestion.isEmpty {
                            Text(diag.suggestion).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .padding(.horizontal, 8)
                }
            }
        }
    }

    // MARK: - Model helpers

    private func binding(_ keyPath: WritableKeyPath<SwiftCodeManifest, String>) -> Binding<String> {
        Binding(
            get: { manifest?[keyPath: keyPath] ?? "" },
            set: { newValue in updateManifest { $0[keyPath: keyPath] = newValue } }
        )
    }

    private func binding(_ keyPath: WritableKeyPath<SwiftCodeManifest, String?>) -> Binding<String> {
        Binding(
            get: { manifest?[keyPath: keyPath] ?? "" },
            set: { newValue in updateManifest { $0[keyPath: keyPath] = newValue.isEmpty ? nil : newValue } }
        )
    }

    private func updateManifest(_ transform: (inout SwiftCodeManifest) -> Void) {
        guard var current = manifest else { return }
        transform(&current)
        manifest = current
        isDirty = true
        syncRawText()
        recomputeDiagnostics()
    }

    private func filteredCapabilities(_ manifest: SwiftCodeManifest) -> [SDKCapabilityID] {
        let enabledIDs = Set(manifest.capabilities.map(\.id))
        let needle = capabilitySearchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return SDKCapabilityID.allCases.filter { cap in
            guard selectedCategory.matches(cap, enabledIDs: enabledIDs) else { return false }
            if needle.isEmpty { return true }
            return cap.rawValue.lowercased().contains(needle)
        }
    }

    private func toggleCapability(_ capability: SDKCapabilityID, enable: Bool) {
        updateManifest { current in
            if enable {
                if !current.capabilities.contains(where: { $0.id == capability.rawValue }) {
                    current.capabilities.append(ManifestCapability(id: capability.rawValue,
                                                                   reason: "Required for \(capability.rawValue)."))
                }
            } else {
                current.capabilities.removeAll(where: { $0.id == capability.rawValue })
            }
        }
    }

    private func addCommand() {
        let id = newCommandID.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = newCommandTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty, !title.isEmpty else { return }
        updateManifest { current in
            if current.contributes == nil { current.contributes = ManifestContributions(commands: []) }
            if !(current.contributes?.commands.contains(where: { $0.id == id }) ?? false) {
                current.contributes?.commands.append(ManifestCommand(id: id, title: title))
            }
        }
        newCommandID = ""
        newCommandTitle = ""
    }

    private func removeCommand(_ id: String) {
        updateManifest { current in
            current.contributes?.commands.removeAll(where: { $0.id == id })
        }
    }

    private func preauthorize(manifest: SwiftCodeManifest) {
        // Pre-authorization grants through the real `PermissionManager`
        // (grants.json). The `SDKStudioGrantStore` seam is read/revoke;
        // granting is `PermissionManager.grant`, so this uses it directly
        // rather than inventing a second grant path.
        let permissions = defaultPermissions()
        let extensionID = manifest.id
        for cap in manifest.capabilities {
            guard let sdkCap = SDKCapabilityID(rawValue: cap.id) else { continue }
            for v2 in ExtensionCapability.v2Capabilities(for: sdkCap) {
                permissions.grant(extensionId: extensionID, capability: v2)
            }
        }
        grantedCapabilityIDs = Set(manifest.capabilities.map(\.id))
        statusBanner = "Granted \(manifest.capabilities.count) capability permission(s) for \(extensionID)."
    }

    private func defaultPermissions() -> PermissionManager {
        // The Studio Extensions view owns the shared ExtensionManager;
        // the manifest editor uses a PermissionManager over the default
        // ExtensionStorage so pre-authorization lands in grants.json.
        PermissionManager()
    }

    private func loadFromDisk() {
        parseError = nil
        statusBanner = nil
        guard let url = manifestFileURL else {
            manifest = nil
            rawText = ""
            diagnostics = []
            return
        }
        do {
            let data = try Data(contentsOf: url)
            rawText = String(decoding: data, as: UTF8.self)
            manifest = try JSONDecoder().decode(SwiftCodeManifest.self, from: data)
            isDirty = false
            recomputeDiagnostics()
        } catch {
            parseError = "Could not read swiftcode.json: \(error.localizedDescription)"
            manifest = nil
            diagnostics = []
            if let data = try? Data(contentsOf: url) {
                rawText = String(decoding: data, as: UTF8.self)
                showingRaw = true
            }
        }
    }

    private func syncRawText() {
        guard let manifest else { return }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(manifest) {
            rawText = String(decoding: data, as: UTF8.self)
        }
    }

    private func recomputeDiagnostics() {
        let data: Data
        if showingRaw {
            data = Data(rawText.utf8)
        } else if let manifest {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            data = (try? encoder.encode(manifest)) ?? Data()
        } else {
            diagnostics = []
            return
        }
        diagnostics = SwiftCodeManifestValidator.validateWithDiagnostics(
            data: data, projectRoot: manifestFileURL?.deletingLastPathComponent())
    }

    private func save() {
        guard let url = manifestFileURL else { return }
        let data: Data
        if showingRaw {
            data = Data(rawText.utf8)
            // Re-parse so the visual model stays in sync after a raw save.
            if let decoded = try? JSONDecoder().decode(SwiftCodeManifest.self, from: data) {
                manifest = decoded
            }
        } else if let manifest {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            guard let encoded = try? encoder.encode(manifest) else { return }
            data = encoded
        } else {
            return
        }
        do {
            try data.write(to: url, options: .atomic)
            isDirty = false
            statusBanner = "Saved \(url.lastPathComponent)."
            recomputeDiagnostics()
            if let tab = editorState.tabs.first(where: { $0.document.fileURL?.standardizedFileURL == url.standardizedFileURL }) {
                let text = String(decoding: data, as: UTF8.self)
                editorState.updateDocument(forTab: tab.id) { $0.withText(text).saved(fileURL: url) }
            }
        } catch {
            parseError = "Could not save: \(error.localizedDescription)"
        }
    }
}

// MARK: - Manifest inspector
//
// Legacy: `SwiftCode/SDK/Studio/Views/SDKManifestInspectorView.swift` —
// the read-first view of a manifest: identity, runtime, SDK, capabilities
// with risk/policy badges, contributed commands, diagnostics, and a raw
// JSON tab, with an edit mode that hands off to the visual editor.

@MainActor
struct SDKManifestInspectorView: View {
    let manifestFileURL: URL?
    @Bindable var editorState: SDKCodeEditorState
    @State private var manifest: SwiftCodeManifest?
    @State private var rawJSONText: String = ""
    @State private var isEditingVisually = false
    @State private var diagnostics: [ManifestDiagnostic] = []
    @State private var parseErrorText: String?
    @State private var capabilitySearchQuery: String = ""
    @State private var selectedCategory: SDKManifestCapabilityCategory = .all

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(manifest.map { "\($0.id) · v\($0.version)" } ?? "Manifest Inspector")
                    .font(.headline)
                Spacer()
                Picker("Mode", selection: $isEditingVisually) {
                    Text("Inspect").tag(false)
                    Text("Edit").tag(true)
                }
                .pickerStyle(.segmented)
                .frame(width: 160)
                Button("Reload") { loadFromDisk() }
            }
            .padding(8)
            if isEditingVisually {
                SDKManifestEditorView(manifestFileURL: manifestFileURL, editorState: editorState)
            } else if let manifest {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        inspectorIdentity(manifest)
                        inspectorCapabilities(manifest)
                        inspectorCommands(manifest)
                        inspectorDiagnostics
                        SDKStudioGroupBox("Raw JSON") {
                            Text(rawJSONText)
                                .font(.caption.monospaced())
                                
                        }
                    }
                    .padding()
                }
            } else {
                SDKStudioEmptyState(title: "No Manifest", systemImage: "doc.badge.gearshape",
                                     description: parseErrorText ?? "Open a project with a swiftcode.json to inspect its manifest.")
            }
        }
        .task { loadFromDisk() }
    }

    private func inspectorIdentity(_ manifest: SwiftCodeManifest) -> some View {
        SDKStudioGroupBox("Extension Identity") {
            VStack(alignment: .leading, spacing: 4) {
                LabeledContent("ID", value: manifest.id)
                LabeledContent("Name", value: manifest.name)
                LabeledContent("Version", value: manifest.version)
                if let description = manifest.description {
                    LabeledContent("Description", value: description)
                }
                LabeledContent("Type", value: manifest.type)
                LabeledContent("Runtime", value: "\(manifest.runtime.language) · \(manifest.runtime.entrypoint)")
                LabeledContent("SDK", value: "\(manifest.sdk.name) \(manifest.sdk.versionRange) (protocol \(manifest.sdk.protocolVersion))")
                if manifest.assist.requested {
                    Text("Assist access requested").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func inspectorCapabilities(_ manifest: SwiftCodeManifest) -> some View {
        SDKStudioGroupBox("Capabilities (\(manifest.capabilities.count))") {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    TextField("Filter capabilities…", text: $capabilitySearchQuery)
                        .textFieldStyle(.roundedBorder)
                    Picker("Category", selection: $selectedCategory) {
                        ForEach(SDKManifestCapabilityCategory.allCases, id: \.self) { category in
                            Text(category.rawValue).tag(category)
                        }
                    }
                    .pickerStyle(.menu)
                }
                ForEach(filteredInspectorCapabilities(manifest), id: \.id) { cap in
                    HStack(alignment: .top, spacing: 8) {
                        if let sdkCap = SDKCapabilityID(rawValue: cap.id) {
                            Text(sdkCap.riskLevel)
                                .font(.caption2)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(sdkManifestRiskColor(sdkCap.riskLevel).opacity(0.15), in: Capsule())
                            if !sdkCap.isGrantable {
                                Text("restricted").font(.caption2).foregroundStyle(.red)
                            }
                        } else {
                            Text("unknown").font(.caption2).foregroundStyle(.red)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(cap.id).font(.callout.monospaced())
                            Text(cap.reason).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    private func filteredInspectorCapabilities(_ manifest: SwiftCodeManifest) -> [ManifestCapability] {
        let needle = capabilitySearchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return manifest.capabilities.filter { cap in
            if let sdkCap = SDKCapabilityID(rawValue: cap.id),
               !selectedCategory.matches(sdkCap, enabledIDs: Set(manifest.capabilities.map(\.id))) {
                return false
            }
            if needle.isEmpty { return true }
            return cap.id.lowercased().contains(needle) || cap.reason.lowercased().contains(needle)
        }
    }

    private func inspectorCommands(_ manifest: SwiftCodeManifest) -> some View {
        SDKStudioGroupBox("Contributed Commands (\(manifest.contributes?.commands.count ?? 0))") {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(manifest.contributes?.commands ?? [], id: \.id) { command in
                    HStack {
                        Text(command.id).font(.callout.monospaced())
                        Text(command.title).foregroundStyle(.secondary)
                    }
                }
                if (manifest.contributes?.commands ?? []).isEmpty {
                    Text("No contributed commands.").foregroundStyle(.secondary)
                }
            }
        }
    }

    private var inspectorDiagnostics: some View {
        SDKStudioGroupBox("Diagnostics") {
            VStack(alignment: .leading, spacing: 4) {
                if diagnostics.isEmpty {
                    Text("No issues found.").foregroundStyle(.green)
                }
                ForEach(diagnostics) { diag in
                    HStack(spacing: 6) {
                        Image(systemName: diag.severity == .error ? "xmark.octagon.fill" : "exclamationmark.triangle.fill")
                            .foregroundStyle(diag.severity == .error ? Color.red : Color.orange)
                        Text("[\(diag.field)] \(diag.message)").font(.caption)
                    }
                }
            }
        }
    }

    private func loadFromDisk() {
        parseErrorText = nil
        guard let url = manifestFileURL else {
            manifest = nil
            return
        }
        do {
            let data = try Data(contentsOf: url)
            rawJSONText = String(decoding: data, as: UTF8.self)
            manifest = try JSONDecoder().decode(SwiftCodeManifest.self, from: data)
            diagnostics = SwiftCodeManifestValidator.validateWithDiagnostics(
                data: data, projectRoot: url.deletingLastPathComponent())
        } catch {
            parseErrorText = "Could not read swiftcode.json: \(error.localizedDescription)"
            manifest = nil
            diagnostics = []
        }
    }
}
