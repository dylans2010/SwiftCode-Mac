import SwiftUI
import UniformTypeIdentifiers

// MARK: - Capability Model

/// Capability sections shown as filter categories and UI groups.
public enum EntitlementCapabilitySection: String, CaseIterable, Identifiable {
    case all = "All Capabilities"
    case sandbox = "App Sandbox"
    case network = "Network"
    case hardware = "Hardware & Media"
    case cloud = "iCloud & Push"
    case sharing = "Sharing"
    case personal = "Personal Information"
    case other = "Other Keys"
    case rawXML = "Raw XML"

    public var id: String { rawValue }

    public var icon: String {
        switch self {
        case .all: return "lock.shield"
        case .sandbox: return "cube.transparent"
        case .network: return "network"
        case .hardware: return "camera"
        case .cloud: return "icloud"
        case .sharing: return "square.stack.3d"
        case .personal: return "person.crop.circle"
        case .other: return "key"
        case .rawXML: return "chevron.left.forwardslash.chevron.right"
        }
    }
}

/// What kind of payload a capability carries beyond its on/off switch.
public enum CapabilityPayloadKind {
    /// Pure boolean toggle — enabling sets the key, disabling removes it.
    case none
    /// An array of string identifiers the user can add/remove.
    case idList(placeholder: String)
    /// A string picked from a fixed set of options.
    case choice(options: [String])
    /// A free-form string value.
    case stringValue(placeholder: String)
}

/// One toggleable capability. Enabling it writes the real entitlement key;
/// disabling it removes the key from the entitlements file.
public struct CapabilityDefinition: Identifiable {
    public var id: String { rawKey }
    public let rawKey: String
    public let name: String
    public let explanation: String
    public let symbol: String
    public let section: EntitlementCapabilitySection
    public let payload: CapabilityPayloadKind
    public let defaultValue: Any
    /// Composite capabilities control more than one entitlement key (e.g. iCloud).
    public let compositeKeys: [String]

    public init(rawKey: String, name: String, explanation: String, symbol: String, section: EntitlementCapabilitySection, payload: CapabilityPayloadKind, defaultValue: Any, compositeKeys: [String] = []) {
        self.rawKey = rawKey
        self.name = name
        self.explanation = explanation
        self.symbol = symbol
        self.section = section
        self.payload = payload
        self.defaultValue = defaultValue
        self.compositeKeys = compositeKeys
    }
}

public enum CapabilityCatalog {
    public static let iCloudContainersKey = "com.apple.developer.icloud-container-identifiers"
    public static let iCloudKVStoreKey = "com.apple.developer.ubiquity-kvstore-identifier"

