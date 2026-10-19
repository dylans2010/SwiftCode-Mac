import SwiftUI
import UniformTypeIdentifiers

// MARK: - Plist Value Type Helpers

/// The plist value kinds a user can create/edit through the UI.
public enum PlistValueKind: String, CaseIterable {
    case string = "String"
    case boolean = "Boolean"
    case number = "Number"
    case date = "Date"
    case data = "Data"
    case array = "Array"
    case dictionary = "Dictionary"

    public var symbol: String {
        switch self {
        case .string: return "textformat"
        case .boolean: return "switch.2"
        case .number: return "number"
        case .date: return "calendar"
        case .data: return "externaldrive"
        case .array: return "square.stack"
        case .dictionary: return "curlybraces"
        }
    }
}

/// Detects the plist kind of an arbitrary value coming from the editor.
public func plistValueKind(of value: Any) -> PlistValueKind {
    if value is Bool { return .boolean }
    if value is NSNumber { return .number }
    if value is Date { return .date }
    if value is Data { return .data }
    if value is [Any] { return .array }
    if value is [String: Any] { return .dictionary }
    return .string
}

/// A sensible default value for a freshly created key of the given kind.
public func defaultPlistValue(for kind: PlistValueKind) -> Any {
    switch kind {
    case .string: return ""
    case .boolean: return false
    case .number: return NSNumber(value: 0)
    case .date: return Date()
    case .data: return Data()
    case .array: return [Any]()
    case .dictionary: return [String: Any]()
    }
}

// MARK: - Common Key Templates

/// A pre-built Info.plist key a user can add with one tap.
public struct InfoPlistTemplate: Identifiable {
    public var id: String { key }
    public let key: String
    public let name: String
    public let symbol: String
    public let category: String
    public let kind: PlistValueKind
    public let defaultValue: Any

    public init(key: String, name: String, symbol: String, category: String, kind: PlistValueKind, defaultValue: Any) {
        self.key = key
        self.name = name
        self.symbol = symbol
        self.category = category
        self.kind = kind
        self.defaultValue = defaultValue
    }
}

public enum InfoPlistTemplateCatalog {
    public static let categories = ["Identity", "Display", "Privacy", "URL Types", "Behavior"]

