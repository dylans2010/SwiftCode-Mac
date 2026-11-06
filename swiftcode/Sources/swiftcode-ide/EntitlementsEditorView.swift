import Foundation
import SwiftUI
import SwiftCodeIDECore
import SwiftCodeIDEShell

/// The `.entitlements` editor for the Linux IDE shell: the capability
/// catalog as toggle cards grouped by section, with each capability's
/// payload editor, the validation findings, the keys no toggle manages,
/// and the raw XML. Every edit goes through `EntitlementsEditorModel`;
/// the AppKit IDE renders the same model with
/// `EntitlementsEditorController` (SwiftCodeUI).
struct EntitlementsEditorView: View {
    @Bindable var model: EntitlementsEditorModel
    @Environment(\.colorScheme) private var scheme
    @State private var status: String?
    @State private var customKey = ""
    @State private var customKeyType = "Boolean"
    @State private var rawText = ""
    @State private var showingRaw = false

    var body: some View {
        let c = ShellColors(scheme)
        VStack(spacing: 0) {
            toolbar(c)
            Hairline(color: c.separator)
            if let p = model.problem { ProblemBanner(message: p) { model.clearProblem() } }
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    fileStatusCard(c)
                    validationPanel(c)
                    ForEach(model.visibleSections) { section in
                        capabilitySection(section, c)
                    }
                    uncoveredKeysSection(c)
                    if showingRaw { rawXMLSection(c) }
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .background(c.content)
        .shellTarget("entitlements editor")
    }

    // MARK: - Toolbar

    private func toolbar(_ c: ShellColors) -> some View {
        HStack(spacing: 8) {
            TextField("Search capabilities", text: $model.searchText)
                .textFieldStyle(.roundedBorder)
                .frame(width: 240)
            Picker("Section", selection: $model.selectedSection) {
                ForEach(EntitlementCapabilitySection.allCases) { section in
                    Text(section.fullTitle).tag(section)
                }
            }
            .frame(width: 190)
            Spacer()
            if let status {
                Text(status)
                    .font(.caption)
                    .foregroundStyle(c.secondaryLabel)
            }
            Menu("Presets") {
                ForEach(EntitlementsPreset.allCases, id: \.rawValue) { preset in
                    Button(preset.rawValue) {
                        model.applyPreset(preset)
                        status = "Applied \(preset.rawValue)"
                    }
                }
            }
            Button("Validate") {
                let issues = model.validate()
                status = issues.isEmpty ? "All capabilities are valid."
                    : "Validation: \(issues.map(\.message).joined(separator: "; "))"
            }
            Button("Copy Raw XML") {
                status = "Raw XML is shown below."
                showingRaw = true
                rawText = model.xmlText()
            }
            Button("Revert") {
                do {
                    try model.revert()
                    status = "Reverted unsaved changes."
                } catch {
                    model.setProblem("Could not re-read entitlements file: \(error.localizedDescription)")
                }
            }
            .disabled(!model.isDirty)
            Button("Save") {
                do {
                    try model.save()
                    status = "Successfully saved entitlements to disk."
                } catch {
                    model.setProblem("Error saving entitlements: \(error.localizedDescription)")
                }
            }
            .disabled(!model.isDirty)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(c.sidebar)
    }

    // MARK: - Status & validation

    private func fileStatusCard(_ c: ShellColors) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.seal.fill")
                .font(.title2)
                .foregroundStyle(c.secondaryLabel)
            VStack(alignment: .leading, spacing: 2) {
                Text(model.url?.lastPathComponent ?? "Entitlements")
                    .font(.headline)
                Text(model.url?.path ?? "")
                    .font(.caption)
                    .foregroundStyle(c.secondaryLabel)
                    .lineLimit(1)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(model.entitlements.count) active")
                    .font(.subheadline)
                if let date = model.lastModified {
                    Text("Modified \(date, style: .date)")
                        .font(.caption)
                        .foregroundStyle(c.secondaryLabel)
                }
                Text(model.sandboxIsOn ? "Sandbox on" : "Sandbox off")
                    .font(.caption)
                    .foregroundStyle(c.secondaryLabel)
            }
        }
        .padding(12)
        .background(c.sidebar, in: RoundedRectangle(cornerRadius: 8))
    }