    public static let definitions: [CapabilityDefinition] = [
        // MARK: App Sandbox
        CapabilityDefinition(
            rawKey: "com.apple.security.app-sandbox",
            name: "App Sandbox",
            explanation: "Restricts the app to only the system resources it explicitly requests. Required for Mac App Store distribution.",
            symbol: "lock.shield.fill",
            section: .sandbox,
            payload: .none,
            defaultValue: true
        ),
        CapabilityDefinition(
            rawKey: "com.apple.security.files.user-selected.read-only",
            name: "User-Selected Files (Read)",
            explanation: "Lets the app read files the user explicitly opens through Open panels or drag and drop.",
            symbol: "folder",
            section: .sandbox,
            payload: .none,
            defaultValue: true
        ),
        CapabilityDefinition(
            rawKey: "com.apple.security.files.user-selected.read-write",
            name: "User-Selected Files (Read & Write)",
            explanation: "Lets the app read and write files the user explicitly opens through Open and Save panels or drag and drop.",
            symbol: "folder.badge.plus",
            section: .sandbox,
            payload: .none,
            defaultValue: true
        ),
        CapabilityDefinition(
            rawKey: "com.apple.security.files.downloads.read-only",
            name: "Downloads Folder (Read)",
            explanation: "Grants read access to files inside the user's Downloads folder without prompting.",
            symbol: "arrow.down.doc",
            section: .sandbox,
            payload: .none,
            defaultValue: true
        ),
        CapabilityDefinition(
            rawKey: "com.apple.security.files.downloads.read-write",
            name: "Downloads Folder (Read & Write)",
            explanation: "Grants read and write access to files inside the user's Downloads folder without prompting.",
            symbol: "arrow.down.doc.fill",
            section: .sandbox,
            payload: .none,
            defaultValue: true
        ),
        CapabilityDefinition(
            rawKey: "com.apple.security.assets.pictures.read-only",
            name: "Pictures Folder (Read)",
            explanation: "Grants read access to the user's Pictures folder, commonly used for image pickers.",
            symbol: "photo",
            section: .sandbox,
            payload: .none,
            defaultValue: true
        ),
        CapabilityDefinition(
            rawKey: "com.apple.security.assets.pictures.read-write",
            name: "Pictures Folder (Read & Write)",
            explanation: "Grants read and write access to the user's Pictures folder, for apps that save images.",
            symbol: "photo.fill",
            section: .sandbox,
            payload: .none,
            defaultValue: true
        ),
        CapabilityDefinition(
            rawKey: "com.apple.security.assets.music.read-only",
            name: "Music Folder (Read)",
            explanation: "Grants read access to the user's Music folder for media library features.",
            symbol: "music.note",
            section: .sandbox,
            payload: .none,
            defaultValue: true
        ),
        CapabilityDefinition(
            rawKey: "com.apple.security.assets.movies.read-only",
            name: "Movies Folder (Read)",
            explanation: "Grants read access to the user's Movies folder for media library features.",
            symbol: "film",
            section: .sandbox,
            payload: .none,
            defaultValue: true
        ),

        // MARK: Network
        CapabilityDefinition(
            rawKey: "com.apple.security.network.client",
            name: "Outgoing Connections",
            explanation: "Allows the app to make outgoing network connections, e.g. calling web APIs or downloading content.",
            symbol: "arrow.up.right.circle",
            section: .network,
            payload: .none,
            defaultValue: true
        ),
        CapabilityDefinition(
            rawKey: "com.apple.security.network.server",
            name: "Incoming Connections",
            explanation: "Allows the app to listen for incoming network connections and host local services.",
            symbol: "arrow.down.left.circle",
            section: .network,
            payload: .none,
            defaultValue: true
        ),

        // MARK: Hardware & Media
        CapabilityDefinition(
            rawKey: "com.apple.security.device.camera",
            name: "Camera",
            explanation: "Allows the app to capture photos and video using the system cameras. Pair with an NSCameraUsageDescription key in Info.plist.",
            symbol: "camera.fill",
            section: .hardware,
            payload: .none,
            defaultValue: true
        ),
        CapabilityDefinition(
            rawKey: "com.apple.security.device.audio-input",
            name: "Microphone",
            explanation: "Allows the app to record audio using the system microphones. Pair with an NSMicrophoneUsageDescription key in Info.plist.",
            symbol: "mic.fill",
            section: .hardware,
            payload: .none,
            defaultValue: true
        ),
        CapabilityDefinition(
            rawKey: "com.apple.security.device.usb",
            name: "USB Devices",
            explanation: "Allows the app to communicate directly with connected USB accessories and hardware.",
            symbol: "cable.connector",
            section: .hardware,
            payload: .none,
            defaultValue: true
        ),
        CapabilityDefinition(
            rawKey: "com.apple.security.device.bluetooth",
            name: "Bluetooth",
            explanation: "Allows the app to communicate with Bluetooth accessories while sandboxed.",
            symbol: "bluetooth",
            section: .hardware,
            payload: .none,
            defaultValue: true
        ),

        // MARK: iCloud & Push
        CapabilityDefinition(
            rawKey: "aps-environment",
            name: "Push Notifications",
            explanation: "Registers the app for Apple Push Notification service. Choose the environment that matches your provisioning profile; Xcode normally finalizes this at archive time.",
            symbol: "bell.badge",
            section: .cloud,
            payload: .choice(options: ["development", "production"]),
            defaultValue: "development"
        ),
        CapabilityDefinition(
            rawKey: iCloudContainersKey,
            name: "iCloud",
            explanation: "Syncs documents and key-value data through the user's iCloud account. Add the container identifiers your app uses, plus the key-value store identifier.",
            symbol: "icloud",
            section: .cloud,
            payload: .idList(placeholder: "iCloud.com.example.app"),
            defaultValue: [String](),
            compositeKeys: [iCloudKVStoreKey]
        ),

        // MARK: Sharing
        CapabilityDefinition(
            rawKey: "com.apple.security.application-groups",
            name: "App Groups",
            explanation: "Lets the app share files and preferences with its extensions or companion apps through a shared container.",
            symbol: "square.stack.3d",
            section: .sharing,
            payload: .idList(placeholder: "group.com.example.app"),
            defaultValue: [String]()
        ),
        CapabilityDefinition(
            rawKey: "keychain-access-groups",
            name: "Keychain Access Groups",
            explanation: "Lets the app share passwords and tokens in the Keychain with sibling apps using the same access group.",
            symbol: "key.fill",
            section: .sharing,
            payload: .idList(placeholder: "$(AppIdentifierPrefix)com.example.app"),
            defaultValue: [String]()
        ),

        // MARK: Personal Information
        CapabilityDefinition(
            rawKey: "com.apple.security.personal-information.photos-library",
            name: "Photos Library",
            explanation: "Allows the app to access the user's Photos library. Pair with an NSPhotoLibraryUsageDescription key in Info.plist.",
            symbol: "photo.on.rectangle",
            section: .personal,
            payload: .none,
            defaultValue: true
        ),
        CapabilityDefinition(
            rawKey: "com.apple.security.personal-information.addressbook",
            name: "Contacts",
            explanation: "Allows the app to access the user's contacts. Pair with an NSContactsUsageDescription key in Info.plist.",
            symbol: "person.crop.circle",
            section: .personal,
            payload: .none,
            defaultValue: true
        ),
    ]