    nonisolated(unsafe) public static let all: [InfoPlistTemplate] = {
        var list: [InfoPlistTemplate] = [
            InfoPlistTemplate(key: "CFBundleIdentifier", name: "Bundle Identifier", symbol: "app.badge", category: "Identity", kind: .string, defaultValue: "$(PRODUCT_BUNDLE_IDENTIFIER)"),
            InfoPlistTemplate(key: "CFBundleName", name: "Bundle Name", symbol: "app", category: "Identity", kind: .string, defaultValue: "$(PRODUCT_NAME)"),
            InfoPlistTemplate(key: "CFBundleDisplayName", name: "Display Name", symbol: "tag", category: "Identity", kind: .string, defaultValue: ""),
            InfoPlistTemplate(key: "CFBundleShortVersionString", name: "Version String", symbol: "number", category: "Identity", kind: .string, defaultValue: "1.0"),
            InfoPlistTemplate(key: "CFBundleVersion", name: "Build Number", symbol: "hammer", category: "Identity", kind: .string, defaultValue: "1"),
            InfoPlistTemplate(key: "CFBundleDevelopmentRegion", name: "Development Region", symbol: "globe", category: "Identity", kind: .string, defaultValue: "en"),
            InfoPlistTemplate(key: "CFBundlePackageType", name: "Package Type", symbol: "archivebox", category: "Identity", kind: .string, defaultValue: "APPL"),
            InfoPlistTemplate(key: "CFBundleInfoDictionaryVersion", name: "Info Dictionary Version", symbol: "info.circle", category: "Identity", kind: .string, defaultValue: "6.0"),
            InfoPlistTemplate(key: "NSHumanReadableCopyright", name: "Copyright Notice", symbol: "c.circle", category: "Identity", kind: .string, defaultValue: ""),
            InfoPlistTemplate(key: "LSApplicationCategoryType", name: "App Category", symbol: "square.grid.2x2", category: "Identity", kind: .string, defaultValue: "public.app-category.developer-tools"),

            InfoPlistTemplate(key: "CFBundleIconName", name: "Icon Name", symbol: "app.dashed", category: "Display", kind: .string, defaultValue: "AppIcon"),
            InfoPlistTemplate(key: "LSMinimumSystemVersion", name: "Minimum System Version", symbol: "desktopcomputer", category: "Display", kind: .string, defaultValue: "13.0"),
            InfoPlistTemplate(key: "NSPrincipalClass", name: "Principal Class", symbol: "pyramid", category: "Display", kind: .string, defaultValue: "NSApplication"),
            InfoPlistTemplate(key: "NSHighResolutionCapable", name: "High Resolution Capable", symbol: "sparkles", category: "Display", kind: .boolean, defaultValue: true),

            InfoPlistTemplate(key: "CFBundleURLTypes", name: "URL Types", symbol: "link", category: "URL Types", kind: .array, defaultValue: [["CFBundleURLName": "", "CFBundleURLSchemes": ["myapp"]]] as [Any]),
            InfoPlistTemplate(key: "LSApplicationQueriesSchemes", name: "Queried URL Schemes", symbol: "magnifyingglass", category: "URL Types", kind: .array, defaultValue: [String]() as [Any]),
            InfoPlistTemplate(key: "CFBundleDocumentTypes", name: "Document Types", symbol: "doc", category: "URL Types", kind: .array, defaultValue: [Any]()),

            InfoPlistTemplate(key: "LSUIElement", name: "Agent App (No Dock Icon)", symbol: "eye.slash", category: "Behavior", kind: .boolean, defaultValue: false),
            InfoPlistTemplate(key: "NSSupportsAutomaticTermination", name: "Supports Automatic Termination", symbol: "power", category: "Behavior", kind: .boolean, defaultValue: false),
            InfoPlistTemplate(key: "NSSupportsSuddenTermination", name: "Supports Sudden Termination", symbol: "bolt", category: "Behavior", kind: .boolean, defaultValue: false),
            InfoPlistTemplate(key: "CFBundleAllowMixedLocalizations", name: "Allow Mixed Localizations", symbol: "globe", category: "Behavior", kind: .boolean, defaultValue: false),
        ]
        // Privacy usage descriptions come from the curated metadata catalog.
        for meta in InfoPlistNSStrings.all {
            list.append(InfoPlistTemplate(
                key: meta.key,
                name: meta.name,
                symbol: meta.sfSymbol,
                category: "Privacy",
                kind: .string,
                defaultValue: meta.recommendedWording
            ))
        }
        return list
    }()

    public static func templates(in category: String) -> [InfoPlistTemplate] {
        all.filter { $0.category == category }
    }
}

// MARK: - Info.plist View

public struct InfoPlistView: View {
    private let fileURL: URL?
    @State private var editor: InfoPlistEditor
    @State private var searchQuery = ""
    @State private var selectedKey: String? = nil
    @State private var selectedCategory: InfoPlistCategory = .all
    @State private var xmlEditorText = ""
    @State private var showingAddKeySheet = false
    @State private var newCustomKey = ""
    @State private var newCustomType: PlistValueKind = .string
    @State private var templateCategory = "Identity"
    @State private var showingInspectorSheet = false
    @State private var toolStatus: String? = nil

    @Environment(\.undoManager) private var undoManager
    @Environment(WorkspaceViewModel.self) private var workspaceViewModel
    @State private var isCreating = false
    @State private var creationError: String? = nil

    public enum InfoPlistCategory: String, CaseIterable, Identifiable {
        case all = "All Properties"
        case identity = "App Identity"
        case permissions = "Privacy & Permissions"
        case display = "Display & Interface"
        case urlSchemes = "URL Types"
        case rawXML = "Raw XML"

        public var id: String { rawValue }

        public var icon: String {
            switch self {
            case .all: return "list.bullet.rectangle"
            case .identity: return "person.crop.square"
            case .permissions: return "hand.raised"
            case .display: return "display"
            case .urlSchemes: return "link"
            case .rawXML: return "chevron.left.forwardslash.chevron.right"
            }
        }
    }

