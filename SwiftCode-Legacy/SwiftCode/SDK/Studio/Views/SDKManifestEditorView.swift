import AppKit
import SwiftUI

// MARK: - SDKManifestEditorView
//
// Full visual editor and validator for `swiftcode.json` in SwiftCode Studio
// (`Review.md` §7 & §8). Allows developers to inspect, configure, validate,
// and save all extension manifest fields (identity, runtime, SDK version range,
// capabilities + reasons from the canonical 32-capability registry, contributed
// commands, Assist metadata, and preserved unknown fields) without manually
// editing raw JSON, while maintaining bidirectional synchronization with the
// raw JSON buffer in `SDKCodeEditorState`.

@MainActor
public struct SDKManifestEditorView: View {
    @ObservedObject private var editorState: SDKCodeEditorState

    private let manifestFileURL: URL?
    private let projectRootURL: URL?
    private let onOpenRawJSON: (() -> Void)?

    @State private var manifest: SDKManifest = Self.defaultTemplateManifest()
    @State private var parseError: String?
    @State private var rawFallbackText: String = ""
    @State private var diagnostics: [SDKManifestDiagnostic] = []
    @State private var capabilitySearchQuery: String = ""
    @State private var selectedCapabilityCategory: String = "All"
    @State private var isDirty: Bool = false
    @State private var statusBanner: String?
    @State private var grantedCapabilityIDs: Set<String> = []

    private static let categoryFilters = [
        "All",
        "Enabled Only",
        "Project",
        "Source Control",
        "Build",
        "UI & Views",
        "Security & AI"
    ]

    public init(
        manifestFileURL: URL? = nil,
        projectRootURL: URL? = nil,
        editorState: SDKCodeEditorState? = nil,
        onOpenRawJSON: (() -> Void)? = nil
    ) {
        self.manifestFileURL = manifestFileURL
        self.projectRootURL = projectRootURL
        self._editorState = ObservedObject(wrappedValue: editorState ?? SDKCodeEditorState.shared)
        self.onOpenRawJSON = onOpenRawJSON
    }

    private var effectiveManifestURL: URL? {
        if let manifestFileURL { return manifestFileURL }
        if let activeURL = editorState.activeDocument?.fileURL,
           activeURL.lastPathComponent == "swiftcode.json" {
            return activeURL
        }
        if let root = effectiveProjectRootURL {
            return root.appendingPathComponent("swiftcode.json")
        }
        return nil
    }