    private func validationPanel(_ c: ShellColors) -> some View {
        let issues = model.validate()
        return Group {
            if !issues.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Entitlement Issues (\(issues.count))", systemImage: "exclamationmark.triangle")
                        .font(.headline)
                        .foregroundStyle(c.secondaryLabel)
                    ForEach(issues) { issue in
                        HStack(alignment: .top) {
                            Image(systemName: issue.severity == .error ? "xmark.octagon.fill" : "exclamationmark.triangle.fill")
                                .foregroundStyle(issue.severity == .error ? c.error : c.warning)
                            VStack(alignment: .leading) {
                                Text(issue.message)
                                Text(issue.rawKey)
                                    .font(.caption)
                                    .foregroundStyle(c.secondaryLabel)
                            }
                        }
                    }
                }
                .padding(.horizontal, 4)
            }
        }
    }

    // MARK: - Capabilities

    private func capabilitySection(_ section: EntitlementCapabilitySection, _ c: ShellColors) -> some View {
        let defs = EntitlementCapabilityCatalog.definitions(in: section)
            .filter { model.capabilityMatchesSearch($0) }
        return Group {
            if !defs.isEmpty {
                Text(section.fullTitle).font(.headline)
                ForEach(defs) { def in
                    capabilityCard(def, c)
                }
            }
        }
    }

    private func capabilityCard(_ def: CapabilityDefinition, _ c: ShellColors) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: def.symbol)
                    .foregroundStyle(c.secondaryLabel)
                VStack(alignment: .leading, spacing: 2) {
                    Text(def.name).font(.headline)
                    Text(def.rawKey)
                        .font(.caption)
                        .foregroundStyle(c.secondaryLabel)
                }
                Spacer()
                if def.requiresSpecialApproval {
                    Text("Special approval")
                        .font(.caption)
                        .foregroundStyle(c.warning)
                }
                Toggle("", isOn: Binding(
                    get: { model.isCapabilityOn(def) },
                    set: { model.setCapability(def, on: $0) }
                ))
                .labelsHidden()
            }
            Text(def.explanation)
                .font(.callout)
                .foregroundStyle(c.secondaryLabel)
            if model.isCapabilityOn(def) {
                capabilityPayloadEditor(def, c)
            }
        }
        .padding(10)
        .background(c.sidebar, in: RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private func capabilityPayloadEditor(_ def: CapabilityDefinition, _ c: ShellColors) -> some View {
        switch def.payload {
        case .none:
            EmptyView()
        case .idList(let placeholder):
            IDListEditor(ids: Binding(
                get: { model.stringArray(forKey: def.rawKey) },
                set: { model.setStringArray($0, forKey: def.rawKey) }
            ), placeholder: placeholder)
        case .fixedValueList(let allowed):
            FixedValueListEditor(values: Binding(
                get: { model.stringArray(forKey: def.rawKey) },
                set: { model.setStringArray($0, forKey: def.rawKey) }
            ), allowed: allowed)
        case .choice(let options):
            Picker("Value", selection: Binding(
                get: { model.string(forKey: def.rawKey, fallback: options.first ?? "") },
                set: { model.setString($0, forKey: def.rawKey) }
            )) {
                ForEach(options, id: \.self) { option in Text(option).tag(option) }
            }
        case .stringValue(let placeholder):
            TextField(placeholder, text: Binding(
                get: { model.string(forKey: def.rawKey, fallback: "") },
                set: { model.setString($0, forKey: def.rawKey) }
            ))
            .textFieldStyle(.roundedBorder)
        case .prefixedList(let prefixes, let placeholder):
            AssociatedDomainsEditor(domains: Binding(
                get: { model.stringArray(forKey: def.rawKey) },
                set: { model.setStringArray($0, forKey: def.rawKey) }
            ), prefixes: prefixes, placeholder: placeholder)
        case .iCloudComposite:
            ICloudCompositeEditor(model: model)
        }
    }

    // MARK: - Uncovered keys

    private func uncoveredKeysSection(_ c: ShellColors) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Other Keys").font(.headline)
            Text("Entitlement keys present in the file that no capability toggle manages.")
                .font(.callout)
                .foregroundStyle(c.secondaryLabel)
            ForEach(model.uncoveredKeys, id: \.self) { key in
                HStack {
                    Text(key).font(.subheadline)
                    Spacer()
                    Text(entitlementSummary(model.entitlements[key]!))
                        .font(.caption)
                        .foregroundStyle(c.secondaryLabel)
                    Button("Remove", role: .destructive) { model.set(nil, forKey: key) }
                }
            }
            HStack {
                TextField("Add a key, e.g. com.example.custom", text: $customKey)
                    .textFieldStyle(.roundedBorder)
                Picker("Type", selection: $customKeyType) {
                    ForEach(["Boolean", "String", "Array"], id: \.self) { Text($0).tag($0) }
                }
                .frame(width: 110)
                Button("Add") {
                    let key = customKey.trimmingCharacters(in: .whitespaces)
                    guard !key.isEmpty, model.entitlements[key] == nil else { return }
                    switch customKeyType {
                    case "String": model.setString("", forKey: key)
                    case "Array": model.setStringArray([], forKey: key)
                    default: model.setBool(false, forKey: key)
                    }
                    customKey = ""
                }
                .disabled(customKey.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }

    // MARK: - Raw XML

    private func rawXMLSection(_ c: ShellColors) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Raw XML").font(.headline)
                Spacer()
                Button("Apply XML") {
                    do {
                        try model.setXMLText(rawText)
                        status = "Applied raw XML."
                    } catch {
                        model.setProblem("Raw XML is not a valid entitlements dictionary: \(error.localizedDescription)")
                    }
                }
                Button("Reload") { rawText = model.xmlText() }
            }
            TextEditor(text: $rawText)
                .font(.system(.body, design: .monospaced))
                .frame(height: 220)
                .border(c.separator)
        }
    }
}