    public init(fileURL: URL?) {
        self.fileURL = fileURL
        if let url = fileURL {
            _editor = State(initialValue: InfoPlistEditor(fileURL: url))
        } else {
            _editor = State(initialValue: InfoPlistEditor(fileURL: URL(fileURLWithPath: "/dev/null")))
        }
    }

    private func createInfoPlist() {
        guard let project = ProjectSessionStore.shared.activeProject else {
            creationError = "No active project found in session."
            return
        }

        isCreating = true
        creationError = nil

        let targetURL = project.directoryURL.appendingPathComponent("Info.plist")
        let defaultContent = """
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>$(DEVELOPMENT_LANGUAGE)</string>
    <key>CFBundleExecutable</key>
    <string>$(EXECUTABLE_NAME)</string>
    <key>CFBundleIdentifier</key>
    <string>$(PRODUCT_BUNDLE_IDENTIFIER)</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>$(PRODUCT_NAME)</string>
    <key>CFBundlePackageType</key>
    <string>$(PRODUCT_BUNDLE_PACKAGE_TYPE)</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
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
                creationError = "Failed to create Info.plist: \(error.localizedDescription)"
            }
        }
    }

    private var filteredKeys: [String] {
        guard fileURL != nil else { return [] }
        return editor.entries.keys.sorted().filter { key in
            // Category filter
            let passesCategory: Bool
            let lowerKey = key.lowercased()
            switch selectedCategory {
            case .all, .rawXML:
                passesCategory = true
            case .identity:
                passesCategory = lowerKey.hasPrefix("cfbundle") || lowerKey.contains("name") || lowerKey.contains("version") || lowerKey.contains("identifier") || lowerKey.contains("copyright") || lowerKey.contains("category")
            case .permissions:
                passesCategory = lowerKey.contains("usage") || lowerKey.contains("privacy") || lowerKey.hasPrefix("ns")
            case .display:
                passesCategory = lowerKey.contains("interface") || lowerKey.contains("scene") || lowerKey.contains("orientation") || lowerKey.contains("status") || lowerKey.contains("icon") || lowerKey.contains("principal") || lowerKey.contains("resolution")
            case .urlSchemes:
                passesCategory = lowerKey.contains("url") || lowerKey.contains("scheme") || lowerKey.contains("document")
            }

            guard passesCategory else { return false }

            if searchQuery.isEmpty { return true }
            let lowerQuery = searchQuery.lowercased()
            let matchesKey = key.lowercased().contains(lowerQuery)
            let matchesVal = String(describing: editor.entries[key] ?? "").lowercased().contains(lowerQuery)
            let matchesType = plistValueKind(of: editor.entries[key] ?? "").rawValue.lowercased().contains(lowerQuery)
            let matchesMetadata = InfoPlistNSStrings.all.contains { meta in
                meta.key == key && (meta.name.lowercased().contains(lowerQuery) || meta.description.lowercased().contains(lowerQuery))
            }
            return matchesKey || matchesVal || matchesType || matchesMetadata
        }
    }

    /// Produces a copy key that cannot collide with an existing key.
    private func uniqueCopyKey(basedOn key: String) -> String {
        var candidate = "\(key) copy"
        var n = 2
        while editor.entries[candidate] != nil {
            candidate = "\(key) copy \(n)"
            n += 1
        }
        return candidate
    }

    private func savePlist() {
        do {
            try editor.save()
            syncXMLPreview()
            toolStatus = "Info.plist saved to disk."
        } catch {
            toolStatus = "Save failed: \(error.localizedDescription)"
        }
    }

    public var body: some View {
        if fileURL == nil {
            VStack(spacing: 20) {
                ContentUnavailableView {
                    Label("No Info.plist Configured", systemImage: "info.circle")
                } description: {
                    Text("The currently selected target does not contain an Info.plist configuration file.\n\nYou can create a standard Info.plist file in your project workspace.")
                }

                if let error = creationError {
                    Text(error)
                        .foregroundColor(.red)
                        .font(.callout)
                }

                Button {
                    createInfoPlist()
                } label: {
                    Label(isCreating ? "Creating..." : "Create Info.plist", systemImage: "plus")
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

                // Segmented Category Switcher
                HStack {
                    Picker("Category", selection: $selectedCategory) {
                        ForEach(InfoPlistCategory.allCases) { cat in
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
                if selectedCategory == .rawXML {
                    rawXMLEditorView
                } else {
                    propertiesListView
                }
            }
            .sheet(isPresented: $showingAddKeySheet) {
                addKeySheetView
            }
            .sheet(isPresented: $showingInspectorSheet) {
                inspectorSheetView
            }
            .onAppear {
                if fileURL != nil {
                    syncXMLPreview()
                }
            }
        }
    }

    // MARK: - Header Toolbar
    private var headerToolbar: some View {
        HStack(spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "doc.text")
                    .foregroundStyle(.secondary)
                Text(fileURL?.lastPathComponent ?? "Info.plist")
                    .font(.headline)
                Text("(\(editor.entries.count) properties)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if editor.isDirty {
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
                TextField("Search keys, values, or types...", text: $searchQuery)
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
            .frame(width: 220)

            // Undo / Redo
            HStack(spacing: 4) {
                Button {
                    editor.undo()
                    syncXMLPreview()
                } label: {
                    Image(systemName: "arrow.uturn.backward")
                }
                .buttonStyle(.bordered)
                .disabled(!editor.canUndo)
                .help("Undo")

                Button {
                    editor.redo()
                    syncXMLPreview()
                } label: {
                    Image(systemName: "arrow.uturn.forward")
                }
                .buttonStyle(.bordered)
                .disabled(!editor.canRedo)
                .help("Redo")
            }

            // Quick Privacy Presets Menu
            Menu {
                Button {
                    addPrivacyPreset(key: "NSCameraUsageDescription", defaultText: "This application requires access to the camera.")
                } label: {
                    Label("Camera Usage (NSCameraUsageDescription)", systemImage: "camera")
                }

                Button {
                    addPrivacyPreset(key: "NSPhotoLibraryUsageDescription", defaultText: "This application requires access to photo library.")
                } label: {
                    Label("Photo Library (NSPhotoLibraryUsageDescription)", systemImage: "photo.on.rectangle")
                }

                Button {
                    addPrivacyPreset(key: "NSMicrophoneUsageDescription", defaultText: "This application requires microphone access.")
                } label: {
                    Label("Microphone (NSMicrophoneUsageDescription)", systemImage: "mic")
                }

                Button {
                    addPrivacyPreset(key: "NSLocationWhenInUseUsageDescription", defaultText: "This application requires location access while in use.")
                } label: {
                    Label("Location (NSLocationWhenInUseUsageDescription)", systemImage: "location")
                }

                Button {
                    addPrivacyPreset(key: "NSFaceIDUsageDescription", defaultText: "This application requires Face ID for biometric authentication.")
                } label: {
                    Label("Face ID (NSFaceIDUsageDescription)", systemImage: "faceid")
                }

                Button {
                    addPrivacyPreset(key: "NSCalendarsUsageDescription", defaultText: "This application requires access to calendar events.")
                } label: {
                    Label("Calendar (NSCalendarsUsageDescription)", systemImage: "calendar")
                }

                Button {
                    addPrivacyPreset(key: "NSLocalNetworkUsageDescription", defaultText: "This application requires local network access to discover devices.")
                } label: {
                    Label("Local Network (NSLocalNetworkUsageDescription)", systemImage: "network")
                }
            } label: {
                Label("Privacy Presets", systemImage: "lock.shield")
            }
            .menuStyle(.borderedButton)

            // Validate Structure Tool
            Button {
                validateStructure()
            } label: {
                Label("Validate", systemImage: "checkmark.seal")
            }
            .buttonStyle(.bordered)
            .help("Validate Info.plist required keys & structure")

            // Copy XML Tool
            Button {
                syncXMLPreview()
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(xmlEditorText, forType: .string)
                toolStatus = "Copied Raw XML to clipboard"
            } label: {
                Label("Copy XML", systemImage: "doc.on.doc")
            }
            .buttonStyle(.bordered)

            // Save Tool
            Button {
                savePlist()
            } label: {
                Label("Save", systemImage: "square.and.arrow.down")
            }
            .buttonStyle(.bordered)
            .disabled(!editor.isDirty)
            .keyboardShortcut("s", modifiers: .command)
            .help("Write changes to the Info.plist file")

            // Add Property
            Button {
                showingAddKeySheet = true
            } label: {
                Label("Add Key", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color(NSColor.windowBackgroundColor))
    }

    private func addPrivacyPreset(key: String, defaultText: String) {
        guard editor.entries[key] == nil else {
            toolStatus = "\(key) already exists."
            return
        }
        editor.set(key: key, value: defaultText)
        syncXMLPreview()
        toolStatus = "Added \(key)"
    }

    private func validateStructure() {
        var issues: [String] = []
        if editor.entries["CFBundleIdentifier"] == nil {
            issues.append("Missing CFBundleIdentifier")
        }
        if editor.entries["CFBundleShortVersionString"] == nil {
            issues.append("Missing CFBundleShortVersionString")
        }
        if editor.entries["CFBundleVersion"] == nil {
            issues.append("Missing CFBundleVersion")
        }
        let privacyIssues = editor.validatePrivacyKeys()
        for (key, message) in privacyIssues {
            issues.append("\(key): \(message)")
        }

        if issues.isEmpty {
            toolStatus = "Info.plist validated successfully. Required identity keys are present."
        } else {
            toolStatus = "Validation warning: " + issues.joined(separator: "; ")
        }
    }

    // MARK: - Properties List View
    private var propertiesListView: some View {
        List {
            if filteredKeys.isEmpty {
                ContentUnavailableView(
                    "No Properties Found",
                    systemImage: "doc.text.magnifyingglass",
                    description: Text(searchQuery.isEmpty ? "Click 'Add Key' or select a Privacy Preset to add properties." : "No properties match '\(searchQuery)'.")
                )
                .padding()
            } else {
                ForEach(filteredKeys, id: \.self) { key in
                    InfoPlistRow(
                        key: key,
                        value: editor.entries[key] ?? "",
                        onSelect: {
                            selectedKey = key
                            showingInspectorSheet = true
                        },
                        onDuplicate: {
                            let val = editor.entries[key] ?? ""
                            let copyKey = uniqueCopyKey(basedOn: key)
                            editor.set(key: copyKey, value: val)
                            syncXMLPreview()
                            toolStatus = "Duplicated to \(copyKey)"
                        },
                        onDelete: {
                            editor.remove(key: key)
                            if selectedKey == key { selectedKey = nil }
                            syncXMLPreview()
                        },
                        onValueChange: { newVal in
                            editor.set(key: key, value: newVal)
                            syncXMLPreview()
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
                Label("Raw XML Editor", systemImage: "doc.plaintext")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Re-format XML") {
                    syncXMLPreview()
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
                    // Skip programmatic syncs; only parse genuine user edits.
                    guard newValue != editor.generateRawXML() else { return }
                    _ = try? editor.updateFromXML(newValue)
                }
        }
    }

    private func syncXMLPreview() {
        xmlEditorText = editor.generateRawXML()
    }

    // MARK: - Add Key Sheet
    private var addKeySheetView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Add Info.plist Key")
                .font(.headline)

            Picker("Template Category", selection: $templateCategory) {
                ForEach(InfoPlistTemplateCatalog.categories, id: \.self) { category in
                    Text(category).tag(category)
                }
            }
            .pickerStyle(.segmented)

            Text("Templates")
                .font(.subheadline.bold())
                .foregroundStyle(.secondary)

            List(InfoPlistTemplateCatalog.templates(in: templateCategory)) { template in
                let exists = editor.entries[template.key] != nil
                HStack(spacing: 10) {
                    Image(systemName: template.symbol)
                        .foregroundStyle(.secondary)
                        .frame(width: 24)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(template.name)
                            .font(.body.weight(.medium))
                        Text(template.key)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    PlistTypeBadge(kind: template.kind)
                    if exists {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.secondary)
                            .help("Already present")
                    } else {
                        Button("Add") {
                            editor.set(key: template.key, value: template.defaultValue)
                            syncXMLPreview()
                            toolStatus = "Added \(template.key)"
                            showingAddKeySheet = false
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
                .padding(.vertical, 4)
            }
            .frame(minHeight: 220)

            Divider()

            Text("Custom Key")
                .font(.subheadline.bold())
                .foregroundStyle(.secondary)

            HStack {
                TextField("Key name (e.g. MyCustomProperty)", text: $newCustomKey)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))

                Picker("Value Type", selection: $newCustomType) {
                    ForEach(PlistValueKind.allCases, id: \.self) { kind in
                        Label(kind.rawValue, systemImage: kind.symbol).tag(kind)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 150)
            }

            let trimmedKey = newCustomKey.trimmingCharacters(in: .whitespaces)
            let keyExists = !trimmedKey.isEmpty && editor.entries[trimmedKey] != nil
            if keyExists {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle")
                    Text("A key named '\(trimmedKey)' already exists. Choose a different name.")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            HStack {
                Button("Cancel") {
                    showingAddKeySheet = false
                    newCustomKey = ""
                }
                .buttonStyle(.bordered)

                Spacer()

                Button("Add Key") {
                    editor.set(key: trimmedKey, value: defaultPlistValue(for: newCustomType))
                    syncXMLPreview()
                    toolStatus = "Added \(trimmedKey) (\(newCustomType.rawValue))"
                    showingAddKeySheet = false
                    newCustomKey = ""
                }
                .buttonStyle(.borderedProminent)
                .disabled(trimmedKey.isEmpty || keyExists)
            }
        }
        .padding()
        .frame(width: 560, height: 600)
    }

    // MARK: - Inspector Sheet
    private var inspectorSheetView: some View {
        VStack(spacing: 0) {
            HStack {
                Label("Property Inspector", systemImage: "info.circle")
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
                let metadata = InfoPlistNSStrings.all.first(where: { $0.key == key })
                InfoPlistInspectorPanel(
                    key: key,
                    value: Binding(
                        get: { editor.entries[key] ?? "" },
                        set: { newVal in
                            editor.set(key: key, value: newVal)
                            syncXMLPreview()
                        }
                    ),
                    metadata: metadata,
                    editor: editor
                )
            } else {
                ContentUnavailableView("No Key Selected", systemImage: "info.circle")
            }
        }
        .frame(width: 540, height: 520)
    }
}

// MARK: - Type Badge

struct PlistTypeBadge: View {
    let kind: PlistValueKind

    var body: some View {
        Text(kind.rawValue)
            .font(.caption2)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color(NSColor.controlBackgroundColor), in: Capsule())
    }
}

// MARK: - Inline Scalar Value Editor (used in rows)

/// Edits scalar plist values inline. Arrays, dictionaries, and data show a
/// summary — they are edited in the inspector panel instead.
struct PlistInlineScalarEditor: View {
    @Binding var value: Any

    var body: some View {
        Group {
            switch plistValueKind(of: value) {
            case .boolean:
                Toggle("", isOn: Binding(
                    get: { (value as? Bool) ?? false },
                    set: { value = $0 }
                ))
                .toggleStyle(.switch)
                .labelsHidden()
            case .number:
                TextField("", text: numberTextBinding)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
            case .date:
                DatePicker("", selection: Binding(
                    get: { (value as? Date) ?? Date() },
                    set: { value = $0 }
                ), displayedComponents: [.date, .hourAndMinute])
                .labelsHidden()
            case .string:
                TextField("", text: Binding(
                    get: { (value as? String) ?? String(describing: value) },
                    set: { value = $0 }
                ))
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))
            case .data:
                Text("Data (\((value as? Data)?.count ?? 0) bytes)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color(NSColor.controlBackgroundColor), in: RoundedRectangle(cornerRadius: 4))
            case .array:
                Text("\((value as? [Any])?.count ?? 0) items")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color(NSColor.controlBackgroundColor), in: RoundedRectangle(cornerRadius: 4))
            case .dictionary:
                Text("Dictionary (\((value as? [String: Any])?.count ?? 0) keys)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color(NSColor.controlBackgroundColor), in: RoundedRectangle(cornerRadius: 4))
            }
        }
    }

    private var numberTextBinding: Binding<String> {
        Binding(
            get: {
                guard let number = value as? NSNumber else { return "" }
                let d = number.doubleValue
                if d.truncatingRemainder(dividingBy: 1) == 0 && abs(d) < 9_007_199_254_740_992 {
                    return String(Int(d))
                }
                return String(d)
            },
            set: { text in
                if let d = Double(text) {
                    value = NSNumber(value: d)
                }
            }
        )
    }
}

// MARK: - Array Editor

struct PlistArrayEditorView: View {
    @Binding var items: [Any]
    @State private var newItemKind: PlistValueKind = .string

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if items.isEmpty {
                Text("Empty array. Add items below.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ForEach(items.indices, id: \.self) { index in
                HStack(spacing: 8) {
                    Text("\(index)")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .frame(width: 24, alignment: .trailing)
                    PlistTypeBadge(kind: plistValueKind(of: items[index]))
                    PlistInlineScalarEditor(value: Binding(
                        get: { items[index] },
                        set: { items[index] = $0 }
                    ))
                    Spacer()
                    Button {
                        items.remove(at: index)
                    } label: {
                        Image(systemName: "minus.circle")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Remove item")
                }
                .padding(6)
                .background(Color(NSColor.controlBackgroundColor).opacity(0.5), in: RoundedRectangle(cornerRadius: 6))
            }

            HStack {
                Picker("New item type", selection: $newItemKind) {
                    ForEach(PlistValueKind.allCases, id: \.self) { kind in
                        Label(kind.rawValue, systemImage: kind.symbol).tag(kind)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                Button("Add Item") {
                    items.append(defaultPlistValue(for: newItemKind))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                Spacer()
            }
        }
    }
}

// MARK: - Dictionary Editor

struct PlistDictionaryEditorView: View {
    @Binding var dict: [String: Any]
    @State private var newKey = ""
    @State private var newKind: PlistValueKind = .string
    @State private var keyExistsWarning = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if dict.isEmpty {
                Text("Empty dictionary. Add entries below.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ForEach(dict.keys.sorted(), id: \.self) { key in
                HStack(spacing: 8) {
                    Text(key)
                        .font(.system(.body, design: .monospaced))
                        .frame(minWidth: 110, alignment: .leading)
                        .lineLimit(1)
                    PlistTypeBadge(kind: plistValueKind(of: dict[key] ?? ""))
                    PlistInlineScalarEditor(value: Binding(
                        get: { dict[key] ?? "" },
                        set: { dict[key] = $0 }
                    ))
                    Spacer()
                    Button {
                        dict.removeValue(forKey: key)
                    } label: {
                        Image(systemName: "minus.circle")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Remove entry")
                }
                .padding(6)
                .background(Color(NSColor.controlBackgroundColor).opacity(0.5), in: RoundedRectangle(cornerRadius: 6))
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    TextField("New key", text: $newKey)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                    Picker("Type", selection: $newKind) {
                        ForEach(PlistValueKind.allCases, id: \.self) { kind in
                            Text(kind.rawValue).tag(kind)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    Button("Add") {
                        let trimmed = newKey.trimmingCharacters(in: .whitespaces)
                        guard !trimmed.isEmpty else { return }
                        guard dict[trimmed] == nil else {
                            keyExistsWarning = true
                            return
                        }
                        dict[trimmed] = defaultPlistValue(for: newKind)
                        newKey = ""
                        keyExistsWarning = false
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(newKey.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                if keyExistsWarning {
                    Text("That key already exists in this dictionary.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .onChange(of: newKey) { _, _ in
            keyExistsWarning = false
        }
    }
}

// MARK: - Data (Hex) Editor

struct PlistDataEditorView: View {
    @Binding var data: Data
    @State private var hexText: String = ""
    @State private var hexError: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("\(data.count) bytes")
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField("Hex bytes, e.g. 0A1B2C", text: $hexText)
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))
                .onAppear {
                    hexText = data.map { String(format: "%02X", $0) }.joined()
                }
            if let error = hexError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Button("Apply Hex") {
                if let parsed = Data(hexString: hexText) {
                    data = parsed
                    hexError = nil
                } else {
                    hexError = "Invalid hex. Use pairs of 0-9/A-F characters."
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }
}

private extension Data {
    init?(hexString: String) {
        let cleaned = hexString
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "\n", with: "")
        guard !cleaned.isEmpty, cleaned.count % 2 == 0 else { return nil }
        var result = Data()
        var index = cleaned.startIndex
        while index < cleaned.endIndex {
            let next = cleaned.index(index, offsetBy: 2)
            guard let byte = UInt8(cleaned[index..<next], radix: 16) else { return nil }
            result.append(byte)
            index = next
        }
        self = result
    }
}

// MARK: - Clean Monochrome Row View
struct InfoPlistRow: View {
    let key: String
    let value: Any
    let onSelect: () -> Void
    let onDuplicate: () -> Void
    let onDelete: () -> Void
    let onValueChange: (Any) -> Void

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(key)
                        .font(.system(.body, design: .monospaced).weight(.medium))
                        .lineLimit(1)
                    PlistTypeBadge(kind: plistValueKind(of: value))
                }

                if let meta = InfoPlistNSStrings.all.first(where: { $0.key == key }) {
                    Text(meta.name)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(minWidth: 240, alignment: .leading)

            Spacer()

            // Value Editor (scalars inline; collections open in the inspector)
            PlistInlineScalarEditor(value: Binding(
                get: { value },
                set: onValueChange
            ))
            .frame(minWidth: 180, maxWidth: 320)

            // Inspect
            Button(action: onSelect) {
                Image(systemName: "slider.horizontal.3")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Inspect Property")

            // Duplicate
            Button(action: onDuplicate) {
                Image(systemName: "plus.square.on.square")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Duplicate Property")

            // Delete
            Button(action: onDelete) {
                Image(systemName: "trash")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Delete Property")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }
}

// MARK: - Inspector Panel

struct InfoPlistInspectorPanel: View {
    let key: String
    @Binding var value: Any
    let metadata: InfoPlistNSString?
    let editor: InfoPlistEditor

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(metadata?.name ?? key)
                            .font(.title3.bold())
                        Spacer()
                        PlistTypeBadge(kind: plistValueKind(of: value))
                    }
                    Text(key)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                }

                if let desc = metadata?.description {
                    Text(desc)
                        .font(.body)
                        .foregroundStyle(.secondary)
                }

                validationHints

                Divider()

                Text("Value")
                    .font(.subheadline.bold())

                switch plistValueKind(of: value) {
                case .array:
                    PlistArrayEditorView(items: Binding(
                        get: { (value as? [Any]) ?? [] },
                        set: { value = $0 }
                    ))
                case .dictionary:
                    PlistDictionaryEditorView(dict: Binding(
                        get: { (value as? [String: Any]) ?? [:] },
                        set: { value = $0 }
                    ))
                case .data:
                    PlistDataEditorView(data: Binding(
                        get: { (value as? Data) ?? Data() },
                        set: { value = $0 }
                    ))
                default:
                    PlistInlineScalarEditor(value: $value)
                }

                if let meta = metadata {
                    Divider()
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Category: \(meta.category)")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Text("Expected Type: \(meta.valueType.rawValue)")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        if !meta.recommendedWording.isEmpty {
                            Text("Apple Recommendation: \(meta.recommendedWording)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .padding(20)
        }
    }

    @ViewBuilder
    private var validationHints: some View {
        if key == "CFBundleIdentifier", let s = value as? String, !editor.validateBundleIdentifier(s) {
            validationHintRow("This bundle identifier contains invalid characters. Use only letters, numbers, dots, and hyphens.")
        }
        if key == "CFBundleShortVersionString", let s = value as? String, !editor.validateVersion(s) {
            validationHintRow("Version strings should use dot-separated numbers, e.g. 1.0.2.")
        }
        if let issue = editor.validatePrivacyKeys()[key] {
            validationHintRow(issue)
        }
    }

    private func validationHintRow(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle")
                .foregroundStyle(.secondary)
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(NSColor.controlBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
    }
}