    /// All raw entitlement keys managed by capability toggles, including composite keys.
    public static var allRawKeys: [String] {
        var keys = definitions.map(\.rawKey)
        keys.append(contentsOf: definitions.flatMap(\.compositeKeys))
        return keys
    }

    public static func definitions(for section: EntitlementCapabilitySection) -> [CapabilityDefinition] {
        definitions.filter { $0.section == section }
    }
}

// MARK: - Entitlements Editor View

public struct EntitlementsEditorView: View {
    private let fileURL: URL?
    @State private var manager: EntitlementsEditorManager
    @State private var entitlementsDict: [String: Any] = [:]
    @State private var searchQuery = ""
    @State private var selectedFilter: EntitlementCapabilitySection = .all
    @State private var selectedKey: String? = nil
    @State private var xmlEditorText = ""
    @State private var showingAddSheet = false
    @State private var showingInspectorSheet = false
    @State private var toolStatus: String? = nil
    @State private var isDirty = false
    @State private var fileModifiedDate: Date? = nil
    @State private var customKey = ""
    @State private var customKeyType = "boolean"
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
        syncXMLText()
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
        return def.name.lowercased().contains(q)
            || def.rawKey.lowercased().contains(q)
            || def.explanation.lowercased().contains(q)
    }

    private var visibleSections: [EntitlementCapabilitySection] {
        switch selectedFilter {
        case .all:
            return [.sandbox, .network, .hardware, .cloud, .sharing, .personal]
        case .other, .rawXML:
            return []
        default:
            return [selectedFilter]
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
                        ForEach(EntitlementCapabilitySection.allCases) { cat in
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
                    if let url = fileURL {
                        fileModifiedDate = Self.modifiedDate(of: url)
                    }
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
                if isDirty {
                    Text("Unsaved changes")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color(NSColor.controlBackgroundColor), in: Capsule())
                }
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
            .disabled(!isDirty)
            .keyboardShortcut("s", modifiers: .command)
            .help("Write changes to the entitlements file")

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
        markDirty()
    }

    private func saveChanges() {
        do {
            try manager.writeEntitlements(entitlementsDict)
            syncXMLText()
            isDirty = false
            if let url = fileURL {
                fileModifiedDate = Self.modifiedDate(of: url)
            }
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

    // MARK: - Capabilities List View
    private var capabilitiesListView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                fileStatusCard
                    .padding(.horizontal, 16)
                    .padding(.top, 12)

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
                Label(section.rawValue, systemImage: section.icon)
                    .font(.headline)
                    .foregroundStyle(.secondary)
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
                }
                Spacer()
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
        // iCloud is composite: container list plus key-value store identifier.
        if def.rawKey == CapabilityCatalog.iCloudContainersKey {
            VStack(alignment: .leading, spacing: 8) {
                Text("Container Identifiers")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                EntitlementIDListEditor(
                    ids: Binding(
                        get: { entitlementsDict[CapabilityCatalog.iCloudContainersKey] as? [String] ?? [] },
                        set: {
                            entitlementsDict[CapabilityCatalog.iCloudContainersKey] = $0
                            markDirty()
                        }
                    ),
                    placeholder: "iCloud.com.example.app"
                )
                Text("Key-Value Store Identifier")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("$(TeamIdentifierPrefix)$(CFBundleIdentifier)", text: Binding(
                    get: { entitlementsDict[CapabilityCatalog.iCloudKVStoreKey] as? String ?? "" },
                    set: {
                        entitlementsDict[CapabilityCatalog.iCloudKVStoreKey] = $0
                        markDirty()
                    }
                ))
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))
            }
        } else {
            switch def.payload {
            case .none:
                EmptyView()
            case .idList(let placeholder):
                EntitlementIDListEditor(
                    ids: Binding(
                        get: { entitlementsDict[def.rawKey] as? [String] ?? [] },
                        set: {
                            entitlementsDict[def.rawKey] = $0
                            markDirty()
                        }
                    ),
                    placeholder: placeholder
                )
            case .choice(let options):
                Picker("Value", selection: Binding(
                    get: { entitlementsDict[def.rawKey] as? String ?? options.first ?? "" },
                    set: {
                        entitlementsDict[def.rawKey] = $0
                        markDirty()
                    }
                )) {
                    ForEach(options, id: \.self) { option in
                        Text(option).tag(option)
                    }
                }
                .pickerStyle(.segmented)
            case .stringValue(let placeholder):
                TextField(placeholder, text: Binding(
                    get: { entitlementsDict[def.rawKey] as? String ?? "" },
                    set: {
                        entitlementsDict[def.rawKey] = $0
                        markDirty()
                    }
                ))
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))
            }
        }
    }

    // MARK: - Other (unmanaged) Keys
    @ViewBuilder
    private var otherKeysSection: some View {
        if !uncoveredKeys.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Label("Other Keys", systemImage: EntitlementCapabilitySection.other.icon)
                    .font(.headline)
                    .foregroundStyle(.secondary)
                Text("These keys are present in the file but are not managed by a capability toggle above.")
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
                    guard newValue != manager.generateRawXML(entitlementsDict) else { return }
                    if let parsed = try? manager.parseRawXML(newValue) {
                        entitlementsDict = parsed
                        markDirty()
                    }
                }
        }
    }

    private func syncXMLText() {
        xmlEditorText = manager.generateRawXML(entitlementsDict)
    }

    // MARK: - Add Capability Sheet
    private var addCapabilitySheet: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Add Capability to Entitlements")
                .font(.headline)

            Text("Capabilities")
                .font(.subheadline.bold())
                .foregroundStyle(.secondary)

            let available = CapabilityCatalog.definitions.filter { !isCapabilityOn($0) }
            List(available) { def in
                HStack(spacing: 10) {
                    Image(systemName: def.symbol)
                        .foregroundStyle(.secondary)
                        .frame(width: 24)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(def.name)
                            .font(.body.weight(.medium))
                        Text(def.rawKey)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Add") {
                        setCapability(def, on: true)
                        showingAddSheet = false
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                .padding(.vertical, 4)
            }
            .frame(minHeight: 200)

            Divider()

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
                }
                .pickerStyle(.menu)
                Button("Add") {
                    let trimmed = customKey.trimmingCharacters(in: .whitespaces)
                    guard !trimmed.isEmpty, entitlementsDict[trimmed] == nil else { return }
                    entitlementsDict[trimmed] = customKeyType == "boolean" ? true : ""
                    markDirty()
                    customKey = ""
                    showingAddSheet = false
                }
                .buttonStyle(.borderedProminent)
                .disabled(customKey.trimmingCharacters(in: .whitespaces).isEmpty || entitlementsDict[customKey.trimmingCharacters(in: .whitespaces)] != nil)
            }
            let trimmedCustom = customKey.trimmingCharacters(in: .whitespaces)
            if !trimmedCustom.isEmpty && entitlementsDict[trimmedCustom] != nil {
                Text("This key already exists in the entitlements file.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Spacer()
                Button("Done") {
                    showingAddSheet = false
                }
                .buttonStyle(.bordered)
            }
        }
        .padding()
        .frame(width: 580, height: 560)
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

// MARK: - Clean Monochrome Row View (unmanaged keys)
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
