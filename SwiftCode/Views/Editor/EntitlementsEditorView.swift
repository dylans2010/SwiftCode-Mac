import SwiftUI

// MARK: - Entitlements Editor View

/// UI-only editor for the entitlements plist. Every control reads and writes the
/// real entitlements dictionary; there is intentionally no raw XML editing.
public struct EntitlementsEditorView: View {
    private let fileURL: URL?
    @State private var manager: EntitlementsEditorManager
    @State private var entitlementsDict: [String: Any] = [:]
    @State private var searchQuery = ""
    @State private var selectedFilter: EntitlementCapabilitySection = .all
    @State private var selectedKey: String? = nil
    @State private var showingAddSheet = false
    @State private var showingInspectorSheet = false
    @State private var toolStatus: String? = nil
    @State private var isDirty = false
    @State private var fileModifiedDate: Date? = nil
    @State private var customKey = ""
    @State private var customKeyType = "boolean"
    @State private var addSheetSearch = ""
    @State private var addSheetSection: EntitlementCapabilitySection = .all
    @Environment(WorkspaceViewModel.self) private var workspaceViewModel
    @State private var isCreating = false
    @State private var creationError: String? = nil

    public init(fileURL: URL?) {
        self.fileURL = fileURL
        let m = EntitlementsEditorManager(fileURL: fileURL ?? URL(fileURLWithPath: "/dev/null"))
        _manager = State(initialValue: m)
        if let url = fileURL {
            _entitlementsDict = State(initialValue: (try? m.readEntitlements()) ?? [:])
            _fileModifiedDate = State(initialValue: Self.modifiedDate(of: url))
        } else {
            _entitlementsDict = State(initialValue: [:])
            _fileModifiedDate = State(initialValue: nil)
        }
    }