/// An editable list of string identifiers (App Groups, keychain groups,
/// merchant identifiers, …), as Legacy's `EntitlementIDListEditor`.
private struct IDListEditor: View {
    @Binding var ids: [String]
    let placeholder: String
    @State private var newID = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(ids, id: \.self) { id in
                HStack {
                    Text(id)
                    Spacer()
                    Button("Remove") { ids.removeAll { $0 == id } }
                }
            }
            HStack {
                TextField(placeholder, text: $newID)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { addID() }
                Button("Add") { addID() }
                    .disabled(newID.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }

    private func addID() {
        let value = newID.trimmingCharacters(in: .whitespaces)
        guard !value.isEmpty, !ids.contains(value) else { return }
        ids.append(value)
        newID = ""
    }
}

/// A list restricted to a fixed set of values (iCloud services,
/// Sign in with Apple), as Legacy's `FixedValueListEditor`.
private struct FixedValueListEditor: View {
    @Binding var values: [String]
    let allowed: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(allowed, id: \.self) { option in
                Toggle(option, isOn: Binding(
                    get: { values.contains(option) },
                    set: { on in
                        if on, !values.contains(option) { values.append(option) }
                        if !on { values.removeAll { $0 == option } }
                    }
                ))
            }
        }
    }
}

/// Associated domains: a prefix picker plus a host field, as Legacy's
/// `AssociatedDomainsEditor`.
private struct AssociatedDomainsEditor: View {
    @Binding var domains: [String]
    let prefixes: [String]
    let placeholder: String
    @State private var selectedPrefix = 0
    @State private var host = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(domains, id: \.self) { domain in
                HStack {
                    Text(domain)
                    Spacer()
                    Button("Remove") { domains.removeAll { $0 == domain } }
                }
            }
            HStack {
                Picker("Prefix", selection: $selectedPrefix) {
                    ForEach(prefixes.indices, id: \.self) { i in Text(prefixes[i]).tag(i) }
                }
                .frame(width: 190)
                TextField(placeholder, text: $host)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { addDomain() }
                Button("Add") { addDomain() }
                    .disabled(host.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }

    private func addDomain() {
        let host = host.trimmingCharacters(in: .whitespaces)
        guard !host.isEmpty else { return }
        let domain = prefixes[selectedPrefix] + host
        guard !domains.contains(domain) else { return }
        domains.append(domain)
        self.host = ""
    }
}

/// The iCloud composite: container identifiers, the key-value store
/// identifier, and the ubiquitous containers, as Legacy's
/// `ICloudCompositeEditor` + `UbiquitousContainersEditor`.
private struct ICloudCompositeEditor: View {
    @Bindable var model: EntitlementsEditorModel
    @State private var newContainer = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Container Identifiers").font(.subheadline)
            IDListEditor(ids: Binding(
                get: { model.iCloudContainers() },
                set: { model.setICloudContainers($0) }
            ), placeholder: "iCloud.$(CFBundleIdentifier)")
            HStack {
                Text("Key-Value Store")
                TextField("$(TeamIdentifierPrefix)$(CFBundleIdentifier)", text: Binding(
                    get: { model.iCloudKVStore() },
                    set: { model.setICloudKVStore($0) }
                ))
                .textFieldStyle(.roundedBorder)
            }
            Text("Ubiquitous Containers").font(.subheadline)
            ForEach(model.ubiquitousContainers(), id: \.id) { container in
                HStack {
                    Text(container.id)
                    Spacer()
                    TextField("Name", text: Binding(
                        get: { container.name },
                        set: { model.setUbiquitousContainer(id: container.id, name: $0, isPublic: container.isPublic, folderLevels: container.folderLevels) }
                    ))
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 140)
                    Toggle("Public", isOn: Binding(
                        get: { container.isPublic },
                        set: { model.setUbiquitousContainer(id: container.id, name: container.name, isPublic: $0, folderLevels: container.folderLevels) }
                    ))
                    Button("Remove") { model.removeUbiquitousContainer(id: container.id) }
                }
            }
            HStack {
                TextField("New container identifier", text: $newContainer)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { addContainer() }
                Button("Add Container") { addContainer() }
                    .disabled(newContainer.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }

    private func addContainer() {
        let id = newContainer.trimmingCharacters(in: .whitespaces)
        guard !id.isEmpty else { return }
        model.setUbiquitousContainer(id: id, name: id, isPublic: false, folderLevels: "")
        newContainer = ""
    }
}


// Ported from Legacy `SwiftCode/Views/Editor/EntitlementsEditorView.swift` (Audit E §5 partial entry; H-E5).
// Types ported here: EntitlementIDListEditor, UbiquitousContainersEditor, EntitlementDictionaryEditor, EntitlementRowView.

struct EntitlementIDListEditor: View {
    @Binding var ids: [String]
    let placeholder: String
    @State private var newID = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if ids.isEmpty {
                Text("No identifiers yet. Add one below.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ForEach(ids, id: \.self) { id in
                HStack {
                    Image(systemName: "tag")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(id)
                        .font(.system(.body, design: .monospaced))
                    Spacer()
                    Button {
                        ids.removeAll { $0 == id }
                    } label: {
                        Image(systemName: "minus.circle")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Remove identifier")
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color(NSColor.textBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
            }
            HStack {
                TextField(placeholder, text: $newID)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
                    .onSubmit { addID() }
                Button("Add") { addID() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(addDisabled)
            }
            if duplicateWarning {
                Text("That identifier is already in the list.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var trimmedNewID: String {
        newID.trimmingCharacters(in: .whitespaces)
    }

    private var duplicateWarning: Bool {
        !trimmedNewID.isEmpty && ids.contains(trimmedNewID)
    }

    private var addDisabled: Bool {
        trimmedNewID.isEmpty || ids.contains(trimmedNewID)
    }

    private func addID() {
        guard !addDisabled else { return }
        ids.append(trimmedNewID)
        newID = ""
    }
}

/// Honest model of the real NSUbiquitousContainers dictionary: each container ID
/// maps to a dictionary with NSUbiquitousContainerName (String),
/// NSUbiquitousContainerIsDocumentScopePublic (Boolean), and
/// NSUbiquitousContainerSupportedFolderLevels (None / One / Any).
struct UbiquitousContainersEditor: View {
    @Binding var containers: [String: [String: Any]]
    @State private var newID = ""

    private enum Keys {
        static let name = "NSUbiquitousContainerName"
        static let isPublic = "NSUbiquitousContainerIsDocumentScopePublic"
        static let folderLevels = "NSUbiquitousContainerSupportedFolderLevels"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Ubiquitous Containers (NSUbiquitousContainers)")
                .font(.caption)
                .foregroundStyle(.secondary)
            if containers.isEmpty {
                Text("No ubiquitous containers configured. Add one below if the app declares document containers.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ForEach(containers.keys.sorted(), id: \.self) { id in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Image(systemName: "shippingbox")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(id)
                            .font(.system(.body, design: .monospaced))
                        Spacer()
                        Button {
                            containers.removeValue(forKey: id)
                        } label: {
                            Image(systemName: "minus.circle")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help("Remove container")
                    }
                    TextField("Display name", text: nameBinding(for: id))
                        .textFieldStyle(.roundedBorder)
                    Toggle("Document scope is public", isOn: publicBinding(for: id))
                    Picker("Folder levels", selection: folderLevelsBinding(for: id)) {
                        Text("None").tag("None")
                        Text("One").tag("One")
                        Text("Any").tag("Any")
                    }
                    .pickerStyle(.segmented)
                    Divider()
                }
            }
            HStack {
                TextField("iCloud.com.example.container", text: $newID)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
                    .onSubmit { addContainer() }
                Button("Add") { addContainer() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(trimmedNewID.isEmpty || containers[trimmedNewID] != nil)
            }
        }
    }

    private var trimmedNewID: String {
        newID.trimmingCharacters(in: .whitespaces)
    }

    private func addContainer() {
        guard !trimmedNewID.isEmpty, containers[trimmedNewID] == nil else { return }
        containers[trimmedNewID] = [
            Keys.name: "",
            Keys.isPublic: false,
            Keys.folderLevels: "None"
        ]
        newID = ""
    }

    private func nameBinding(for id: String) -> Binding<String> {
        Binding(
            get: { containers[id]?[Keys.name] as? String ?? "" },
            set: {
                var entry = containers[id] ?? [:]
                entry[Keys.name] = $0
                containers[id] = entry
            }
        )
    }

    private func publicBinding(for id: String) -> Binding<Bool> {
        Binding(
            get: { containers[id]?[Keys.isPublic] as? Bool ?? false },
            set: {
                var entry = containers[id] ?? [:]
                entry[Keys.isPublic] = $0
                containers[id] = entry
            }
        )
    }

    private func folderLevelsBinding(for id: String) -> Binding<String> {
        Binding(
            get: { containers[id]?[Keys.folderLevels] as? String ?? "None" },
            set: {
                var entry = containers[id] ?? [:]
                entry[Keys.folderLevels] = $0
                containers[id] = entry
            }
        )
    }
}

struct EntitlementDictionaryEditor: View {
    @Binding var entries: [String: String]
    @State private var newKey = ""
    @State private var newValue = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if entries.isEmpty {
                Text("Empty dictionary.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ForEach(entries.keys.sorted(), id: \.self) { key in
                HStack {
                    Image(systemName: "curlybraces")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(key)
                        .font(.system(.body, design: .monospaced))
                    Image(systemName: "arrow.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    TextField("Value", text: Binding(
                        get: { entries[key] ?? "" },
                        set: { entries[key] = $0 }
                    ))
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
                    Button {
                        entries.removeValue(forKey: key)
                    } label: {
                        Image(systemName: "minus.circle")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Remove entry")
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color(NSColor.textBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
            }
            HStack {
                TextField("Key", text: $newKey)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
                TextField("Value", text: $newValue)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
                    .onSubmit { addEntry() }
                Button("Add") { addEntry() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(trimmedKey.isEmpty || entries[trimmedKey] != nil)
            }
        }
    }

    private var trimmedKey: String {
        newKey.trimmingCharacters(in: .whitespaces)
    }

    private func addEntry() {
        guard !trimmedKey.isEmpty, entries[trimmedKey] == nil else { return }
        entries[trimmedKey] = newValue
        newKey = ""
        newValue = ""
    }
}

struct EntitlementRowView: View {
    let key: String
    let value: Any
    let onSelect: () -> Void
    let onDuplicate: () -> Void
    let onDelete: () -> Void
    let onValueChange: (Any) -> Void

    private var typeIcon: String {
        if value is Bool { return "switch.2" }
        if value is [String] { return "list.bullet" }
        if value is [Any] { return "list.bullet" }
        if value is [String: Any] { return "curlybraces" }
        return "textformat"
    }

    private var typeName: String {
        if value is Bool { return "Boolean" }
        if value is [String] { return "Array of Strings" }
        if value is [Any] { return "Array" }
        if value is [String: String] { return "Dictionary (String values)" }
        if value is [String: Any] { return "Dictionary" }
        if value is String { return "String" }
        return "Value"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Image(systemName: typeIcon)
                    .foregroundStyle(.secondary)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text(key)
                        .font(.system(.body, design: .monospaced).weight(.medium))
                        .lineLimit(1)
                    if let meta = EntitlementsCatalog.all.first(where: { $0.rawKey == key }) {
                        Text(meta.displayName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text(typeName)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
                .frame(minWidth: 220, alignment: .leading)

                Spacer()

                if let boolVal = value as? Bool {
                    Toggle("", isOn: Binding(
                        get: { boolVal },
                        set: { onValueChange($0) }
                    ))
                    .toggleStyle(.switch)
                    .labelsHidden()
                }

                // Inspect
                Button(action: onSelect) {
                    Image(systemName: "slider.horizontal.3")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Inspect Capability")

                // Duplicate
                Button(action: onDuplicate) {
                    Image(systemName: "plus.square.on.square")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Duplicate Capability")

                // Delete
                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Remove Capability")
            }

            valueEditor
                .padding(.leading, 36)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private var valueEditor: some View {
        if value is Bool {
            EmptyView()
        } else if value is [String] {
            EntitlementIDListEditor(
                ids: Binding(
                    get: { value as? [String] ?? [] },
                    set: { onValueChange($0) }
                ),
                placeholder: "value"
            )
        } else if let arrVal = value as? [Any] {
            Text("\(arrVal.count) entries (non-string array — remove and re-add to edit inline)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color(NSColor.controlBackgroundColor), in: RoundedRectangle(cornerRadius: 4))
        } else if value is [String: String] {
            EntitlementDictionaryEditor(
                entries: Binding(
                    get: { value as? [String: String] ?? [:] },
                    set: { onValueChange($0) }
                )
            )
        } else if let dictVal = value as? [String: Any] {
            Text("Dictionary with \(dictVal.count) entries (non-string values — remove and re-add to edit inline)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color(NSColor.controlBackgroundColor), in: RoundedRectangle(cornerRadius: 4))
        } else {
            TextField("", text: Binding(
                get: { String(describing: value) },
                set: { onValueChange($0) }
            ))
            .textFieldStyle(.roundedBorder)
            .font(.system(.body, design: .monospaced))
            .frame(minWidth: 160, maxWidth: 400)
        }
    }
}
