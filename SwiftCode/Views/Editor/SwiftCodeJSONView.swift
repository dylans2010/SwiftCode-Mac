import SwiftUI

/// Decoded editor for `swiftcode.json`: the file is never shown as raw
/// JSON. It decodes to `SDKManifest` and presents every field in
/// organized sections, edits in place, and writes the manifest back
/// (unknown top-level fields are preserved by `SDKManifest`'s codec,
/// so visual editing never destroys forward-compatible properties).
/// Rendered in-pane by EditorView, like the Localizable
/// (.xcstrings) view: tabs, jump bar, sidebars, and the toolbar
/// stay visible. This view never takes over the code editor and
/// never posts .specialEditorActive.
public struct SwiftCodeJSONView: View {
    public let fileURL: URL

    @State private var manifest: SDKManifest?
    @State private var original: SDKManifest?
    @State private var loadError: String?
    @State private var saveError: String?
    /// Decoded `project.json` found next to this manifest, if any.
    /// Read-only: project metadata is edited in Project Settings,
    /// never from the manifest editor.
    @State private var projectDetails: ProjectFileDetails?
    @State private var newCapabilityID = ""
    @State private var newCapabilityReason = ""
    @State private var newCommandID = ""
    @State private var newCommandTitle = ""

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    private var isDirty: Bool {
        guard let manifest, let original else { return false }
        return manifest != original
    }

