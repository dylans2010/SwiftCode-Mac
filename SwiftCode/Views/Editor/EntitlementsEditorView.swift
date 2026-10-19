import SwiftUI
import UniformTypeIdentifiers

public struct EntitlementsEditorView: View {
    private let fileURL: URL?
    @State private var manager: EntitlementsEditorManager
    @State private var entitlementsDict: [String: Any] = [:]
    @State private var searchQuery = ""
    @State private var selectedFilter: EntitlementCategoryFilter = .all
    @State private var selectedKey: String? = nil
    @State private var xmlEditorText = ""
    @State private var showingAddSheet = false
    @State private var showingInspectorSheet = false
    @State private var toolStatus: String? = nil
    @Environment(WorkspaceViewModel.self) private var workspaceViewModel
    @State private var isCreating = false
    @State private var creationError: String? = nil

    public enum EntitlementCategoryFilter: String, CaseIterable, Identifiable {
        case all = "All Capabilities"
        case sandbox = "App Sandbox"
        case network = "Network"
        case hardware = "Hardware & Media"
        case files = "Files & Storage"
        case cloud = "iCloud & Push"
        case rawXML = "Raw XML"

        public var id: String { rawValue }

        public var icon: String {
            switch self {
            case .all: return "lock.shield"
            case .sandbox: return "cube.transparent"
            case .network: return "network"
            case .hardware: return "camera"
            case .files: return "folder"
            case .cloud: return "icloud"
            case .rawXML: return "chevron.left.forwardslash.chevron.right"
            }
        }
    }