    private static func modifiedDate(of url: URL) -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate] as? Date) ?? nil
    }

    private func createEntitlements() {
        guard let project = ProjectSessionStore.shared.activeProject else {
            creationError = "No active project found in session."
            return
        }

        isCreating = true
        creationError = nil

        let targetURL = project.directoryURL.appendingPathComponent("\(project.name).entitlements")
        let defaultContent = """
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.app-sandbox</key>
    <true/>
    <key>com.apple.security.files.user-selected.read-write</key>
    <true/>
</dict>
</plist>
"""

        Task {
            do {
                try defaultContent.write(to: targetURL, atomically: true, encoding: .utf8)
                ProjectSessionStore.shared.refreshFileTree(for: project)
                await workspaceViewModel.editor.openFile(url: targetURL)
                await workspaceViewModel.editor.updateActiveConfigurationURLs(for: project)
                isCreating = false
            } catch {
                isCreating = false
                creationError = "Failed to create Entitlements: \(error.localizedDescription)"
            }
        }
    }

    // MARK: - Capability State Helpers

    private func isCapabilityOn(_ def: CapabilityDefinition) -> Bool {
        if def.rawKey == CapabilityCatalog.iCloudContainersKey {
            return entitlementsDict[CapabilityCatalog.iCloudContainersKey] != nil
                || entitlementsDict[CapabilityCatalog.iCloudKVStoreKey] != nil
                || entitlementsDict[CapabilityCatalog.ubiquitousContainersKey] != nil
        }
        return entitlementsDict[def.rawKey] != nil
    }

    private func setCapability(_ def: CapabilityDefinition, on: Bool) {
        if def.rawKey == CapabilityCatalog.iCloudContainersKey {
            if on {
                if entitlementsDict[CapabilityCatalog.iCloudContainersKey] == nil {
                    entitlementsDict[CapabilityCatalog.iCloudContainersKey] = [String]()
                }
                if entitlementsDict[CapabilityCatalog.iCloudKVStoreKey] == nil {
                    entitlementsDict[CapabilityCatalog.iCloudKVStoreKey] = "$(TeamIdentifierPrefix)$(CFBundleIdentifier)"
                }
            } else {
                entitlementsDict.removeValue(forKey: CapabilityCatalog.iCloudContainersKey)
                entitlementsDict.removeValue(forKey: CapabilityCatalog.iCloudKVStoreKey)
                entitlementsDict.removeValue(forKey: CapabilityCatalog.ubiquitousContainersKey)
            }
        } else if on {
            entitlementsDict[def.rawKey] = def.defaultValue
        } else {
            entitlementsDict.removeValue(forKey: def.rawKey)
        }
        markDirty()
    }

    private func markDirty() {
        isDirty = true
    }

    private var sandboxIsOn: Bool {
        (entitlementsDict["com.apple.security.app-sandbox"] as? Bool) ?? false
    }

    /// Entitlement keys present in the file that no capability toggle manages.
    private var uncoveredKeys: [String] {
        let known = Set(CapabilityCatalog.allRawKeys)
        return entitlementsDict.keys
            .filter { !known.contains($0) }
            .sorted()
            .filter { key in
                guard !searchQuery.isEmpty else { return true }
                let q = searchQuery.lowercased()
                return key.lowercased().contains(q)
                    || String(describing: entitlementsDict[key] ?? "").lowercased().contains(q)
            }
    }

    private func capabilityMatchesSearch(_ def: CapabilityDefinition) -> Bool {
        guard !searchQuery.isEmpty else { return true }
        let q = searchQuery.lowercased()
        if def.name.lowercased().contains(q)
            || def.rawKey.lowercased().contains(q)
            || def.explanation.lowercased().contains(q) {
            return true
        }
        // Also match against the key's current value.
        for key in [def.rawKey] + def.compositeKeys {
            if String(describing: entitlementsDict[key] ?? "").lowercased().contains(q) {
                return true
            }
        }
        return false
    }

    private var visibleSections: [EntitlementCapabilitySection] {
        switch selectedFilter {
        case .all:
            return [.sandbox, .hardenedRuntime, .cloud, .sharing, .personal, .services, .systemExtensions]
        case .other:
            return []
        default:
            return [selectedFilter]
        }
    }

    /// Base validation plus cross-entitlement checks, deduplicated by message.
    private var combinedIssues: (errors: [EntitlementError], warnings: [EntitlementWarning]) {
        let base = manager.validate(entitlementsDict)
        let extra = manager.crossEntitlementIssues(entitlementsDict)
        var seen = Set(base.errors.map(\.message) + base.warnings.map(\.message))
        var errors = base.errors
        var warnings = base.warnings
        for e in extra.errors where seen.insert(e.message).inserted { errors.append(e) }
        for w in extra.warnings where seen.insert(w.message).inserted { warnings.append(w) }
        return (errors, warnings)
    }

    private func stringArrayBinding(for key: String) -> Binding<[String]> {
        Binding(
            get: { entitlementsDict[key] as? [String] ?? [] },
            set: {
                entitlementsDict[key] = $0
                markDirty()
            }
        )
    }

    private func stringBinding(for key: String, fallback: String) -> Binding<String> {
        Binding(
            get: { entitlementsDict[key] as? String ?? fallback },
            set: {
                entitlementsDict[key] = $0
                markDirty()
            }
        )
    }

    public var body: some View {
        if fileURL == nil {
            VStack(spacing: 20) {
                ContentUnavailableView {
                    Label("No Entitlements Configured", systemImage: "lock.shield")
                } description: {
                    Text("The currently selected target does not contain an Entitlements configuration file.\n\nYou can create a standard entitlements file in your project workspace.")
                }

                if let error = creationError {
                    Text(error)
                        .foregroundStyle(.secondary)
                        .font(.callout)
                }

                Button {
                    createEntitlements()
                } label: {
                    Label(isCreating ? "Creating..." : "Create Entitlements", systemImage: "plus")
                        .font(.headline)
                        .frame(minWidth: 160)
                }
                .buttonStyle(.bordered)
                .disabled(isCreating)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(NSColor.windowBackgroundColor))
        } else {
            VStack(spacing: 0) {
                // Professional Header Toolbar with Tool Actions
                headerToolbar

                Divider()

                Divider()

                // Modern Category Filter Pills with Active Counts
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(EntitlementCapabilitySection.allCases) { cat in
                            let isSelected = selectedFilter == cat
                            let count = countForSection(cat)
                            Button {
                                selectedFilter = cat
                            } label: {
                                HStack(spacing: 5) {
                                    Image(systemName: cat.icon)
                                        .font(.caption2)
                                    Text(cat.rawValue)
                                        .font(.caption.weight(isSelected ? .semibold : .regular))
                                    if count > 0 && cat != .all {
                                        Text("\(count)")
                                            .font(.system(size: 10, weight: .bold))
                                            .padding(.horizontal, 5)
                                            .padding(.vertical, 1)
                                            .background(isSelected ? Color.white.opacity(0.3) : Color.secondary.opacity(0.2), in: Capsule())
                                    }
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(isSelected ? Color.teal : Color.secondary.opacity(0.12), in: Capsule())
                                .foregroundStyle(isSelected ? Color.white : Color.primary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                }
                .background(Color(NSColor.controlBackgroundColor).opacity(0.5))

                Divider()

                // Feedback status banner
                if let status = toolStatus {
                    HStack {
                        Image(systemName: "info.circle")
                            .font(.caption)
                        Text(status)
                            .font(.caption)
                        Spacer()
                        Button { toolStatus = nil } label: {
                            Image(systemName: "xmark")
                                .font(.caption2)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 4)
                    .background(Color(NSColor.secondarySystemFill))
                    Divider()
                }

                // Main Content View
                capabilitiesListView
            }
            .sheet(isPresented: $showingAddSheet) {
                addCapabilitySheet
            }
            .sheet(isPresented: $showingInspectorSheet) {
                inspectorSheetView
            }
            .onAppear {
                reloadFromDisk()
            }
            .onChange(of: fileURL) { _, newURL in
                if let url = newURL {
                    manager = EntitlementsEditorManager(fileURL: url)
                    reloadFromDisk()
                }
            }
        }
    }

    private func countForSection(_ section: EntitlementCapabilitySection) -> Int {
        if section == .all {
            return entitlementsDict.count
        }
        let defs = CapabilityCatalog.definitions(for: section)
        return defs.filter { isCapabilityOn($0) }.count
    }

    private func reloadFromDisk() {
        guard let url = fileURL else { return }
        do {
            entitlementsDict = try manager.readEntitlements()
            fileModifiedDate = Self.modifiedDate(of: url)
            isDirty = false
        } catch {
            toolStatus = "Could not read entitlements file: \(error.localizedDescription)"
        }
    }

    // MARK: - Header Toolbar
    private var headerToolbar: some View {
        HStack(spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "lock.shield.fill")
                    .foregroundStyle(.teal)
                Text(fileURL?.lastPathComponent ?? "App.entitlements")
                    .font(.headline)
                Text("(\(entitlementsDict.count) active)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if isDirty {
                    Text("Unsaved")
                        .font(.caption2.bold())
                        .foregroundStyle(.orange)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.orange.opacity(0.12), in: Capsule())
                } else {
                    Text("Saved")
                        .font(.caption2.bold())
                        .foregroundStyle(.green)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.green.opacity(0.12), in: Capsule())
                }
            }

            Spacer()

            // Search Bar
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search entitlements...", text: $searchQuery)
                    .textFieldStyle(.plain)
                if !searchQuery.isEmpty {
                    Button { searchQuery = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Color(NSColor.controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
            .frame(width: 200)

            // Primary Add Capability Button
            Button {
                showingAddSheet = true
            } label: {
                Label("Capability", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
            .tint(.teal)

            // Save Tool
            Button {
                saveChanges()
            } label: {
                Label("Save", systemImage: "square.and.arrow.down")
            }
            .buttonStyle(.bordered)
            .disabled(!isDirty)
            .keyboardShortcut("s", modifiers: .command)

            // More Actions Menu (Consolidating presets, validation, XML, revert)
            Menu {
                Menu("Capability Presets") {
                    Button {
                        applyPreset(keys: [
                            "com.apple.security.app-sandbox": true,
                            "com.apple.security.files.user-selected.read-write": true,
                            "com.apple.security.network.client": true
                        ])
                        toolStatus = "Applied App Store Sandbox Preset"
                    } label: {
                        Label("App Store Sandbox (macOS)", systemImage: "cube.transparent")
                    }

                    Button {
                        applyPreset(keys: [
                            "com.apple.security.cs.allow-jit": true,
                            "com.apple.security.cs.allow-unsigned-executable-memory": true,
                            "com.apple.security.cs.disable-library-validation": true
                        ])
                        toolStatus = "Applied Hardened Runtime Developer Tool Preset"
                    } label: {
                        Label("Developer Tool Hardened Runtime", systemImage: "hammer")
                    }

                    Button {
                        applyPreset(keys: [
                            "com.apple.security.device.camera": true,
                            "com.apple.security.device.audio-input": true,
                            "com.apple.security.personal-information.photos-library": true
                        ])
                        toolStatus = "Applied Media & Hardware Preset"
                    } label: {
                        Label("Media & Hardware Access", systemImage: "camera")
                    }

                    Button {
                        applyPreset(keys: [
                            CapabilityCatalog.iCloudContainersKey: ["iCloud.$(CFBundleIdentifier)"],
                            CapabilityCatalog.iCloudKVStoreKey: "$(TeamIdentifierPrefix)$(CFBundleIdentifier)"
                        ])
                        toolStatus = "Applied iCloud & CloudKit Preset"
                    } label: {
                        Label("iCloud Key-Value & Containers", systemImage: "icloud")
                    }
                }

                Divider()

                Button {
                    validateEntitlements()
                } label: {
                    Label("Validate Capabilities", systemImage: "checkmark.seal")
                }

                Button {
                    let xml = manager.generateRawXML(entitlementsDict)
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(xml, forType: .string)
                    toolStatus = "Copied entitlements XML to clipboard"
                } label: {
                    Label("Copy Raw XML", systemImage: "doc.on.doc")
                }

                Divider()

                Button(role: .destructive) {
                    revertChanges()
                } label: {
                    Label("Revert to Saved", systemImage: "arrow.uturn.backward")
                }
                .disabled(!isDirty)
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.body)
            }
            .menuStyle(.borderlessButton)
            .frame(width: 24, height: 24)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color(NSColor.windowBackgroundColor))
    }

    private func applyPreset(keys: [String: Any]) {
        for (k, v) in keys {
            entitlementsDict[k] = v
        }
        markDirty()
    }

    private func saveChanges() {
        do {
            try manager.writeEntitlements(entitlementsDict)
            isDirty = false
            if let url = fileURL {
                fileModifiedDate = Self.modifiedDate(of: url)
            }
            toolStatus = "Successfully saved entitlements to disk."
        } catch {
            toolStatus = "Error saving entitlements: \(error.localizedDescription)"
        }
    }

    private func revertChanges() {
        do {
            entitlementsDict = try manager.readEntitlements()
            isDirty = false
            if let url = fileURL {
                fileModifiedDate = Self.modifiedDate(of: url)
            }
            toolStatus = "Reverted unsaved changes."
        } catch {
            toolStatus = "Could not re-read entitlements file: \(error.localizedDescription)"
        }
    }

    private func validateEntitlements() {
        let issues = combinedIssues
        if issues.errors.isEmpty && issues.warnings.isEmpty {
            toolStatus = "All capabilities are valid."
        } else {
            let allIssues = issues.errors.map(\.message) + issues.warnings.map(\.message)
            toolStatus = "Validation: \(allIssues.joined(separator: "; "))"
        }
    }

    // MARK: - File Status Card
    private var fileStatusCard: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.seal.fill")
                .font(.title2)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(fileURL?.lastPathComponent ?? "Entitlements")
                    .font(.headline)
                Text(fileURL?.path ?? "")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(entitlementsDict.count) active")
                    .font(.subheadline.weight(.medium))
                if let date = fileModifiedDate {
                    Text("Modified \(date, style: .date)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text(sandboxIsOn ? "Sandbox on" : "Sandbox off")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(Color(NSColor.controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Cross-Entitlement Issues Panel
    @ViewBuilder
    private var validationIssuesPanel: some View {
        let issues = combinedIssues
        if !issues.errors.isEmpty || !issues.warnings.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Label(
                    "Entitlement Issues (\(issues.errors.count + issues.warnings.count))",
                    systemImage: "exclamationmark.triangle"
                )
                .font(.headline)
                .foregroundStyle(.secondary)
                ForEach(issues.errors) { error in
                    issueRow(icon: "xmark.octagon.fill", rawKey: error.rawKey, message: error.message)
                }
                ForEach(issues.warnings) { warning in
                    issueRow(icon: "exclamationmark.triangle.fill", rawKey: warning.rawKey, message: warning.message)
                }
            }
            .padding(.horizontal, 16)
        }
    }

    private func issueRow(icon: String, rawKey: String, message: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(.secondary)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(rawKey)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                Text(message)
                    .font(.callout)
            }
            Spacer()
        }
        .padding(10)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.6), in: RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Capabilities List View
    private var capabilitiesListView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                fileStatusCard
                    .padding(.horizontal, 16)
                    .padding(.top, 12)

                validationIssuesPanel

                ForEach(visibleSections) { section in
                    capabilitySection(section)
                }

                if selectedFilter == .all || selectedFilter == .other {
                    otherKeysSection
                }
            }
            .padding(.bottom, 20)
        }
    }

    @ViewBuilder
    private func capabilitySection(_ section: EntitlementCapabilitySection) -> some View {
        let defs = CapabilityCatalog.definitions(for: section).filter(capabilityMatchesSearch)
        if !defs.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Label(section.fullTitle, systemImage: section.icon)
                    .font(.headline)
                    .foregroundStyle(.secondary)
                if section == .systemExtensions {
                    Label(
                        "Requires a special entitlement request to Apple — the key alone does not grant access.",
                        systemImage: "exclamationmark.triangle"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                ForEach(defs) { def in
                    capabilityCard(def)
                }
            }
            .padding(.horizontal, 16)
        }
    }

    private func capabilityCard(_ def: CapabilityDefinition) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Image(systemName: def.symbol)
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .frame(width: 32)
                VStack(alignment: .leading, spacing: 2) {
                    Text(def.name)
                        .font(.body.weight(.medium))
                    Text(def.explanation)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if def.requiresSpecialApproval {
                        Label(
                            "Requires a special entitlement request to Apple — the key alone does not grant access.",
                            systemImage: "exclamationmark.triangle"
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if isCapabilityOn(def) {
                    Button {
                        setCapability(def, on: false)
                        toolStatus = "Removed \(def.rawKey)"
                    } label: {
                        Image(systemName: "arrow.counterclockwise")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Remove \(def.rawKey) from the entitlements file")
                }
                Toggle("", isOn: Binding(
                    get: { isCapabilityOn(def) },
                    set: { setCapability(def, on: $0) }
                ))
                .toggleStyle(.switch)
                .labelsHidden()
                .help("Adds or removes \(def.rawKey)")
            }

            if isCapabilityOn(def) {
                capabilityPayloadEditor(def)
                    .padding(.leading, 44)
            }

            Text(def.rawKey)
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(.tertiary)
                .padding(.leading, 44)
        }
        .padding(12)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.6), in: RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private func capabilityPayloadEditor(_ def: CapabilityDefinition) -> some View {
        switch def.payload {
        case .none:
            EmptyView()
        case .idList(let placeholder):
            EntitlementIDListEditor(
                ids: stringArrayBinding(for: def.rawKey),
                placeholder: placeholder
            )
        case .fixedValueList(let allowed):
            FixedValueListEditor(
                values: stringArrayBinding(for: def.rawKey),
                allowed: allowed
            )
        case .choice(let options):
            Picker("Value", selection: stringBinding(for: def.rawKey, fallback: options.first ?? "")) {
                ForEach(options, id: \.self) { option in
                    Text(option).tag(option)
                }
            }
            .pickerStyle(.segmented)
        case .stringValue(let placeholder):
            TextField(placeholder, text: stringBinding(for: def.rawKey, fallback: ""))
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))
        case .prefixedList(let prefixes, let placeholder):
            AssociatedDomainsEditor(
                domains: stringArrayBinding(for: def.rawKey),
                prefixes: prefixes,
                placeholder: placeholder
            )
        case .iCloudComposite:
            ICloudCompositeEditor(
                containers: Binding(
                    get: { entitlementsDict[CapabilityCatalog.iCloudContainersKey] as? [String] ?? [] },
                    set: {
                        entitlementsDict[CapabilityCatalog.iCloudContainersKey] = $0
                        markDirty()
                    }
                ),
                kvStore: Binding(
                    get: { entitlementsDict[CapabilityCatalog.iCloudKVStoreKey] as? String ?? "" },
                    set: {
                        entitlementsDict[CapabilityCatalog.iCloudKVStoreKey] = $0
                        markDirty()
                    }
                ),
                ubiquitous: Binding(
                    get: { entitlementsDict[CapabilityCatalog.ubiquitousContainersKey] as? [String: [String: Any]] ?? [:] },
                    set: {
                        entitlementsDict[CapabilityCatalog.ubiquitousContainersKey] = $0
                        markDirty()
                    }
                )
            )
        }
    }

    // MARK: - Other (unmanaged) Keys
    @ViewBuilder
    private var otherKeysSection: some View {
        if !uncoveredKeys.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Label(EntitlementCapabilitySection.other.fullTitle, systemImage: EntitlementCapabilitySection.other.icon)
                    .font(.headline)
                    .foregroundStyle(.secondary)
                Text("These keys are present in the file but are not managed by a capability toggle above. Edit them in place or remove them.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ForEach(uncoveredKeys, id: \.self) { key in
                    EntitlementRowView(
                        key: key,
                        value: entitlementsDict[key] ?? "",
                        onSelect: {
                            selectedKey = key
                            showingInspectorSheet = true
                        },
                        onDuplicate: {
                            let val = entitlementsDict[key] ?? true
                            var copyKey = "\(key).copy"
                            var n = 2
                            while entitlementsDict[copyKey] != nil {
                                copyKey = "\(key).copy\(n)"
                                n += 1
                            }
                            entitlementsDict[copyKey] = val
                            markDirty()
                            toolStatus = "Duplicated to \(copyKey)"
                        },
                        onDelete: {
                            entitlementsDict.removeValue(forKey: key)
                            if selectedKey == key { selectedKey = nil }
                            markDirty()
                        },
                        onValueChange: { newVal in
                            entitlementsDict[key] = newVal
                            markDirty()
                        }
                    )
                    .padding(.vertical, 2)
                }
            }
            .padding(.horizontal, 16)
        }
    }

    // MARK: - Add Capability Sheet
    private var addCapabilitySheet: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Add Capability to Entitlements", systemImage: "plus.circle.fill")
                    .font(.title3.bold())
                Spacer()
                Button {
                    showingAddSheet = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                        .font(.title3)
                }
                .buttonStyle(.plain)
            }

            // Search Bar in Add Capability Sheet
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search capabilities by name, key, or category...", text: $addSheetSearch)
                    .textFieldStyle(.plain)
                if !addSheetSearch.isEmpty {
                    Button { addSheetSearch = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(8)
            .background(Color(NSColor.controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))

            // Category filter pills in Add Capability Sheet
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(EntitlementCapabilitySection.allCases.filter { $0 != .other }) { cat in
                        let isSelected = addSheetSection == cat
                        Button {
                            addSheetSection = cat
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: cat.icon)
                                    .font(.caption2)
                                Text(cat.rawValue)
                                    .font(.caption)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(isSelected ? Color.teal : Color.secondary.opacity(0.12), in: Capsule())
                            .foregroundStyle(isSelected ? Color.white : Color.primary)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            // Filtered available capabilities
            let available = CapabilityCatalog.definitions
                .filter { !isCapabilityOn($0) }
                .filter { def in
                    if addSheetSection != .all && def.section != addSheetSection {
                        return false
                    }
                    if addSheetSearch.isEmpty { return true }
                    let query = addSheetSearch.lowercased()
                    return def.name.lowercased().contains(query)
                        || def.rawKey.lowercased().contains(query)
                        || def.explanation.lowercased().contains(query)
                }

            if available.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "checkmark.circle")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text("No matching capabilities found")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 220)
            } else {
                List(available) { def in
                    HStack(spacing: 12) {
                        Image(systemName: def.symbol)
                            .font(.title3)
                            .foregroundStyle(.teal)
                            .frame(width: 28)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(def.name)
                                .font(.body.weight(.medium))
                            Text(def.explanation)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                            Text(def.rawKey)
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundStyle(.tertiary)
                        }
                        Spacer()
                        Button("Add") {
                            setCapability(def, on: true)
                            showingAddSheet = false
                            toolStatus = "Added \(def.name)"
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.teal)
                        .controlSize(.small)
                    }
                    .padding(.vertical, 6)
                }
                .listStyle(.inset)
                .frame(minHeight: 240)
            }

            Divider()

            // Custom Entitlement Key
            VStack(alignment: .leading, spacing: 8) {
                Text("Custom Entitlement Key")
                    .font(.subheadline.bold())
                    .foregroundStyle(.secondary)

                HStack {
                    TextField("e.g. com.example.custom-capability", text: $customKey)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                    Picker("Type", selection: $customKeyType) {
                        Text("Boolean").tag("boolean")
                        Text("String").tag("string")
                        Text("Array").tag("array")
                        Text("Dictionary").tag("dictionary")
                    }
                    .pickerStyle(.menu)
                    .frame(width: 120)
                    Button("Add Custom") {
                        let trimmed = customKey.trimmingCharacters(in: .whitespaces)
                        guard !trimmed.isEmpty, entitlementsDict[trimmed] == nil else { return }
                        let newValue: Any
                        switch customKeyType {
                        case "string":
                            newValue = ""
                        case "array":
                            newValue = [String]()
                        case "dictionary":
                            newValue = [String: String]()
                        default:
                            newValue = true
                        }
                        entitlementsDict[trimmed] = newValue
                        markDirty()
                        customKey = ""
                        showingAddSheet = false
                        toolStatus = "Added custom key \(trimmed)"
                    }
                    .buttonStyle(.bordered)
                    .disabled(customKey.trimmingCharacters(in: .whitespaces).isEmpty || entitlementsDict[customKey.trimmingCharacters(in: .whitespaces)] != nil)
                }
            }

            HStack {
                Spacer()
                Button("Done") {
                    showingAddSheet = false
                }
                .buttonStyle(.bordered)
                .keyboardShortcut(.cancelAction)
            }
        }
        .padding(20)
        .frame(minWidth: 640, minHeight: 620)
    }

    // MARK: - Inspector Sheet
    private var inspectorSheetView: some View {
        VStack(spacing: 0) {
            HStack {
                Label("Capability Details", systemImage: "lock.shield")
                    .font(.headline)
                Spacer()
                Button("Done") {
                    showingInspectorSheet = false
                }
                .buttonStyle(.bordered)
            }
            .padding()
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            if let key = selectedKey {
                let meta = EntitlementsCatalog.all.first(where: { $0.rawKey == key })
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(meta?.displayName ?? key)
                                .font(.title3.bold())
                            Text(key)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }

                        if let desc = meta?.entitlementDescription, !desc.isEmpty {
                            Text(desc)
                                .font(.body)
                                .foregroundStyle(.secondary)
                        }

                        if let meta {
                            Divider()
                            VStack(alignment: .leading, spacing: 6) {
                                inspectorDetailRow(label: "Category", value: meta.category.rawValue)
                                inspectorDetailRow(
                                    label: "Platforms",
                                    value: meta.supportedPlatforms.map(\.rawValue).joined(separator: ", ")
                                )
                                inspectorDetailRow(label: "Minimum OS", value: meta.minimumOS)
                                inspectorDetailRow(label: "Value Type", value: meta.valueType.rawValue)
                                if !meta.validationRules.isEmpty {
                                    inspectorDetailRow(label: "Validation", value: meta.validationRules)
                                }
                                if !meta.recommendedUsage.isEmpty {
                                    inspectorDetailRow(label: "Recommended Usage", value: meta.recommendedUsage)
                                }
                            }
                        }

                        Divider()

                        VStack(alignment: .leading, spacing: 6) {
                            Text("Configured Value:")
                                .font(.subheadline.bold())
                            Text(String(describing: entitlementsDict[key] ?? ""))
                                .font(.system(.body, design: .monospaced))
                                .padding(10)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color(NSColor.controlBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
                        }
                    }
                    .padding(20)
                }
            } else {
                ContentUnavailableView("No Capability Selected", systemImage: "lock.shield")
            }
        }
        .frame(width: 480, height: 440)
    }

    private func inspectorDetailRow(label: String, value: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 130, alignment: .leading)
            Text(value)
                .font(.callout)
            Spacer()
        }
    }
}

