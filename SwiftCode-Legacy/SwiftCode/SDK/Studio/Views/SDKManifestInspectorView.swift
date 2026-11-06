import AppKit
import SwiftUI

// MARK: - SDKManifestInspectorView
//
// Read-only inspector for an installed extension (`SDKInstalledExtension`)
// plus a one-click toggle to open the full Visual `swiftcode.json` Manifest
// Editor when the extension's package directory is writable on disk.

public struct SDKManifestInspectorView: View {

    public let installedExtension: SDKInstalledExtension
    @State private var isEditingVisually: Bool = false

    public init(installedExtension: SDKInstalledExtension) {
        self.installedExtension = installedExtension
    }

    private var manifest: SDKManifest { installedExtension.manifest }

    private var manifestFileURL: URL {
        URL(fileURLWithPath: installedExtension.installPath).appendingPathComponent("swiftcode.json")
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(manifest.name)
                        .font(.headline)
                    Text("\(manifest.id) · v\(manifest.version)")
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if FileManager.default.fileExists(atPath: manifestFileURL.path) {
                    Picker("Mode", selection: $isEditingVisually) {
                        Text("Inspector").tag(false)
                        Text("Visual Editor").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 200)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .liquidGlass(style: .subtle, cornerRadius: 8)
            .padding(8)

            Divider()

            if isEditingVisually {
                SDKManifestEditorView(manifestFileURL: manifestFileURL)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        identityGroup
                        runtimeGroup
                        sdkRequirementGroup
                        capabilitiesGroup
                        commandsGroup
                        assistGroup
                        packageVerificationGroup
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private var identityGroup: some View {
        GroupBox("Extension Identity") {
            VStack(alignment: .leading, spacing: 8) {
                LabeledContent("Name", value: manifest.name)
                LabeledContent("Identifier") {
                    Text(manifest.id)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                }
                LabeledContent("Version", value: manifest.version)
                LabeledContent("Type", value: manifest.type)
                LabeledContent("Manifest Version", value: String(manifest.manifestVersion))
                if let description = manifest.description, !description.isEmpty {
                    LabeledContent("Description", value: description)
                }
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var runtimeGroup: some View {
        GroupBox("Runtime") {
            VStack(alignment: .leading, spacing: 8) {
                LabeledContent("Language", value: manifest.runtime.language)
                LabeledContent("Entrypoint") {
                    Text(manifest.runtime.entrypoint)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                }
                LabeledContent("Minimum SwiftCode Version", value: manifest.runtime.minimumSwiftCodeVersion)
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var sdkRequirementGroup: some View {
        GroupBox("SDK Requirement") {
            VStack(alignment: .leading, spacing: 8) {
                LabeledContent("Package") {
                    Text(manifest.sdk.name)
                        .font(.system(.body, design: .monospaced))
                }
                LabeledContent("Version Range") {
                    Text(manifest.sdk.versionRange)
                        .font(.system(.body, design: .monospaced))
                }
                LabeledContent("Protocol Version", value: String(manifest.sdk.protocolVersion))
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var capabilitiesGroup: some View {
        GroupBox("Requested Capabilities (\(manifest.capabilities.count))") {
            VStack(alignment: .leading, spacing: 10) {
                if manifest.capabilities.isEmpty {
                    Text("This extension requests no capabilities.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(manifest.capabilities, id: \.id) { requested in
                        capabilityRow(requested)
                        if requested.id != manifest.capabilities.last?.id {
                            Divider()
                        }
                    }
                }
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func capabilityRow(_ requested: SDKManifestCapability) -> some View {
        let descriptor = SDKCapability.lookup(requested.id)
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(descriptor?.title ?? requested.id)
                    .font(.headline)
                Text(requested.id)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                Spacer()
                if let descriptor {
                    riskBadge(descriptor.riskLevel)
                    policyBadge(descriptor.approvalPolicy)
                }
            }
            Text("Reason: \(requested.reason)")
                .font(.subheadline)
            if let summary = descriptor?.summary {
                Text(summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func riskBadge(_ risk: SDKCapabilityRisk) -> some View {
        Text("Risk: \(risk.rawValue)")
            .font(.caption2)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(riskColor(risk).opacity(0.15))
            .foregroundStyle(riskColor(risk))
            .clipShape(Capsule())
    }

    private func riskColor(_ risk: SDKCapabilityRisk) -> Color {
        switch risk {
        case .low: return .green
        case .medium: return .orange
        case .high, .restricted: return .red
        }
    }

    private func policyBadge(_ policy: SDKApprovalPolicy) -> some View {
        let label: String
        switch policy {
        case .automatic: label = "Automatic"
        case .promptOnce: label = "Prompt Once"
        case .promptEveryTime: label = "Prompt Every Time"
        case .neverGranted: label = "Never Granted"
        }
        return Text(label)
            .font(.caption2)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.secondary.opacity(0.15))
            .foregroundStyle(.secondary)
            .clipShape(Capsule())
    }

    private var commandsGroup: some View {
        let commands = manifest.contributes?.commands ?? []
        return GroupBox("Contributed Commands (\(commands.count))") {
            VStack(alignment: .leading, spacing: 8) {
                if commands.isEmpty {
                    Text("This extension contributes no commands.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(commands, id: \.id) { command in
                        HStack {
                            Text(command.title)
                            Spacer()
                            Text("\(manifest.id).\(command.id)")
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                    }
                }
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var assistGroup: some View {
        GroupBox("Assist Declaration") {
            VStack(alignment: .leading, spacing: 6) {
                LabeledContent("Requested in Manifest", value: manifest.assist.requested ? "Yes" : "No")
                Text("Descriptive metadata only. Requires a verified com.SwiftCode.developer-AI-Assist API key entitlement at runtime.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var packageVerificationGroup: some View {
        GroupBox("Package Verification") {
            VStack(alignment: .leading, spacing: 8) {
                LabeledContent("Install State", value: installedExtension.enabled ? "enabled" : "disabled")
                LabeledContent("Package Digest (SHA-256)") {
                    Text(installedExtension.packageDigest)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                }
                LabeledContent("Installed At") {
                    Text(installedExtension.installedAt.formatted(date: .abbreviated, time: .standard))
                }
                LabeledContent("Location") {
                    Text(URL(fileURLWithPath: installedExtension.installPath).path)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - SDKManifestEditorView
//
// Full visual editor for `swiftcode.json` inside SwiftCode Studio (Review.md §7 & §8).
// Supports:
// - Visual editing of Identity, Runtime, SDK Target, Capabilities & Reasons
//   (backed by the canonical 32-capability `SDKCapability.all` registry),
//   Contributed Commands, and Assist declaration.
// - Unknown top-level JSON field preservation (`manifest.unknownFields`).
// - Real-time syntactic + semantic + capability-grant validation via
//   `SDKManifestValidator.validateWithDiagnostics`.
// - Bidirectional synchronization between the Visual Form, Raw JSON text,
//   `SDKCodeEditorState` open tabs, and disk (`swiftcode.json`).

@MainActor
public struct SDKManifestEditorView: View {

    public enum EditorTabMode: String, CaseIterable, Identifiable {
        case visual = "Visual Editor"
        case split = "Split View"
        case rawJSON = "Raw JSON"

        public var id: String { rawValue }
    }

    @ObservedObject private var editorState: SDKCodeEditorState
    @State private var manifestFileURL: URL?
    @State private var manifest: SDKManifest = Self.defaultManifest()
    @State private var rawJSONText: String = ""
    @State private var mode: EditorTabMode = .visual
    @State private var capabilitySearchQuery: String = ""
    @State private var selectedCapabilityCategory: SDKCapabilityCategory? = nil
    @State private var showOnlyEnabledCapabilities: Bool = false
    @State private var diagnostics: [SDKManifestDiagnostic] = []
    @State private var parseErrorText: String? = nil
    @State private var isDirty: Bool = false
    @State private var statusBanner: String? = nil
    @State private var newCommandID: String = ""
    @State private var newCommandTitle: String = ""

    public init(
        manifestFileURL: URL? = nil,
        editorState: SDKCodeEditorState? = nil
    ) {
        self._editorState = ObservedObject(wrappedValue: editorState ?? SDKCodeEditorState())
        self._manifestFileURL = State(initialValue: manifestFileURL)
    }

    private var resolvedProjectRoot: URL? {
        if let url = manifestFileURL {
            return url.deletingLastPathComponent()
        }
        return editorState.projectRootURL
    }

    private var errorCount: Int {
        diagnostics.filter { $0.severity == .error }.count
    }

    private var warningCount: Int {
        diagnostics.filter { $0.severity == .warning }.count
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            toolbarHeader
            Divider()

            if let banner = statusBanner {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text(banner)
                        .font(.caption)
                    Spacer()
                    Button("Dismiss") { statusBanner = nil }
                        .buttonStyle(.plain)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(Color.green.opacity(0.10))
                Divider()
            }

            if let parseError = parseErrorText {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.octagon.fill")
                        .foregroundStyle(.red)
                    Text("Raw JSON has syntax/schema errors that prevent visual form sync: \(parseError)")
                        .font(.caption)
                        .foregroundStyle(.red)
                    Spacer()
                    Button("Switch to Raw JSON") {
                        mode = .rawJSON
                    }
                    .controlSize(.small)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Color.red.opacity(0.10))
                Divider()
            }

            switch mode {
            case .visual:
                visualEditorBody
            case .rawJSON:
                rawJSONEditorBody
            case .split:
                HSplitView {
                    visualEditorBody
                        .frame(minWidth: 380, maxWidth: .infinity, maxHeight: .infinity)
                    rawJSONEditorBody
                        .frame(minWidth: 320, maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            resolveAndLoadManifest()
        }
        .onChange(of: editorState.projectRootURL) { _, newRoot in
            if let newRoot {
                let candidate = newRoot.appendingPathComponent("swiftcode.json")
                if candidate != manifestFileURL {
                    manifestFileURL = candidate
                    loadFromDisk(url: candidate)
                }
            }
        }
    }

    // MARK: - Toolbar Header

    private var toolbarHeader: some View {
        HStack(spacing: 10) {
            Image(systemName: "doc.badge.gearshape.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.accentColor)

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text("swiftcode.json Manifest Editor")
                        .font(.system(size: 13, weight: .semibold))
                    if isDirty {
                        Text("Modified")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.orange)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(Color.orange.opacity(0.15), in: Capsule())
                    }
                }
                Text(manifestFileURL?.path ?? "In-memory manifest — select a project root to bind to disk")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            validationStatusPill

            Picker("View Mode", selection: $mode) {
                ForEach(EditorTabMode.allCases) { tabMode in
                    Text(tabMode.rawValue).tag(tabMode)
                }
            }
            .pickerStyle(.segmented)
            .controlSize(.small)
            .frame(width: 250)

            Button {
                chooseManifestFile()
            } label: {
                Label("Open…", systemImage: "folder")
            }
            .controlSize(.small)
            .help("Open a swiftcode.json file or project directory")

            Button {
                reloadFromSource()
            } label: {
                Label("Reload", systemImage: "arrow.clockwise")
            }
            .controlSize(.small)
            .disabled(manifestFileURL == nil)
            .help("Reload swiftcode.json from disk")

            Button {
                saveManifestToDisk()
            } label: {
                Label("Save Manifest", systemImage: "square.and.arrow.down")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .keyboardShortcut("s", modifiers: [.command])
            .help("Save swiftcode.json (⌘S)")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(.bar)
    }

    private var validationStatusPill: some View {
        HStack(spacing: 5) {
            if errorCount > 0 {
                Image(systemName: "xmark.octagon.fill")
                    .foregroundStyle(.red)
                Text("\(errorCount) error\(errorCount == 1 ? "" : "s")")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.red)
            } else if warningCount > 0 {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text("Valid · \(warningCount) warning\(warningCount == 1 ? "" : "s")")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.orange)
            } else {
                Image(systemName: "checkmark.seal.fill")
                    .foregroundStyle(.green)
                Text("Schema & Capabilities Valid")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.green)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule()
                .fill((errorCount > 0 ? Color.red : (warningCount > 0 ? Color.orange : Color.green)).opacity(0.12))
        )
    }

    // MARK: - Visual Editor Body

    private var visualEditorBody: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if !diagnostics.isEmpty {
                    diagnosticsSection
                }
                identitySection
                runtimeAndSDKSection
                capabilitiesSection
                commandsSection
                assistAndUnknownFieldsSection
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Diagnostics Section

    private var diagnosticsSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(diagnostics) { diag in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: iconForSeverity(diag.severity))
                            .foregroundStyle(colorForSeverity(diag.severity))
                            .font(.system(size: 12))
                            .padding(.top, 2)

                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(diag.field)
                                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                if let line = diag.line {
                                    Text("line \(line)")
                                        .font(.system(size: 10, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Text(diag.message)
                                .font(.system(size: 12))
                            Text(diag.suggestion)
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        if let line = diag.line, let url = manifestFileURL {
                            Button("Line \(line)") {
                                editorState.navigateTo(fileURL: url, line: line)
                            }
                            .controlSize(.mini)
                        }
                    }
                    if diag.id != diagnostics.last?.id {
                        Divider()
                    }
                }
            }
            .padding(8)
        } label: {
            Label("Live Manifest Validation (\(diagnostics.count))", systemImage: "checkmark.shield")
                .font(.subheadline.weight(.semibold))
        }
    }

    // MARK: - Identity Section

    private var identitySection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Extension Identifier (Reverse-DNS)")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        TextField("com.example.my-extension", text: Binding(
                            get: { manifest.id },
                            set: { newVal in
                                manifest.id = newVal
                                syncVisualToRawJSON()
                            }
                        ))
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Display Name")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        TextField("My Extension", text: Binding(
                            get: { manifest.name },
                            set: { newVal in
                                manifest.name = newVal
                                syncVisualToRawJSON()
                            }
                        ))
                        .textFieldStyle(.roundedBorder)
                    }
                }

                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Version (Semver)")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button("+Patch") { bumpVersion(part: 2) }
                                .buttonStyle(.link)
                                .font(.caption2)
                            Button("+Minor") { bumpVersion(part: 1) }
                                .buttonStyle(.link)
                                .font(.caption2)
                        }
                        TextField("0.1.0", text: Binding(
                            get: { manifest.version },
                            set: { newVal in
                                manifest.version = newVal
                                syncVisualToRawJSON()
                            }
                        ))
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Package Type")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Picker("Type", selection: Binding(
                            get: { manifest.type },
                            set: { newVal in
                                manifest.type = newVal
                                syncVisualToRawJSON()
                            }
                        )) {
                            Text("Extension (extension)").tag("extension")
                            Text("Standalone App (app)").tag("app")
                        }
                        .labelsHidden()
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Description")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    TextField("Brief summary of what this extension provides…", text: Binding(
                        get: { manifest.description ?? "" },
                        set: { newVal in
                            manifest.description = newVal.isEmpty ? nil : newVal
                            syncVisualToRawJSON()
                        }
                    ))
                    .textFieldStyle(.roundedBorder)
                }
            }
            .padding(8)
        } label: {
            Label("Identity & Metadata", systemImage: "person.text.rectangle")
                .font(.subheadline.weight(.semibold))
        }
    }

    // MARK: - Runtime & SDK Target Section

    private var runtimeAndSDKSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Runtime Language")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Picker("Language", selection: Binding(
                            get: { manifest.runtime.language },
                            set: { newVal in
                                manifest.runtime.language = newVal
                                syncVisualToRawJSON()
                            }
                        )) {
                            Text("TypeScript (typescript)").tag("typescript")
                        }
                        .labelsHidden()
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Runtime Entrypoint")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Spacer()
                            entrypointStatusBadge
                        }
                        TextField("dist/index.js", text: Binding(
                            get: { manifest.runtime.entrypoint },
                            set: { newVal in
                                manifest.runtime.entrypoint = newVal
                                syncVisualToRawJSON()
                            }
                        ))
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Min SwiftCode Version")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        TextField("1.0.0", text: Binding(
                            get: { manifest.runtime.minimumSwiftCodeVersion },
                            set: { newVal in
                                manifest.runtime.minimumSwiftCodeVersion = newVal
                                syncVisualToRawJSON()
                            }
                        ))
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                    }
                }

                Divider()

                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("SDK Package")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        TextField("@swiftcode/sdk", text: Binding(
                            get: { manifest.sdk.name },
                            set: { newVal in
                                manifest.sdk.name = newVal
                                syncVisualToRawJSON()
                            }
                        ))
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("SDK Version Range")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Spacer()
                            Menu("Presets") {
                                ForEach(["1.2.0", "^1.2.0", "^1.1.0", "^1.0.0", "1.1.0", "1.0.0", ">=1.0.0 <2.0.0"], id: \.self) { preset in
                                    Button(preset) {
                                        manifest.sdk.versionRange = preset
                                        syncVisualToRawJSON()
                                    }
                                }
                            }
                            .controlSize(.mini)
                        }
                        TextField("1.2.0", text: Binding(
                            get: { manifest.sdk.versionRange },
                            set: { newVal in
                                manifest.sdk.versionRange = newVal
                                syncVisualToRawJSON()
                            }
                        ))
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("IPC Protocol Version")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text("\(manifest.sdk.protocolVersion)")
                            .font(.system(.body, design: .monospaced))
                            .padding(.vertical, 4)
                    }
                }
            }
            .padding(8)
        } label: {
            Label("Runtime & SDK Compatibility", systemImage: "cpu")
                .font(.subheadline.weight(.semibold))
        }
    }

    @ViewBuilder
    private var entrypointStatusBadge: some View {
        if let root = resolvedProjectRoot {
            let entryURL = root.appendingPathComponent(manifest.runtime.entrypoint)
            if FileManager.default.fileExists(atPath: entryURL.path) {
                Text("Built ✓")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.green)
            } else if FileManager.default.fileExists(atPath: root.appendingPathComponent("src/index.ts").path) {
                Text("Needs Build")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.orange)
            } else {
                Text("Missing")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.red)
            }
        }
    }

    // MARK: - Capabilities Section

    private var filteredRegistryCapabilities: [SDKCapability] {
        SDKCapability.all.filter { cap in
            if let cat = selectedCapabilityCategory, cap.category != cat {
                return false
            }
            if showOnlyEnabledCapabilities && !isCapabilityEnabled(cap.id) {
                return false
            }
            let q = capabilitySearchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !q.isEmpty else { return true }
            return cap.id.lowercased().contains(q) ||
                   cap.title.lowercased().contains(q) ||
                   cap.summary.lowercased().contains(q)
        }
    }

    private var capabilitiesSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Search 32 capabilities by ID, title, or description…", text: $capabilitySearchQuery)
                        .textFieldStyle(.roundedBorder)

                    Picker("Category", selection: $selectedCapabilityCategory) {
                        Text("All Categories").tag(SDKCapabilityCategory?.none)
                        ForEach(SDKCapabilityCategory.allCases, id: \.self) { cat in
                            Text(cat.rawValue.capitalized).tag(SDKCapabilityCategory?.some(cat))
                        }
                    }
                    .frame(width: 150)

                    Toggle("Enabled Only (\(manifest.capabilities.count))", isOn: $showOnlyEnabledCapabilities)
                        .toggleStyle(.checkbox)
                }

                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    ForEach(filteredRegistryCapabilities, id: \.id) { cap in
                        capabilityEditorRow(cap)
                        if cap.id != filteredRegistryCapabilities.last?.id {
                            Divider()
                        }
                    }
                }
            }
            .padding(8)
        } label: {
            Label("Capabilities & Permission Justifications (\(manifest.capabilities.count) selected)", systemImage: "lock.shield")
                .font(.subheadline.weight(.semibold))
        }
    }

    private func capabilityEditorRow(_ cap: SDKCapability) -> some View {
        let enabled = isCapabilityEnabled(cap.id)
        let currentReason = reasonForCapability(cap.id)

        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 8) {
                Toggle("", isOn: Binding(
                    get: { enabled },
                    set: { isOn in
                        toggleCapability(cap, enabled: isOn)
                    }
                ))
                .toggleStyle(.checkbox)
                .labelsHidden()

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(cap.title)
                            .font(.system(size: 12, weight: .semibold))
                        Text(cap.id)
                            .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                            .foregroundStyle(Color.accentColor)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 4))
                    }
                    Text(cap.summary)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Text(cap.category.rawValue.uppercased())
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.12), in: Capsule())

                Text(cap.riskLevel.rawValue.uppercased())
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(colorForRisk(cap.riskLevel))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(colorForRisk(cap.riskLevel).opacity(0.14), in: Capsule())
            }

            if enabled {
                HStack(spacing: 8) {
                    Text("Reason:")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    TextField("Explain to the user why \(cap.id) is needed…", text: Binding(
                        get: { currentReason },
                        set: { newReason in
                            updateCapabilityReason(cap.id, reason: newReason)
                        }
                    ))
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 11.5))
                }
                .padding(.leading, 24)
            }
        }
        .padding(.vertical, 2)
    }

    // MARK: - Commands Section

    private var commandsSection: some View {
        let commands = manifest.contributes?.commands ?? []
        return GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                if commands.isEmpty {
                    Text("No commands contributed yet. Add a command below to expose it in the SwiftCode Command Palette.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(Array(commands.enumerated()), id: \.offset) { index, cmd in
                        HStack(spacing: 10) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Command ID (kebab-case)")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                TextField("run-action", text: Binding(
                                    get: { manifest.contributes?.commands[index].id ?? "" },
                                    set: { newID in
                                        manifest.contributes?.commands[index].id = newID
                                        syncVisualToRawJSON()
                                    }
                                ))
                                .textFieldStyle(.roundedBorder)
                                .font(.system(size: 11.5, design: .monospaced))
                            }

                            VStack(alignment: .leading, spacing: 2) {
                                Text("Command Title")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                TextField("Run Action", text: Binding(
                                    get: { manifest.contributes?.commands[index].title ?? "" },
                                    set: { newTitle in
                                        manifest.contributes?.commands[index].title = newTitle
                                        syncVisualToRawJSON()
                                    }
                                ))
                                .textFieldStyle(.roundedBorder)
                                .font(.system(size: 11.5))
                            }

                            Button(role: .destructive) {
                                removeCommand(at: index)
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                            .padding(.top, 14)
                            .help("Remove command")
                        }
                    }
                }

                Divider()

                HStack(spacing: 8) {
                    TextField("New command ID (e.g. inspect-repo)", text: $newCommandID)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 11.5, design: .monospaced))
                    TextField("New command title (e.g. Inspect Repository)", text: $newCommandTitle)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 11.5))
                    Button {
                        addNewCommand()
                    } label: {
                        Label("Add Command", systemImage: "plus.circle.fill")
                    }
                    .controlSize(.small)
                    .disabled(newCommandID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                              newCommandTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .padding(8)
        } label: {
            Label("Contributed Commands (\(commands.count))", systemImage: "command.square")
                .font(.subheadline.weight(.semibold))
        }
    }

    // MARK: - Assist & Unknown Fields Section

    private var assistAndUnknownFieldsSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                Toggle("Request Assist Integration (assist.requested)", isOn: Binding(
                    get: { manifest.assist.requested },
                    set: { newVal in
                        manifest.assist.requested = newVal
                        if newVal && !isCapabilityEnabled("assist.invoke") {
                            toggleCapability(
                                SDKCapability(
                                    id: "assist.invoke",
                                    title: "Invoke Assist",
                                    category: .project,
                                    riskLevel: .restricted,
                                    approvalPolicy: .neverGranted,
                                    summary: "Invoke headless or UI Assist sessions via verified API key entitlement."
                                ),
                                enabled: true
                            )
                        }
                        syncVisualToRawJSON()
                    }
                ))
                Text("Assist access is enforced at runtime by the Capability Broker and requires an API key holding the com.SwiftCode.developer-AI-Assist entitlement.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if !manifest.unknownFields.isEmpty {
                    Divider()
                    Text("Preserved Custom Top-Level Fields (\(manifest.unknownFields.count))")
                        .font(.caption.weight(.semibold))
                    ForEach(manifest.unknownFields.keys.sorted(), id: \.self) { key in
                        HStack {
                            Text(key)
                                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            Spacer()
                            Text(manifest.unknownFields[key]?.summaryDescription ?? "")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(.secondary)
                            Button(role: .destructive) {
                                manifest.unknownFields.removeValue(forKey: key)
                                syncVisualToRawJSON()
                            } label: {
                                Image(systemName: "xmark.circle")
                            }
                            .buttonStyle(.plain)
                            .help("Remove custom field \(key)")
                        }
                    }
                }
            }
            .padding(8)
        } label: {
            Label("Assist & Forward-Compatible Fields", systemImage: "sparkles")
                .font(.subheadline.weight(.semibold))
        }
    }

    // MARK: - Raw JSON Editor Body

    private var rawJSONEditorBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Raw swiftcode.json")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Format JSON") {
                    if let formatted = try? manifest.encodedPrettyString() {
                        rawJSONText = formatted
                        applyRawJSONEdit(formatted)
                    }
                }
                .controlSize(.mini)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color(nsColor: .controlBackgroundColor))

            Divider()

            TextEditor(text: Binding(
                get: { rawJSONText },
                set: { newText in
                    rawJSONText = newText
                    applyRawJSONEdit(newText)
                }
            ))
            .font(.system(size: 12, design: .monospaced))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - Actions & Synchronization

    private func resolveAndLoadManifest() {
        if let explicitURL = manifestFileURL, FileManager.default.fileExists(atPath: explicitURL.path) {
            loadFromDisk(url: explicitURL)
            return
        }
        if let activeDoc = editorState.activeDocument,
           activeDoc.displayName == "swiftcode.json" {
            manifestFileURL = activeDoc.fileURL
            rawJSONText = activeDoc.text
            applyRawJSONEdit(activeDoc.text, markDirty: activeDoc.isDirty)
            return
        }
        if let root = editorState.projectRootURL {
            let candidate = root.appendingPathComponent("swiftcode.json")
            if FileManager.default.fileExists(atPath: candidate.path) {
                manifestFileURL = candidate
                loadFromDisk(url: candidate)
                return
            }
        }
        let defaultMan = Self.defaultManifest()
        manifest = defaultMan
        rawJSONText = (try? defaultMan.encodedPrettyString()) ?? "{}\n"
        revalidate(data: Data(rawJSONText.utf8))
    }

    private func loadFromDisk(url: URL) {
        guard let data = try? Data(contentsOf: url),
              let text = String(data: data, encoding: .utf8) else { return }
        rawJSONText = text
        applyRawJSONEdit(text, markDirty: false)
    }

    private func reloadFromSource() {
        guard let url = manifestFileURL else { return }
        loadFromDisk(url: url)
        statusBanner = "Reloaded swiftcode.json from disk."
    }

    private func syncVisualToRawJSON() {
        guard let encoded = try? manifest.encodedPrettyString() else { return }
        rawJSONText = encoded
        parseErrorText = nil
        isDirty = true
        revalidate(data: Data(encoded.utf8))
        syncWithEditorStateTab(newText: encoded, isSaved: false)
    }

    private func applyRawJSONEdit(_ text: String, markDirty: Bool = true) {
        let data = Data(text.utf8)
        revalidate(data: data)
        if let decoded = try? JSONDecoder().decode(SDKManifest.self, from: data) {
            manifest = decoded
            parseErrorText = nil
        } else {
            parseErrorText = diagnostics.first(where: { $0.severity == .error })?.message ?? "Invalid JSON structure"
        }
        if markDirty {
            isDirty = true
            syncWithEditorStateTab(newText: text, isSaved: false)
        }
    }

    private func revalidate(data: Data) {
        diagnostics = SDKManifestValidator.validateWithDiagnostics(
            data: data,
            projectRoot: resolvedProjectRoot
        )
    }

    private func saveManifestToDisk() {
        let dataToSave = Data(rawJSONText.utf8)
        revalidate(data: dataToSave)

        if let url = manifestFileURL {
            do {
                try dataToSave.write(to: url, options: .atomic)
                isDirty = false
                syncWithEditorStateTab(newText: rawJSONText, isSaved: true)
                statusBanner = "Saved swiftcode.json to \(url.path)"
            } catch {
                parseErrorText = "Failed to save swiftcode.json: \(error.localizedDescription)"
            }
        } else {
            let panel = NSSavePanel()
            panel.title = "Save swiftcode.json Manifest"
            panel.nameFieldStringValue = "swiftcode.json"
            panel.canCreateDirectories = true
            if let root = editorState.projectRootURL {
                panel.directoryURL = root
            }
            if panel.runModal() == .OK, let targetURL = panel.url {
                manifestFileURL = targetURL
                do {
                    try dataToSave.write(to: targetURL, options: .atomic)
                    isDirty = false
                    syncWithEditorStateTab(newText: rawJSONText, isSaved: true)
                    statusBanner = "Saved swiftcode.json to \(targetURL.path)"
                } catch {
                    parseErrorText = "Failed to save swiftcode.json: \(error.localizedDescription)"
                }
            }
        }
    }

    private func syncWithEditorStateTab(newText: String, isSaved: Bool) {
        guard let url = manifestFileURL?.standardizedFileURL else { return }
        if let tab = editorState.tabs.first(where: { $0.document.fileURL?.standardizedFileURL == url }) {
            editorState.updateDocument(forTab: tab.id) { doc in
                let updated = doc.withText(newText)
                return isSaved ? updated.saved(fileURL: url) : updated
            }
        }
    }

    private func chooseManifestFile() {
        let panel = NSOpenPanel()
        panel.title = "Open swiftcode.json or Extension Project"
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let selected = panel.url {
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: selected.path, isDirectory: &isDir), isDir.boolValue {
                let candidate = selected.appendingPathComponent("swiftcode.json")
                editorState.projectRootURL = selected
                manifestFileURL = candidate
                if FileManager.default.fileExists(atPath: candidate.path) {
                    loadFromDisk(url: candidate)
                }
            } else {
                manifestFileURL = selected
                editorState.projectRootURL = selected.deletingLastPathComponent()
                loadFromDisk(url: selected)
            }
        }
    }

    // MARK: - Capability & Command Helpers

    private func isCapabilityEnabled(_ id: String) -> Bool {
        manifest.capabilities.contains(where: { $0.id == id })
    }

    private func reasonForCapability(_ id: String) -> String {
        manifest.capabilities.first(where: { $0.id == id })?.reason ?? ""
    }

    private func toggleCapability(_ cap: SDKCapability, enabled: Bool) {
        if enabled {
            if !isCapabilityEnabled(cap.id) {
                manifest.capabilities.append(
                    SDKManifestCapability(id: cap.id, reason: cap.summary)
                )
            }
        } else {
            manifest.capabilities.removeAll(where: { $0.id == cap.id })
        }
        syncVisualToRawJSON()
    }

    private func updateCapabilityReason(_ id: String, reason: String) {
        guard let idx = manifest.capabilities.firstIndex(where: { $0.id == id }) else { return }
        manifest.capabilities[idx].reason = reason
        syncVisualToRawJSON()
    }

    private func addNewCommand() {
        let id = newCommandID.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let title = newCommandTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty, !title.isEmpty else { return }
        var current = manifest.contributes?.commands ?? []
        current.append(SDKManifestCommandContribution(id: id, title: title))
        manifest.contributes = SDKManifestContributions(commands: current)
        newCommandID = ""
        newCommandTitle = ""
        syncVisualToRawJSON()
    }

    private func removeCommand(at index: Int) {
        guard var current = manifest.contributes?.commands, current.indices.contains(index) else { return }
        current.remove(at: index)
        manifest.contributes = current.isEmpty ? nil : SDKManifestContributions(commands: current)
        syncVisualToRawJSON()
    }

    private func bumpVersion(part: Int) {
        let comps = manifest.version.split(separator: ".").compactMap { Int($0) }
        guard comps.count == 3 else { return }
        var major = comps[0]
        var minor = comps[1]
        var patch = comps[2]
        if part == 2 {
            patch += 1
        } else if part == 1 {
            minor += 1
            patch = 0
        } else {
            major += 1
            minor = 0
            patch = 0
        }
        manifest.version = "\(major).\(minor).\(patch)"
        syncVisualToRawJSON()
    }

    private func iconForSeverity(_ severity: SDKManifestDiagnostic.Severity) -> String {
        switch severity {
        case .error: return "xmark.octagon.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .info: return "info.circle.fill"
        }
    }

    private func colorForSeverity(_ severity: SDKManifestDiagnostic.Severity) -> Color {
        switch severity {
        case .error: return .red
        case .warning: return .orange
        case .info: return .blue
        }
    }

    private func colorForRisk(_ risk: SDKCapabilityRisk) -> Color {
        switch risk {
        case .low: return .green
        case .medium: return .blue
        case .high: return .orange
        case .restricted: return .red
        }
    }

    public static func defaultManifest() -> SDKManifest {
        SDKManifest(
            manifestVersion: 1,
            id: "com.example.my-extension",
            name: "My Extension",
            version: "0.1.0",
            description: "A SwiftCode TypeScript extension.",
            type: "extension",
            runtime: SDKManifestRuntime(
                language: "typescript",
                entrypoint: "dist/index.js",
                minimumSwiftCodeVersion: "1.0.0"
            ),
            sdk: SDKManifestSDKRef(
                name: "@swiftcode/sdk",
                versionRange: "1.2.0",
                protocolVersion: 1
            ),
            capabilities: [
                SDKManifestCapability(
                    id: "source-control.read",
                    reason: "Read repository status and diffs to summarize working-tree changes."
                ),
                SDKManifestCapability(
                    id: "build.execute",
                    reason: "Run project builds through the host's managed build service."
                ),
            ],
            contributes: SDKManifestContributions(commands: [
                SDKManifestCommandContribution(id: "inspect-repository", title: "Inspect Repository"),
                SDKManifestCommandContribution(id: "run-build", title: "Run Build"),
            ]),
            assist: SDKManifestAssist(requested: false)
        )
    }
}