    private var effectiveProjectRootURL: URL? {
        if let projectRootURL { return projectRootURL }
        if let manifestFileURL { return manifestFileURL.deletingLastPathComponent() }
        if let activeURL = editorState.activeDocument?.fileURL,
           activeURL.lastPathComponent == "swiftcode.json" {
            return activeURL.deletingLastPathComponent()
        }
        return editorState.projectRootURL
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            toolbarHeader
            Divider()

            if let parseError {
                malformedJSONBanner(parseError)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        if let statusBanner {
                            savedBanner(statusBanner)
                        }

                        validationSummarySection
                        identitySection
                        runtimeAndSDKSection
                        capabilitiesSection
                        commandsSection
                        assistSection
                        if !manifest.unknownFields.isEmpty {
                            unknownFieldsSection
                        }
                    }
                    .padding(18)
                }
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
        .onAppear {
            loadManifestFromSource()
        }
        .onChange(of: effectiveManifestURL) { _, _ in
            loadManifestFromSource()
        }
    }

    // MARK: - Toolbar Header

    private var toolbarHeader: some View {
        HStack(spacing: 10) {
            Image(systemName: "slider.horizontal.below.square.and.square.filled")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.accentColor)

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text("Visual Manifest Editor — swiftcode.json")
                        .font(.system(size: 13, weight: .semibold))
                    if isDirty {
                        Text("Modified")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.orange)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1.5)
                            .background(Capsule().fill(Color.orange.opacity(0.15)))
                    }
                }
                if let url = effectiveManifestURL {
                    Text(url.path)
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            Spacer()

            let errorCount = diagnostics.filter { $0.severity == .error }.count
            let warningCount = diagnostics.filter { $0.severity == .warning }.count
            HStack(spacing: 6) {
                Label(
                    errorCount == 0 ? "Valid Schema" : "\(errorCount) Error\(errorCount == 1 ? "" : "s")",
                    systemImage: errorCount == 0 ? "checkmark.seal.fill" : "xmark.octagon.fill"
                )
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(errorCount == 0 ? Color.green : Color.red)

                if warningCount > 0 {
                    Label("\(warningCount) Warning\(warningCount == 1 ? "" : "s")", systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.orange)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )

            if let onOpenRawJSON {
                Button {
                    syncToEditorBufferIfOpen()
                    onOpenRawJSON()
                } label: {
                    Label("Raw JSON", systemImage: "curlybraces")
                        .font(.system(size: 11, weight: .medium))
                }
                .controlSize(.small)
                .help("Switch to Raw JSON view")
            }

            Button {
                loadManifestFromSource()
            } label: {
                Label("Reload", systemImage: "arrow.clockwise")
                    .font(.system(size: 11, weight: .medium))
            }
            .controlSize(.small)
            .help("Reload swiftcode.json from disk")

            Button {
                saveManifestToDisk()
            } label: {
                Label("Save swiftcode.json", systemImage: "square.and.arrow.down")
                    .font(.system(size: 11, weight: .semibold))
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .keyboardShortcut("s", modifiers: [.command])
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - Malformed JSON Fallback

    private func malformedJSONBanner(_ errorText: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "xmark.octagon.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(.red)
                VStack(alignment: .leading, spacing: 2) {
                    Text("swiftcode.json contains a syntax or schema error")
                        .font(.system(size: 13, weight: .semibold))
                    Text(errorText)
                        .font(.system(size: 11.5, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 10) {
                if let onOpenRawJSON {
                    Button("Fix in Raw JSON Editor") {
                        onOpenRawJSON()
                    }
                    .buttonStyle(.borderedProminent)
                }
                Button("Reset to Valid v1 Manifest Template") {
                    manifest = Self.defaultTemplateManifest()
                    parseError = nil
                    markEdited()
                }
                .buttonStyle(.bordered)
            }

            if !rawFallbackText.isEmpty {
                Text("Current File Contents:")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                ScrollView {
                    Text(rawFallbackText)
                        .font(.system(size: 11, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                }
                .background(RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: .controlBackgroundColor)))
            }
            Spacer()
        }
        .padding(18)
    }

    private func savedBanner(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
            Text(message)
                .font(.system(size: 11.5, weight: .medium))
            Spacer()
            Button {
                statusBanner = nil
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10))
            }
            .buttonStyle(.plain)
        }
        .padding(10)
        .liquidGlass(style: .standard, cornerRadius: 7, tint: .green)
    }

    // MARK: - Sections

    private var validationSummarySection: some View {
        GroupBox {
            if diagnostics.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("Manifest passes all syntactic, semantic, entrypoint, and capability checks.")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(6)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(diagnostics) { diag in
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: iconName(for: diag.severity))
                                .foregroundStyle(color(for: diag.severity))
                                .font(.system(size: 12))
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 6) {
                                    Text(diag.field)
                                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                    if let line = diag.line {
                                        Text("line \(line)")
                                            .font(.system(size: 10, design: .monospaced))
                                            .foregroundStyle(.secondary)
                                    }
                                    Text(diag.message)
                                        .font(.system(size: 11.5, weight: .medium))
                                }
                                Text(diag.suggestion)
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                        .padding(6)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(color(for: diag.severity).opacity(0.08))
                        )
                    }
                }
                .padding(4)
            }
        } label: {
            Label("Live Manifest Validation & Diagnostics", systemImage: "checkmark.shield")
                .font(.system(size: 12, weight: .semibold))
        }
    }

    private var identitySection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 12) {
                    labeledField("Extension ID (reverse-DNS)", hint: "com.example.my-extension") {
                        TextField("com.example.my-extension", text: Binding(
                            get: { manifest.id },
                            set: { manifest.id = $0; markEdited() }
                        ))
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12, design: .monospaced))
                    }

                    labeledField("Display Name", hint: "Human-readable name") {
                        TextField("My Extension", text: Binding(
                            get: { manifest.name },
                            set: { manifest.name = $0; markEdited() }
                        ))
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12))
                    }
                }

                HStack(spacing: 12) {
                    labeledField("Version (SemVer)", hint: "e.g. 0.1.0 or 1.0.0") {
                        TextField("0.1.0", text: Binding(
                            get: { manifest.version },
                            set: { manifest.version = $0; markEdited() }
                        ))
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12, design: .monospaced))
                    }

                    labeledField("Package Type", hint: "extension") {
                        Picker("", selection: Binding(
                            get: { manifest.type },
                            set: { manifest.type = $0; markEdited() }
                        )) {
                            Text("extension").tag("extension")
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                    }

                    labeledField("Manifest Schema Version", hint: "Generation 1") {
                        Text("v\(manifest.manifestVersion)")
                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 4)
                    }
                }

                labeledField("Description", hint: "Summary shown in Studio Extensions catalog") {
                    TextField("Describe what this extension does…", text: Binding(
                        get: { manifest.description ?? "" },
                        set: { manifest.description = $0.isEmpty ? nil : $0; markEdited() }
                    ))
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12))
                }
            }
            .padding(8)
        } label: {
            Label("Identity & Metadata", systemImage: "person.text.rectangle")
                .font(.system(size: 12, weight: .semibold))
        }
    }

    private var runtimeAndSDKSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 12) {
                    labeledField("Runtime Language", hint: "v1 supports typescript") {
                        Picker("", selection: Binding(
                            get: { manifest.runtime.language },
                            set: { manifest.runtime.language = $0; markEdited() }
                        )) {
                            Text("typescript").tag("typescript")
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                    }

                    labeledField("Compiled Entrypoint", hint: "Relative path inside package (e.g. dist/index.js)") {
                        HStack(spacing: 6) {
                            TextField("dist/index.js", text: Binding(
                                get: { manifest.runtime.entrypoint },
                                set: { manifest.runtime.entrypoint = $0; markEdited() }
                            ))
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 12, design: .monospaced))

                            if let root = effectiveProjectRootURL {
                                let exists = FileManager.default.fileExists(
                                    atPath: root.appendingPathComponent(manifest.runtime.entrypoint).path
                                )
                                Image(systemName: exists ? "checkmark.circle.fill" : "clock.badge.exclamationmark")
                                    .foregroundStyle(exists ? Color.green : Color.orange)
                                    .help(exists ? "Entrypoint exists on disk" : "Entrypoint will be produced on Build")
                            }
                        }
                    }

                    labeledField("Minimum SwiftCode Version", hint: "SemVer, e.g. 1.0.0") {
                        TextField("1.0.0", text: Binding(
                            get: { manifest.runtime.minimumSwiftCodeVersion },
                            set: { manifest.runtime.minimumSwiftCodeVersion = $0; markEdited() }
                        ))
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12, design: .monospaced))
                    }
                }

                HStack(spacing: 12) {
                    labeledField("SDK Package", hint: "@swiftcode/sdk") {
                        TextField("@swiftcode/sdk", text: Binding(
                            get: { manifest.sdk.name },
                            set: { manifest.sdk.name = $0; markEdited() }
                        ))
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12, design: .monospaced))
                    }

                    labeledField("SDK Version Range", hint: "Compatible with host 1.2.0") {
                        Picker("", selection: Binding(
                            get: { manifest.sdk.versionRange },
                            set: { manifest.sdk.versionRange = $0; markEdited() }
                        )) {
                            Text("1.2.0").tag("1.2.0")
                            Text("^1.2.0").tag("^1.2.0")
                            Text("^1.1.0").tag("^1.1.0")
                            Text("^1.0.0").tag("^1.0.0")
                            Text("1.1.0").tag("1.1.0")
                            Text("1.0.0").tag("1.0.0")
                            Text(">=1.0.0 <2.0.0").tag(">=1.0.0 <2.0.0")
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                    }

                    labeledField("IPC Protocol Version", hint: "Must be 1") {
                        Text("v\(manifest.sdk.protocolVersion)")
                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 4)
                    }
                }
            }
            .padding(8)
        } label: {
            Label("Runtime & SDK Compatibility", systemImage: "gearshape.2")
                .font(.system(size: 12, weight: .semibold))
        }
    }

    private var capabilitiesSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Filter capabilities by ID, title, or summary…", text: $capabilitySearchQuery)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 11.5))

                    Spacer()

                    Text("\(manifest.capabilities.count) enabled")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Color.accentColor)

                    Button("Grant Enabled Capabilities in Host") {
                        grantEnabledCapabilitiesForExtension()
                    }
                    .controlSize(.small)
                    .help("Pre-authorize all enabled manifest capabilities in SDKGrantStore for this extension ID")
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(Self.categoryFilters, id: \.self) { filter in
                            let selected = selectedCapabilityCategory == filter
                            Button {
                                selectedCapabilityCategory = filter
                            } label: {
                                Text(filter)
                                    .font(.system(size: 10.5, weight: selected ? .semibold : .regular))
                                    .foregroundStyle(selected ? Color.white : Color.primary)
                                    .padding(.horizontal, 9)
                                    .padding(.vertical, 3.5)
                                    .background(
                                        Capsule()
                                            .fill(selected ? Color.accentColor : Color(nsColor: .controlBackgroundColor))
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    ForEach(filteredCapabilities, id: \.id) { cap in
                        capabilityRow(cap)
                    }
                }
            }
            .padding(8)
        } label: {
            Label("Capabilities & Permission Justifications (\(manifest.capabilities.count)/\(SDKCapability.all.count))", systemImage: "lock.shield")
                .font(.system(size: 12, weight: .semibold))
        }
    }

    private func capabilityRow(_ cap: SDKCapability) -> some View {
        let enabledIndex = manifest.capabilities.firstIndex(where: { $0.id == cap.id })
        let isEnabled = enabledIndex != nil
        let isGranted = grantedCapabilityIDs.contains(cap.id)

        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 8) {
                Toggle("", isOn: Binding(
                    get: { isEnabled },
                    set: { newValue in
                        toggleCapability(cap, enabled: newValue)
                    }
                ))
                .labelsHidden()
                .toggleStyle(.checkbox)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(cap.title)
                            .font(.system(size: 12, weight: .semibold))
                        Text(cap.id)
                            .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(RoundedRectangle(cornerRadius: 4).fill(Color.secondary.opacity(0.12)))
                        riskBadge(cap.riskLevel)
                        if isEnabled {
                            Text(isGranted ? "GRANTED" : "NEEDS GRANT")
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .foregroundStyle(isGranted ? Color.green : Color.orange)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(
                                    RoundedRectangle(cornerRadius: 3)
                                        .fill((isGranted ? Color.green : Color.orange).opacity(0.14))
                                )
                        }
                    }
                    Text(cap.summary)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            if let idx = enabledIndex, manifest.capabilities.indices.contains(idx) {
                HStack(spacing: 6) {
                    Text("Justification (`reason`):")
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(.secondary)
                    TextField("Explain why this extension requests \(cap.id)…", text: Binding(
                        get: { manifest.capabilities[idx].reason },
                        set: { newReason in
                            manifest.capabilities[idx].reason = newReason
                            markEdited()
                        }
                    ))
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 11.5))
                }
                .padding(.leading, 22)
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 7)
                .fill(isEnabled ? Color.accentColor.opacity(0.06) : Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 7)
                .strokeBorder(isEnabled ? Color.accentColor.opacity(0.3) : Color.secondary.opacity(0.12), lineWidth: 1)
        )
    }

    private var commandsSection: some View {
        let commands = manifest.contributes?.commands ?? []
        return GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Commands contributed to the SwiftCode Command Palette.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        var current = manifest.contributes?.commands ?? []
                        let nextNum = current.count + 1
                        current.append(SDKManifestCommandContribution(
                            id: "command-\(nextNum)",
                            title: "Run Command \(nextNum)"
                        ))
                        manifest.contributes = SDKManifestContributions(commands: current)
                        markEdited()
                    } label: {
                        Label("Add Command", systemImage: "plus")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .controlSize(.small)
                }

                if commands.isEmpty {
                    Text("No commands contributed. Click \"Add Command\" to register a command.")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                        .padding(.vertical, 4)
                } else {
                    ForEach(Array(commands.enumerated()), id: \.offset) { idx, cmd in
                        HStack(spacing: 8) {
                            TextField("command-id (kebab-case)", text: Binding(
                                get: { cmd.id },
                                set: { newID in
                                    updateCommand(at: idx, id: newID, title: cmd.title)
                                }
                            ))
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 11.5, design: .monospaced))
                            .frame(maxWidth: 220)

                            TextField("Human-readable Command Title", text: Binding(
                                get: { cmd.title },
                                set: { newTitle in
                                    updateCommand(at: idx, id: cmd.id, title: newTitle)
                                }
                            ))
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 11.5))

                            Button(role: .destructive) {
                                removeCommand(at: idx)
                            } label: {
                                Image(systemName: "trash")
                                    .font(.system(size: 11))
                            }
                            .buttonStyle(.borderless)
                            .help("Remove command")
                        }
                    }
                }
            }
            .padding(8)
        } label: {
            Label("Contributed Commands (\(commands.count))", systemImage: "command.square")
                .font(.system(size: 12, weight: .semibold))
        }
    }

    private var assistSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 6) {
                Toggle("Request Assist Integration (`assist.requested`)", isOn: Binding(
                    get: { manifest.assist.requested },
                    set: { newValue in
                        manifest.assist.requested = newValue
                        markEdited()
                    }
                ))
                .font(.system(size: 12, weight: .medium))

                Text("Descriptive metadata only (ADR §9). Actual runtime Assist invocation requires a developer API key carrying the verified `com.SwiftCode.developer-AI-Assist` entitlement.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .padding(8)
        } label: {
            Label("Assist Metadata", systemImage: "sparkles")
                .font(.system(size: 12, weight: .semibold))
        }
    }

    private var unknownFieldsSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 4) {
                Text("The following custom top-level JSON properties were found in swiftcode.json and will be preserved intact on save:")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                ForEach(manifest.unknownFields.keys.sorted(), id: \.self) { key in
                    HStack(spacing: 8) {
                        Text(key)
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        Text(manifest.unknownFields[key]?.summaryDescription ?? "")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(8)
        } label: {
            Label("Preserved Custom Fields (\(manifest.unknownFields.count))", systemImage: "archivebox")
                .font(.system(size: 12, weight: .semibold))
        }
    }

    // MARK: - Helpers

    private var filteredCapabilities: [SDKCapability] {
        let enabledIDs = Set(manifest.capabilities.map(\.id))
        let catFiltered = SDKCapability.all.filter { cap in
            switch selectedCapabilityCategory {
            case "All": return true
            case "Enabled Only": return enabledIDs.contains(cap.id)
            case "Project": return cap.category == .project
            case "Source Control": return cap.category == .sourceControl
            case "Build": return cap.category == .build
            case "UI & Views": return cap.category == .ui && !cap.id.hasPrefix("use.") && cap.id != "assist.invoke" && cap.id != "credentials.use"
            case "Security & AI": return cap.id.hasPrefix("use.") || cap.id == "assist.invoke" || cap.id == "credentials.use" || cap.id == "network.request"
            default: return true
            }
        }
        let needle = capabilitySearchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else { return catFiltered }
        return catFiltered.filter { cap in
            cap.id.lowercased().contains(needle)
                || cap.title.lowercased().contains(needle)
                || cap.summary.lowercased().contains(needle)
        }
    }

    private func toggleCapability(_ cap: SDKCapability, enabled: Bool) {
        if enabled {
            if !manifest.capabilities.contains(where: { $0.id == cap.id }) {
                manifest.capabilities.append(
                    SDKManifestCapability(id: cap.id, reason: cap.summary)
                )
            }
        } else {
            manifest.capabilities.removeAll(where: { $0.id == cap.id })
        }
        markEdited()
    }

    private func updateCommand(at index: Int, id: String, title: String) {
        var current = manifest.contributes?.commands ?? []
        guard current.indices.contains(index) else { return }
        current[index] = SDKManifestCommandContribution(id: id, title: title)
        manifest.contributes = SDKManifestContributions(commands: current)
        markEdited()
    }

    private func removeCommand(at index: Int) {
        var current = manifest.contributes?.commands ?? []
        guard current.indices.contains(index) else { return }
        current.remove(at: index)
        manifest.contributes = current.isEmpty ? nil : SDKManifestContributions(commands: current)
        markEdited()
    }

    private func markEdited() {
        isDirty = true
        statusBanner = nil
        recomputeDiagnostics()
        syncToEditorBufferIfOpen()
    }

    private func recomputeDiagnostics() {
        refreshGrantedCapabilities()
        guard let data = try? manifest.encodedPrettyJSON() else { return }
        diagnostics = SDKManifestValidator.validateWithDiagnostics(
            data: data,
            projectRoot: effectiveProjectRootURL,
            grantedCapabilities: grantedCapabilityIDs
        )
    }

    private func refreshGrantedCapabilities() {
        let extID = manifest.id.trimmingCharacters(in: .whitespacesAndNewlines)
        var granted = Set<String>()
        if !extID.isEmpty {
            let store = SDKGrantStore.shared
            for record in store.grants(forExtensionID: extID) where record.decision == .allow {
                granted.insert(record.capabilityID)
            }
        }
        // Also union scopes from any active non-revoked SDK API key
        if let keys = try? SDKAPIKeyStore.shared.listKeys() {
            for key in keys where !key.isRevoked {
                granted.formUnion(key.scopes)
            }
        }
        grantedCapabilityIDs = granted
    }

    private func grantEnabledCapabilitiesForExtension() {
        let extID = manifest.id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !extID.isEmpty else { return }
        let store = SDKGrantStore.shared
        for cap in manifest.capabilities {
            store.recordDecision(
                extensionID: extID,
                capabilityID: cap.id,
                decision: .allow,
                scope: .persistent
            )
        }
        refreshGrantedCapabilities()
        recomputeDiagnostics()
        statusBanner = "Granted \(manifest.capabilities.count) capability permission(s) for \(extID)."
    }

    private func loadManifestFromSource() {
        parseError = nil
        // Prefer in-memory buffer if swiftcode.json is open in SDKCodeEditorState
        if let url = effectiveManifestURL,
           let openTab = editorState.tabs.first(where: { $0.document.fileURL?.standardizedFileURL == url.standardizedFileURL }) {
            let text = openTab.document.text
            rawFallbackText = text
            if let data = text.data(using: .utf8) {
                do {
                    manifest = try JSONDecoder().decode(SDKManifest.self, from: data)
                    isDirty = openTab.document.isDirty
                    refreshGrantedCapabilities()
                    diagnostics = SDKManifestValidator.validateWithDiagnostics(
                        data: data,
                        projectRoot: effectiveProjectRootURL,
                        grantedCapabilities: grantedCapabilityIDs
                    )
                    return
                } catch {
                    parseError = error.localizedDescription
                    diagnostics = SDKManifestValidator.validateWithDiagnostics(
                        data: data,
                        projectRoot: effectiveProjectRootURL
                    )
                    return
                }
            }
        }

        if let url = effectiveManifestURL, FileManager.default.fileExists(atPath: url.path) {
            do {
                let data = try Data(contentsOf: url)
                rawFallbackText = String(data: data, encoding: .utf8) ?? ""
                manifest = try JSONDecoder().decode(SDKManifest.self, from: data)
                isDirty = false
                refreshGrantedCapabilities()
                diagnostics = SDKManifestValidator.validateWithDiagnostics(
                    data: data,
                    projectRoot: effectiveProjectRootURL,
                    grantedCapabilities: grantedCapabilityIDs
                )
            } catch {
                parseError = error.localizedDescription
            }
        } else {
            manifest = Self.defaultTemplateManifest()
            isDirty = false
            recomputeDiagnostics()
        }
    }

    private func syncToEditorBufferIfOpen() {
        guard let url = effectiveManifestURL,
              let openTab = editorState.tabs.first(where: { $0.document.fileURL?.standardizedFileURL == url.standardizedFileURL }),
              let formatted = try? manifest.encodedPrettyString() else { return }
        editorState.updateText(formatted, for: openTab.id)
    }

    private func saveManifestToDisk() {
        guard let formattedData = try? manifest.encodedPrettyJSON(),
              let formattedString = String(data: formattedData, encoding: .utf8) else { return }

        if let url = effectiveManifestURL {
            do {
                try formattedString.write(to: url, atomically: true, encoding: .utf8)
                if let openTab = editorState.tabs.first(where: { $0.document.fileURL?.standardizedFileURL == url.standardizedFileURL }) {
                    editorState.updateText(formattedString, for: openTab.id)
                    editorState.markSaved(tabID: openTab.id, fileURL: url)
                }
                isDirty = false
                recomputeDiagnostics()
                statusBanner = "Saved swiftcode.json to \(url.path)."
                editorState.appendConsole(SDKConsoleEntry(stream: .system, text: "Saved swiftcode.json via Visual Manifest Editor."))
            } catch {
                statusBanner = "Save failed: \(error.localizedDescription)"
            }
        }
    }

    private func labeledField<Content: View>(
        _ label: String,
        hint: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Text(label)
                    .font(.system(size: 11, weight: .semibold))
                Text("· \(hint)")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func riskBadge(_ risk: SDKCapabilityRisk) -> some View {
        let color: Color = {
            switch risk {
            case .low: return .green
            case .medium: return .blue
            case .high: return .orange
            case .critical: return .red
            }
        }()
        return Text(risk.rawValue.uppercased())
            .font(.system(size: 8.5, weight: .bold, design: .monospaced))
            .foregroundStyle(color)
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(RoundedRectangle(cornerRadius: 3).fill(color.opacity(0.14)))
    }

    private func iconName(for severity: SDKManifestDiagnostic.Severity) -> String {
        switch severity {
        case .error: return "xmark.octagon.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .info: return "info.circle.fill"
        }
    }

    private func color(for severity: SDKManifestDiagnostic.Severity) -> Color {
        switch severity {
        case .error: return .red
        case .warning: return .orange
        case .info: return .blue
        }
    }

    public static func defaultTemplateManifest() -> SDKManifest {
        SDKManifest(
            manifestVersion: 1,
            id: "com.example.my-extension",
            name: "My Extension",
            version: "0.1.0",
            description: "A SwiftCode extension built in SwiftCode Studio.",
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
                    reason: "Read repository status and diffs for the active project."
                ),
                SDKManifestCapability(
                    id: "build.execute",
                    reason: "Run project builds through the host's managed build service."
                )
            ],
            contributes: SDKManifestContributions(commands: [
                SDKManifestCommandContribution(id: "inspect-repository", title: "Inspect Repository"),
                SDKManifestCommandContribution(id: "run-build", title: "Run Build")
            ]),
            assist: SDKManifestAssist(requested: false)
        )
    }
}