    public var body: some View {
        Group {
            if let loadError {
                ContentUnavailableView {
                    Label("Couldn't Read swiftcode.json", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(loadError)
                } actions: {
                    Button("Reload") { load() }
                }
            } else if let manifest = manifest {
                manifestForm(manifest)
            } else {
                ProgressView("Loading manifest…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onAppear {
            load()
        }
    }

    // MARK: - Form

    @ViewBuilder
    private func manifestForm(_ manifest: SDKManifest) -> some View {
        VStack(spacing: 0) {
            // Header (in-view, not a toolbar): file identity + actions.
            HStack(spacing: 12) {
                Image(systemName: "swift")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text("swiftcode.json")
                        .font(.system(size: 15, weight: .bold))
                    Text(fileURL.deletingLastPathComponent().lastPathComponent)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if isDirty {
                    Text("Unsaved changes")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                Button("Revert") { revert() }
                    .disabled(!isDirty)
                Button("Save") { save() }
                    .buttonStyle(.borderedProminent)
                    .disabled(!isDirty)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(VisualEffectView(material: .headerView, blendingMode: .withinWindow))
            Divider()

            if let saveError {
                Text(saveError)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 8)
            }

            Form {
                Section("Identity") {
                    TextField("Name", text: binding(\.name))
                    TextField("ID", text: binding(\.id))
                    TextField("Version", text: binding(\.version))
                    TextField("Type", text: binding(\.type))
                    TextField("Description", text: binding(\.description, defaultValue: ""))
                }

                Section("Runtime") {
                    TextField("Language", text: binding(\.runtime.language))
                    TextField("Entrypoint", text: binding(\.runtime.entrypoint))
                    TextField("Minimum SwiftCode Version", text: binding(\.runtime.minimumSwiftCodeVersion))
                }

                Section("SDK") {
                    TextField("Name", text: binding(\.sdk.name))
                    TextField("Version Range", text: binding(\.sdk.versionRange))
                    Stepper(value: binding(\.sdk.protocolVersion), in: 1...99) {
                        HStack {
                            Text("Protocol Version")
                            Spacer()
                            Text("\(manifest.sdk.protocolVersion)")
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                    }
                }

                Section("Capabilities") {
                    if manifest.capabilities.isEmpty {
                        Text("No capabilities declared.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(manifest.capabilities) { capability in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(capability.id).font(.system(size: 13, weight: .semibold))
                                Text(capability.reason).font(.system(size: 12)).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button(role: .destructive) {
                                self.manifest?.capabilities.removeAll { $0.id == capability.id }
                            } label: {
                                Label("Remove", systemImage: "trash")
                            }
                            .labelStyle(.iconOnly)
                        }
                    }
                    HStack(spacing: 8) {
                        TextField("Capability ID", text: $newCapabilityID)
                        TextField("Reason", text: $newCapabilityReason)
                        Button("Add") {
                            guard !newCapabilityID.isEmpty else { return }
                            self.manifest?.capabilities.append(
                                SDKManifestCapability(id: newCapabilityID, reason: newCapabilityReason)
                            )
                            newCapabilityID = ""
                            newCapabilityReason = ""
                        }
                        .disabled(newCapabilityID.isEmpty)
                    }
                }

                Section("Commands") {
                    if (manifest.contributes?.commands ?? []).isEmpty {
                        Text("No commands contributed.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(manifest.contributes?.commands ?? []) { command in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(command.title).font(.system(size: 13, weight: .semibold))
                                Text(command.id).font(.system(size: 12)).foregroundStyle(.secondary).monospaced()
                            }
                            Spacer()
                            Button(role: .destructive) {
                                self.manifest?.contributes?.commands.removeAll { $0.id == command.id }
                            } label: {
                                Label("Remove", systemImage: "trash")
                            }
                            .labelStyle(.iconOnly)
                        }
                    }
                    HStack(spacing: 8) {
                        TextField("Command ID", text: $newCommandID)
                        TextField("Title", text: $newCommandTitle)
                        Button("Add") {
                            guard !newCommandID.isEmpty else { return }
                            if self.manifest?.contributes == nil {
                                self.manifest?.contributes = SDKManifestContributions(commands: [])
                            }
                            self.manifest?.contributes?.commands.append(
                                SDKManifestCommandContribution(id: newCommandID, title: newCommandTitle)
                            )
                            newCommandID = ""
                            newCommandTitle = ""
                        }
                        .disabled(newCommandID.isEmpty)
                    }
                }

                Section("Assist") {
                    Toggle("Assist Requested", isOn: binding(\.assist.requested))
                    Text("Descriptive metadata only: requesting Assist here does not grant access — the capability broker denies independently.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Project Details (project.json)") {
                    if let details = projectDetails {
                        LabeledContent("Project", value: details.name)
                        if !details.description.isEmpty {
                            LabeledContent("Description", value: details.description)
                        }
                        LabeledContent("Bundle ID", value: details.bundleIdentifier)
                        LabeledContent("Platform", value: details.platform)
                        LabeledContent("Deployment Target", value: details.deploymentTarget)
                        LabeledContent("Scheme", value: details.scheme)
                        if let created = details.createdAt {
                            LabeledContent("Created", value: created.formatted(date: .abbreviated, time: .omitted))
                        }
                        if let lastOpened = details.lastOpened {
                            LabeledContent("Last Opened", value: lastOpened.formatted(date: .abbreviated, time: .omitted))
                        }
                        Text(details.path)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    } else {
                        Text("No project.json found next to this manifest. Project details appear here when the manifest lives in a project folder (or its SwiftCode/ folder).")
                            .foregroundStyle(.secondary)
                    }
                }

                if !manifest.unknownFields.isEmpty {
                    Section("Other Fields (preserved on save)") {
                        ForEach(manifest.unknownFields.keys.sorted(), id: \.self) { key in
                            LabeledContent(key, value: jsonValueDescription(manifest.unknownFields[key]))
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
        }
    }

    // MARK: - Bindings into the decoded manifest

    private func binding<Value>(_ keyPath: WritableKeyPath<SDKManifest, Value>) -> Binding<Value> {
        Binding(
            get: { manifest?[keyPath: keyPath] ?? defaultValue(for: keyPath) },
            set: { manifest?[keyPath: keyPath] = $0 }
        )
    }

    /// Fallback only for the get path before load completes; the form
    /// is never rendered while `manifest` is nil, so this is unreachable
    /// in practice. `fatalError` would be worse than a placeholder here.
    private func defaultValue<Value>(for keyPath: WritableKeyPath<SDKManifest, Value>) -> Value {
        // String and Int are the only value types bound through this helper.
        if Value.self == String.self { return "" as! Value }
        if Value.self == Int.self { return 0 as! Value }
        if Value.self == Bool.self { return false as! Value }
        return ("" as! Value)
    }

    private func binding(_ keyPath: WritableKeyPath<SDKManifest, String?>, defaultValue: String) -> Binding<String> {
        Binding(
            get: { manifest?[keyPath: keyPath] ?? defaultValue },
            set: { manifest?[keyPath: keyPath] = $0.isEmpty ? nil : $0 }
        )
    }

    private func jsonValueDescription(_ value: SDKManifestJSONValue?) -> String {
        switch value {
        case .string(let s): return s
        case .int(let i): return "\(i)"
        case .double(let d): return "\(d)"
        case .bool(let b): return b ? "true" : "false"
        case .array(let a): return "\(a.count) items"
        case .object(let o): return "\(o.count) keys"
        case .null, .none: return "—"
        }
    }

    // MARK: - Project details (project.json, read-only)

    private struct ProjectFileDetails {
        let path: String
        let name: String
        let description: String
        let bundleIdentifier: String
        let platform: String
        let deploymentTarget: String
        let scheme: String
        let createdAt: Date?
        let lastOpened: Date?
    }

    /// Finds the `project.json` that belongs to this manifest: a
    /// sibling first (covers manifests at the project root and
    /// manifests inside a project's `SwiftCode/` folder, where the
    /// copy lives), then the project root when the manifest sits
    /// inside `SwiftCode/`. Nothing else is consulted — a manifest
    /// opened outside a project shows no project details rather
    /// than some other project's metadata.
    private func loadProjectDetails() -> ProjectFileDetails? {
        let manifestDir = fileURL.deletingLastPathComponent()
        var candidates: [URL] = [manifestDir.appendingPathComponent("project.json")]
        if manifestDir.lastPathComponent == "SwiftCode" {
            candidates.append(manifestDir.deletingLastPathComponent().appendingPathComponent("project.json"))
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        for url in candidates {
            guard let data = try? Data(contentsOf: url),
                  let project = try? decoder.decode(Project.self, from: data) else { continue }
            let ci = project.ciBuildConfiguration
            let bundleID = [ci?.bundleIdentifier, project.buildSettings.bundleIdentifier]
                .compactMap { $0 }.first { !$0.isEmpty } ?? "—"
            return ProjectFileDetails(
                path: url.path,
                name: project.name,
                description: project.description,
                bundleIdentifier: bundleID,
                platform: ci?.platform.rawValue ?? project.buildSettings.deploymentTargetPlatform,
                deploymentTarget: ci?.deploymentTarget ?? project.buildSettings.deploymentTargetVersion,
                scheme: ci?.schemeName ?? "—",
                createdAt: project.createdAt,
                lastOpened: project.lastOpened
            )
        }
        return nil
    }

    // MARK: - Load / save

    private func load() {
        loadError = nil
        saveError = nil
        projectDetails = loadProjectDetails()
        do {
            let data = try Data(contentsOf: fileURL)
            let decoded = try JSONDecoder().decode(SDKManifest.self, from: data)
            manifest = decoded
            original = decoded
        } catch {
            loadError = error.localizedDescription
        }
    }

    private func revert() {
        manifest = original
        saveError = nil
    }

    private func save() {
        guard let manifest else { return }
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(manifest)
            try data.write(to: fileURL, options: .atomic)
            original = manifest
            saveError = nil
        } catch {
            saveError = error.localizedDescription
        }
    }
}