// MARK: - Identifier List Editor (App Groups, Keychain Groups, iCloud Containers)

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

// MARK: - Fixed Value List Editor (values restricted to a real set)

struct FixedValueListEditor: View {
    @Binding var values: [String]
    let allowed: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if values.isEmpty {
                Text("None selected. Add one of the supported values below.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ForEach(values, id: \.self) { value in
                HStack {
                    Image(systemName: allowed.contains(value) ? "checkmark.circle" : "exclamationmark.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(value)
                        .font(.system(.body, design: .monospaced))
                    Spacer()
                    Button {
                        values.removeAll { $0 == value }
                    } label: {
                        Image(systemName: "minus.circle")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Remove value")
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color(NSColor.textBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
            }
            let missing = allowed.filter { !values.contains($0) }
            if !missing.isEmpty {
                HStack {
                    Text("Add:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    ForEach(missing, id: \.self) { value in
                        Button(value) { values.append(value) }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                    }
                }
            }
        }
    }
}

// MARK: - Associated Domains Editor (service prefix + host)

struct AssociatedDomainsEditor: View {
    @Binding var domains: [String]
    let prefixes: [String]
    let placeholder: String
    @State private var selectedPrefix = 0
    @State private var host = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if domains.isEmpty {
                Text("No associated domains yet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ForEach(domains, id: \.self) { domain in
                HStack {
                    Image(systemName: "link")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(domain)
                        .font(.system(.body, design: .monospaced))
                    Spacer()
                    Button {
                        domains.removeAll { $0 == domain }
                    } label: {
                        Image(systemName: "minus.circle")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Remove domain")
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color(NSColor.textBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
            }
            HStack {
                Picker("Service", selection: $selectedPrefix) {
                    ForEach(prefixes.indices, id: \.self) { index in
                        Text(prefixes[index]).tag(index)
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: 180)
                TextField(placeholder, text: $host)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
                    .onSubmit { addDomain() }
                Button("Add") { addDomain() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(!canAdd)
            }
            Text("Each entry is a service prefix plus your domain, e.g. applinks:example.com.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var trimmedHost: String {
        host.trimmingCharacters(in: .whitespaces).lowercased()
    }

    private var newDomain: String {
        prefixes[selectedPrefix] + trimmedHost
    }

    private var canAdd: Bool {
        !trimmedHost.isEmpty && !domains.contains(newDomain)
    }

    private func addDomain() {
        guard canAdd else { return }
        domains.append(newDomain)
        host = ""
    }
}

// MARK: - iCloud Composite Editor

struct ICloudCompositeEditor: View {
    @Binding var containers: [String]
    @Binding var kvStore: String
    @Binding var ubiquitous: [String: [String: Any]]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Container Identifiers")
                .font(.caption)
                .foregroundStyle(.secondary)
            EntitlementIDListEditor(
                ids: $containers,
                placeholder: "iCloud.com.example.app"
            )
            Text("Key-Value Store Identifier")
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField("$(TeamIdentifierPrefix)$(CFBundleIdentifier)", text: $kvStore)
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))
            UbiquitousContainersEditor(containers: $ubiquitous)
        }
    }
}

// MARK: - NSUbiquitousContainers Editor

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

// MARK: - String Dictionary Editor (custom dictionary values)

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

// MARK: - Row View for unmanaged keys (type-appropriate inline editors)

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