    public init(fileURL: URL?) {
        self.fileURL = fileURL
        let m = EntitlementsEditorManager(fileURL: fileURL ?? URL(fileURLWithPath: "/dev/null"))
        _manager = State(initialValue: m)
        if fileURL != nil {
            _entitlementsDict = State(initialValue: (try? m.readEntitlements()) ?? [:])
        } else {
            _entitlementsDict = State(initialValue: [:])
        }
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

    private var activeKeys: [String] {
        guard fileURL != nil else { return [] }
        return entitlementsDict.keys.sorted().filter { key in
            // Filter by category
            let lowerKey = key.lowercased()
            let passesFilter: Bool
            switch selectedFilter {
            case .all, .rawXML:
                passesFilter = true
            case .sandbox:
                passesFilter = lowerKey.contains("sandbox") || lowerKey.contains("hardened")
            case .network:
                passesFilter = lowerKey.contains("network")
            case .hardware:
                passesFilter = lowerKey.contains("device") || lowerKey.contains("camera") || lowerKey.contains("microphone") || lowerKey.contains("usb") || lowerKey.contains("bluetooth")
            case .files:
                passesFilter = lowerKey.contains("files") || lowerKey.contains("downloads") || lowerKey.contains("pictures") || lowerKey.contains("movies")
            case .cloud:
                passesFilter = lowerKey.contains("icloud") || lowerKey.contains("aps-environment") || lowerKey.contains("push") || lowerKey.contains("keychain")
            }

            guard passesFilter else { return false }

            if searchQuery.isEmpty { return true }
            let lowerQuery = searchQuery.lowercased()
            let matchesKey = key.lowercased().contains(lowerQuery)
            let matchesVal = String(describing: entitlementsDict[key] ?? "").lowercased().contains(lowerQuery)
            let matchesMeta = EntitlementsCatalog.all.contains { meta in
                meta.rawKey == key && (meta.displayName.lowercased().contains(lowerQuery) || meta.entitlementDescription.lowercased().contains(lowerQuery))
            }
            return matchesKey || matchesVal || matchesMeta
        }
    }

    private var validationResult: EntitlementValidationResult {
        manager.validate(entitlementsDict)
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
                        .foregroundColor(.red)
                        .font(.callout)
                }

                Button {
                    createEntitlements()
                } label: {
                    Label(isCreating ? "Creating..." : "Create Entitlements", systemImage: "plus")
                        .font(.headline)
                        .frame(minWidth: 160)
                }
                .buttonStyle(.borderedProminent)
                .disabled(isCreating)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(NSColor.windowBackgroundColor))
        } else {
            VStack(spacing: 0) {
                // Professional Header Toolbar with Tool Actions
                headerToolbar

                Divider()

                // Segmented Category Filter
                HStack {
                    Picker("Category", selection: $selectedFilter) {
                        ForEach(EntitlementCategoryFilter.allCases) { cat in
                            Label(cat.rawValue, systemImage: cat.icon).tag(cat)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color(NSColor.controlBackgroundColor))

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
                if selectedFilter == .rawXML {
                    rawXMLEditorView
                } else {
                    capabilitiesListView
                }
            }
            .sheet(isPresented: $showingAddSheet) {
                addCapabilitySheet
            }
            .sheet(isPresented: $showingInspectorSheet) {
                inspectorSheetView
            }
            .onAppear {
                if fileURL != nil {
                    syncXMLText()
                }
            }
        }
    }

    // MARK: - Header Toolbar
    private var headerToolbar: some View {
        HStack(spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "lock.shield")
                    .foregroundStyle(.secondary)
                Text(fileURL?.lastPathComponent ?? "App.entitlements")
                    .font(.headline)
                Text("(\(entitlementsDict.count) capabilities)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Search Bar
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search capabilities...", text: $searchQuery)
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
            .padding(.vertical, 4)
            .background(Color(NSColor.controlBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
            .frame(width: 180)

            // Preset Bundles Menu
            Menu {
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
                    Label("Developer Tool Hardened Runtime", systemImage: "wrench.and.screwdriver")
                }

                Button {
                    applyPreset(keys: [
                        "com.apple.security.device.camera": true,
                        "com.apple.security.device.microphone": true,
                        "com.apple.security.personal-information.photos-library": true
                    ])
                    toolStatus = "Applied Media & Hardware Preset"
                } label: {
                    Label("Media & Hardware Access", systemImage: "camera")
                }

                Button {
                    applyPreset(keys: [
                        "com.apple.developer.icloud-container-identifiers": ["iCloud.$(CFBundleIdentifier)"],
                        "com.apple.developer.ubiquity-kvstore-identifier": "$(CFBundleIdentifier)"
                    ])
                    toolStatus = "Applied iCloud & CloudKit Preset"
                } label: {
                    Label("iCloud Key-Value & Containers", systemImage: "icloud")
                }
            } label: {
                Label("Capability Presets", systemImage: "square.grid.2x2")
            }
            .menuStyle(.borderedButton)

            // Validate Tool
            Button {
                validateEntitlements()
            } label: {
                Label("Validate", systemImage: "checkmark.seal")
            }
            .buttonStyle(.bordered)

            // Copy XML Tool
            Button {
                syncXMLText()
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(xmlEditorText, forType: .string)
                toolStatus = "Copied Raw XML to clipboard"
            } label: {
                Label("Copy XML", systemImage: "doc.on.doc")
            }
            .buttonStyle(.bordered)

            // Save Tool
            Button {
                saveChanges()
            } label: {
                Label("Save", systemImage: "square.and.arrow.down")
            }
            .buttonStyle(.bordered)

            // Add Capability Tool
            Button {
                showingAddSheet = true
            } label: {
                Label("Capability", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color(NSColor.windowBackgroundColor))
    }

    private func applyPreset(keys: [String: Any]) {
        for (k, v) in keys {
            entitlementsDict[k] = v
        }
        saveChanges()
    }

    private func saveChanges() {
        do {
            try manager.writeEntitlements(entitlementsDict)
            syncXMLText()
            toolStatus = "Successfully saved entitlements to disk."
        } catch {
            toolStatus = "Error saving entitlements: \(error.localizedDescription)"
        }
    }

    private func validateEntitlements() {
        let res = validationResult
        if res.errors.isEmpty && res.warnings.isEmpty {
            toolStatus = "All capabilities are syntactically valid."
        } else {
            let allIssues = res.errors.map(\.message) + res.warnings.map(\.message)
            let msg = allIssues.joined(separator: "; ")
            toolStatus = "Validation: \(msg)"
        }
    }

    // MARK: - Capabilities List View
    private var capabilitiesListView: some View {
        List {
            if activeKeys.isEmpty {
                ContentUnavailableView(
                    "No Active Capabilities",
                    systemImage: "lock.shield",
                    description: Text(searchQuery.isEmpty ? "Click 'Capability' or select a Capability Preset to enable sandbox permissions." : "No capabilities match '\(searchQuery)'.")
                )
                .padding()
            } else {
                ForEach(activeKeys, id: \.self) { key in
                    EntitlementRowView(
                        key: key,
                        value: entitlementsDict[key] ?? "",
                        onSelect: {
                            selectedKey = key
                            showingInspectorSheet = true
                        },
                        onDuplicate: {
                            let val = entitlementsDict[key] ?? true
                            let copyKey = "\(key).copy"
                            entitlementsDict[copyKey] = val
                            saveChanges()
                            toolStatus = "Duplicated to \(copyKey)"
                        },
                        onDelete: {
                            entitlementsDict.removeValue(forKey: key)
                            if selectedKey == key { selectedKey = nil }
                            saveChanges()
                        },
                        onValueChange: { newVal in
                            entitlementsDict[key] = newVal
                            saveChanges()
                        }
                    )
                    .padding(.vertical, 2)
                }
            }
        }
        .listStyle(.inset)
    }

    // MARK: - Raw XML Editor View
    private var rawXMLEditorView: some View {
        VStack(spacing: 0) {
            HStack {
                Label("Raw Entitlements XML", systemImage: "doc.plaintext")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Re-format XML") {
                    syncXMLText()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            TextEditor(text: $xmlEditorText)
                .font(.system(.body, design: .monospaced))
                .padding(8)
                .background(Color(NSColor.textBackgroundColor))
                .onChange(of: xmlEditorText) { _, newValue in
                    if let data = newValue.data(using: .utf8),
                       let parsed = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any] {
                        entitlementsDict = parsed
                        try? manager.writeEntitlements(parsed)
                    }
                }
        }
    }

    private func syncXMLText() {
        if let data = try? PropertyListSerialization.data(fromPropertyList: entitlementsDict, format: .xml, options: 0),
           let str = String(data: data, encoding: .utf8) {
            xmlEditorText = str
        }
    }

    // MARK: - Add Capability Sheet
    private var addCapabilitySheet: some View {
        VStack(spacing: 16) {
            Text("Add Capability to Entitlements")
                .font(.headline)

            List(EntitlementsCatalog.all.filter { entitlementsDict[$0.rawKey] == nil }) { item in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.displayName)
                            .font(.body.weight(.medium))
                        Text(item.rawKey)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Add") {
                        entitlementsDict[item.rawKey] = item.defaultValue
                        saveChanges()
                        showingAddSheet = false
                    }
                    .buttonStyle(.bordered)
                }
                .padding(.vertical, 4)
            }
            .frame(height: 300)

            HStack {
                Spacer()
                Button("Done") {
                    showingAddSheet = false
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .frame(width: 500, height: 400)
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
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(meta?.displayName ?? key)
                            .font(.title3.bold())
                        Text(key)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }

                    if let desc = meta?.entitlementDescription {
                        Text(desc)
                            .font(.body)
                            .foregroundStyle(.secondary)
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

                    Spacer()
                }
                .padding(20)
            } else {
                ContentUnavailableView("No Capability Selected", systemImage: "lock.shield")
            }
        }
        .frame(width: 480, height: 400)
    }
}

// MARK: - Clean Monochrome Row View
struct EntitlementRowView: View {
    let key: String
    let value: Any
    let onSelect: () -> Void
    let onDuplicate: () -> Void
    let onDelete: () -> Void
    let onValueChange: (Any) -> Void

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(key)
                    .font(.system(.body, design: .monospaced).weight(.medium))
                    .lineLimit(1)

                if let meta = EntitlementsCatalog.all.first(where: { $0.rawKey == key }) {
                    Text(meta.displayName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
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
            } else if let arrVal = value as? [Any] {
                Text("\(arrVal.count) entries")
                    .font(.caption)
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
                .frame(minWidth: 160, maxWidth: 260)
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
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }
}
