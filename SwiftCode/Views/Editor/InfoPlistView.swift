import SwiftUI
import UniformTypeIdentifiers

public struct InfoPlistView: View {
    private let fileURL: URL?
    @State private var editor: InfoPlistEditor
    @State private var searchQuery = ""
    @State private var selectedKey: String? = nil
    @State private var selectedCategory: InfoPlistCategory = .all
    @State private var xmlEditorText = ""
    @State private var showingAddKeySheet = false
    @State private var newCustomKey = ""
    @State private var newCustomType: InfoPlistNSString.ValueType = .string
    @State private var showingInspectorSheet = false
    @State private var validationMessage: String? = nil
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
                passesCategory = lowerKey.hasPrefix("cfbundle") || lowerKey.contains("name") || lowerKey.contains("version") || lowerKey.contains("identifier")
            case .permissions:
                passesCategory = lowerKey.contains("usage") || lowerKey.contains("privacy") || lowerKey.hasPrefix("ns")
            case .display:
                passesCategory = lowerKey.contains("interface") || lowerKey.contains("scene") || lowerKey.contains("orientation") || lowerKey.contains("status") || lowerKey.contains("icon")
            case .urlSchemes:
                passesCategory = lowerKey.contains("url") || lowerKey.contains("scheme")
            }

            guard passesCategory else { return false }

            if searchQuery.isEmpty { return true }
            let lowerQuery = searchQuery.lowercased()
            let matchesKey = key.lowercased().contains(lowerQuery)
            let matchesVal = String(describing: editor.entries[key] ?? "").lowercased().contains(lowerQuery)
            let matchesMetadata = InfoPlistNSStrings.all.contains { meta in
                meta.key == key && (meta.name.lowercased().contains(lowerQuery) || meta.description.lowercased().contains(lowerQuery))
            }
            return matchesKey || matchesVal || matchesMetadata
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
            }

            Spacer()

            // Search Bar
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search keys or values...", text: $searchQuery)
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
            .frame(width: 200)

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

        if issues.isEmpty {
            toolStatus = "Info.plist validated successfully. Required identity keys are present."
        } else {
            toolStatus = "Validation warning: " + issues.joined(separator: ", ")
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
                        editor: editor,
                        onSelect: {
                            selectedKey = key
                            showingInspectorSheet = true
                        },
                        onDuplicate: {
                            let val = editor.entries[key] ?? ""
                            let copyKey = "\(key)_Copy"
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
                    _ = try? editor.updateFromXML(newValue)
                }
        }
    }

    private func syncXMLPreview() {
        xmlEditorText = editor.generateRawXML()
    }

    // MARK: - Add Key Sheet
    private var addKeySheetView: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Add Info.plist Key")
                .font(.headline)

            Picker("Suggested Key", selection: $newCustomKey) {
                Text("Custom Key...").tag("")
                ForEach(InfoPlistNSStrings.all) { meta in
                    Text("\(meta.name) (\(meta.key))").tag(meta.key)
                }
            }
            .pickerStyle(.menu)

            if newCustomKey.isEmpty {
                TextField("Custom Key Name (e.g. MyCustomProperty)", text: $newCustomKey)
                    .textFieldStyle(.roundedBorder)

                Picker("Value Type", selection: $newCustomType) {
                    ForEach(InfoPlistNSString.ValueType.allCases, id: \.self) { type in
                        Text(type.rawValue).tag(type)
                    }
                }
                .pickerStyle(.menu)
            }

            Spacer()

            HStack {
                Button("Cancel") {
                    showingAddKeySheet = false
                }
                .buttonStyle(.bordered)

                Spacer()

                Button("Add Key") {
                    if !newCustomKey.isEmpty {
                        editor.addMissingKey(newCustomKey)
                        syncXMLPreview()
                        showingAddKeySheet = false
                        newCustomKey = ""
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(newCustomKey.isEmpty)
            }
        }
        .padding()
        .frame(width: 440, height: 260)
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
                    value: editor.entries[key] ?? "",
                    metadata: metadata,
                    onSaveValue: { newVal in
                        editor.set(key: key, value: newVal)
                        syncXMLPreview()
                    }
                )
            } else {
                ContentUnavailableView("No Key Selected", systemImage: "info.circle")
            }
        }
        .frame(width: 500, height: 450)
    }
}

// MARK: - Clean Monochrome Row View
struct InfoPlistRow: View {
    let key: String
    let value: Any
    let editor: InfoPlistEditor
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

                if let meta = InfoPlistNSStrings.all.first(where: { $0.key == key }) {
                    Text(meta.name)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(minWidth: 220, alignment: .leading)

            Spacer()

            // Value Editor
            if let boolVal = value as? Bool {
                Toggle("", isOn: Binding(
                    get: { boolVal },
                    set: { onValueChange($0) }
                ))
                .toggleStyle(.switch)
                .labelsHidden()
            } else if let arrVal = value as? [Any] {
                Text("\(arrVal.count) items")
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color(NSColor.controlBackgroundColor), in: RoundedRectangle(cornerRadius: 4))
            } else if let dictVal = value as? [String: Any] {
                Text("Dictionary (\(dictVal.count) keys)")
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
                .frame(minWidth: 180, maxWidth: 300)
            }

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

struct InfoPlistInspectorPanel: View {
    let key: String
    let value: Any
    let metadata: InfoPlistNSString?
    let onSaveValue: (Any) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(metadata?.name ?? key)
                        .font(.title3.bold())
                    Text(key)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                }

                if let desc = metadata?.description {
                    Text(desc)
                        .font(.body)
                        .foregroundStyle(.secondary)
                }

                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    Text("Current Value:")
                        .font(.subheadline.bold())

                    Text(String(describing: value))
                        .font(.system(.body, design: .monospaced))
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(NSColor.controlBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
                }

                if let meta = metadata {
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
}
