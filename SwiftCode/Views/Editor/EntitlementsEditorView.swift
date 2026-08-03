import SwiftUI
import UniformTypeIdentifiers

public struct EntitlementsEditorView: View {
    private let fileURL: URL?
    @State private var manager: EntitlementsEditorManager
    @State private var entitlementsDict: [String: Any] = [:]
    @State private var searchQuery = ""
    @State private var selectedCategory: EntitlementCategory? = nil
    @State private var selectedKey: String? = nil
    @State private var xmlEditorText = ""
    @State private var showXMLSheet = false
    @State private var showingAddSheet = false
    @State private var showingInspectorSheet = false
    @Environment(WorkspaceViewModel.self) private var workspaceViewModel
    @State private var isCreating = false
    @State private var creationError: String? = nil

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
                    if isCreating {
                        ProgressView()
                            .controlSize(.small)
                            .padding(.horizontal)
                    } else {
                        Text("Create Entitlements File")
                            .font(.headline)
                            .padding(.horizontal)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isCreating)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.ultraThinMaterial)
            .macDesktopOptimized()
        } else {
            VStack(spacing: 0) {
                // Interactive Statistics and Validation Banner
                HStack(spacing: 16) {
                    Label {
                        Text("\(entitlementsDict.count) Capabilities Configured")
                            .font(.subheadline.bold())
                    } icon: {
                        Image(systemName: "lock.shield.fill")
                            .foregroundColor(.orange)
                    }

                    Spacer()

                    let validation = validationResult
                    if validation.errors.isEmpty && validation.warnings.isEmpty {
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.seal.fill")
                                .foregroundStyle(.green)
                            Text("Sandbox Validated")
                                .font(.caption.bold())
                                .foregroundColor(.green)
                        }
                    } else {
                        HStack(spacing: 4) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.yellow)
                            Text("Validation Issues Found")
                                .font(.caption.bold())
                                .foregroundColor(.orange)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color.orange.opacity(0.05))

                Divider()

                // Top Modern Action Bar
                HStack(spacing: 12) {
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
                    .padding(8)
                    .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))

                    Spacer()

                    // Category Filter Picker
                    Picker("", selection: $selectedCategory) {
                        Text("All Categories").tag(nil as EntitlementCategory?)
                        ForEach(EntitlementCategory.allCases, id: \.self) { cat in
                            Text(cat.rawValue).tag(cat as EntitlementCategory?)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 150)

                    // View XML Sheet
                    Button {
                        syncXMLText()
                        showXMLSheet = true
                    } label: {
                        Label("Raw XML", systemImage: "chevron.left.forwardslash.chevron.right")
                    }
                    .buttonStyle(.bordered)

                    // Save Button
                    Button {
                        try? manager.writeEntitlements(entitlementsDict)
                    } label: {
                        Text("Save")
                    }
                    .buttonStyle(.bordered)

                    // Add Cap Button
                    Button {
                        showingAddSheet = true
                    } label: {
                        Label("Capability", systemImage: "plus")
                            .bold()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                }
                .padding()
                .background(.thinMaterial)

                Divider()

                // Validation summary banner
                validationBanner

                // Entitlements list
                List {
                    Section("Active App Capabilities") {
                        let filtered = activeKeys.filter { key in
                            if let cat = selectedCategory {
                                let meta = EntitlementsCatalog.all.first(where: { $0.rawKey == key })
                                return meta?.category == cat
                            }
                            return true
                        }

                        if filtered.isEmpty {
                            ContentUnavailableView("No Active Capabilities", systemImage: "lock.shield", description: Text("Click 'Capability' or check categories to enable them."))
                                .padding()
                        } else {
                            ForEach(filtered, id: \.self) { key in
                                EntitlementRowView(
                                    key: key,
                                    value: entitlementsDict[key] ?? "",
                                    isFavorite: false,
                                    onSelect: {
                                        selectedKey = key
                                        showingInspectorSheet = true
                                    },
                                    onToggleFavorite: {},
                                    onDelete: {
                                        entitlementsDict.removeValue(forKey: key)
                                        if selectedKey == key { selectedKey = nil }
                                        syncXMLText()
                                    },
                                    onValueChange: { newVal in
                                        entitlementsDict[key] = newVal
                                        syncXMLText()
                                    }
                                )
                                .padding(.vertical, 4)
                                .background(Color.primary.opacity(0.02))
                                .cornerRadius(10)
                            }
                        }
                    }
                }
                .listStyle(.inset)
            }
            .sheet(isPresented: $showXMLSheet) {
                // XML View Sheet
                VStack(spacing: 0) {
                    HStack {
                        Label("Entitlements XML Editor", systemImage: "lock.shield")
                            .font(.headline)
                        Spacer()
                        Button("Done") {
                            showXMLSheet = false
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.orange)
                    }
                    .padding()
                    .background(.thinMaterial)

                    Divider()

                    TextEditor(text: $xmlEditorText)
                        .font(.system(.body, design: .monospaced))
                        .padding()
                        .onChange(of: xmlEditorText) { _, newValue in
                            if let parsed = try? manager.parseRawXML(newValue) {
                                self.entitlementsDict = parsed
                            }
                        }
                }
                .frame(width: 650, height: 480)
            }
            .sheet(isPresented: $showingAddSheet) {
                addCapabilitySheetView
            }
            .sheet(isPresented: $showingInspectorSheet) {
                // Inspector Details Sheet
                VStack(spacing: 0) {
                    HStack {
                        Label("Capability Inspector", systemImage: "info.circle")
                            .font(.headline)
                        Spacer()
                        Button("Done") {
                            showingInspectorSheet = false
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding()
                    .background(.thinMaterial)

                    Divider()

                    if let key = selectedKey {
                        let metadata = EntitlementsCatalog.all.first(where: { $0.rawKey == key })
                        EntitlementInspectorPanel(
                            key: key,
                            value: entitlementsDict[key] ?? "",
                            metadata: metadata,
                            onUpdateValue: { newVal in
                                entitlementsDict[key] = newVal
                                syncXMLText()
                            }
                        )
                    } else {
                        ContentUnavailableView("No Capability Selected", systemImage: "info.circle")
                    }
                }
                .frame(width: 500, height: 450)
            }
            .onAppear {
                if fileURL != nil {
                    syncXMLText()
                }
            }
        }
    }

    private func syncXMLText() {
        xmlEditorText = manager.generateRawXML(entitlementsDict)
    }

    // MARK: - Subviews

    private var validationBanner: some View {
        let result = validationResult
        return Group {
            if !result.warnings.isEmpty || !result.errors.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(result.errors) { err in
                        HStack {
                            Image(systemName: "exclamationmark.octagon.fill")
                                .foregroundStyle(.red)
                            Text("\(err.rawKey): \(err.message)")
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                    }
                    ForEach(result.warnings) { warn in
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.yellow)
                            Text("\(warn.rawKey): \(warn.message)")
                                .font(.caption)
                                .foregroundStyle(.primary)
                        }
                    }
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.yellow.opacity(0.12))
                .overlay(
                    Rectangle().frame(height: 1).foregroundColor(Color.yellow.opacity(0.3)), alignment: .bottom
                )
            }
        }
    }

    private var addCapabilitySheetView: some View {
        let available = EntitlementsCatalog.all.filter { entitlementsDict[$0.rawKey] == nil }
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Add Capability Entitlement")
                    .font(.headline)
                Spacer()
                Button("Close") {
                    showingAddSheet = false
                }
                .buttonStyle(.bordered)
            }
            .padding(.bottom, 6)

            Divider()

            if available.isEmpty {
                ContentUnavailableView("All capabilities already added", systemImage: "checkmark.seal")
            } else {
                List(available) { meta in
                    Button {
                        if meta.valueType == .boolean {
                            entitlementsDict[meta.rawKey] = true
                        } else if meta.valueType == .array {
                            entitlementsDict[meta.rawKey] = [String]()
                        } else {
                            entitlementsDict[meta.rawKey] = ""
                        }
                        syncXMLText()
                        showingAddSheet = false
                    } label: {
                        HStack {
                            Image(systemName: meta.sfSymbol)
                                .foregroundStyle(.blue)
                                .frame(width: 20)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(meta.displayName)
                                    .font(.body.bold())
                                Text(meta.rawKey)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .padding(.vertical, 4)
                }
            }
        }
        .padding()
        .frame(width: 400, height: 420)
    }
}

// MARK: - Subviews for Entitlements List & Inspector

struct EntitlementRowView: View {
    let key: String
    let value: Any
    let isFavorite: Bool
    let onSelect: () -> Void
    let onToggleFavorite: () -> Void
    let onDelete: () -> Void
    let onValueChange: (Any) -> Void

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(key)
                    .font(.headline)
                    .lineLimit(1)

                if let meta = EntitlementsCatalog.all.first(where: { $0.rawKey == key }) {
                    Text(meta.displayName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            // Value Editor
            if let boolVal = value as? Bool {
                Toggle("", isOn: Binding(
                    get: { boolVal },
                    set: { onValueChange($0) }
                ))
                .toggleStyle(.switch)
                .labelsHidden()
            } else if let arrVal = value as? [String] {
                Text("\(arrVal.count) items")
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
            } else {
                TextField("", text: Binding(
                    get: { String(describing: value) },
                    set: { onValueChange($0) }
                ))
                .textFieldStyle(.roundedBorder)
                .frame(width: 180)
            }

            // Inspect
            Button(action: onSelect) {
                Image(systemName: "info.circle")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)

            // Delete
            Button(action: onDelete) {
                Image(systemName: "trash")
                    .foregroundStyle(.red)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

struct EntitlementInspectorPanel: View {
    let key: String
    let value: Any
    let metadata: EntitlementMetadata?
    let onUpdateValue: (Any) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(metadata?.displayName ?? key)
                        .font(.title3.bold())
                    Text(key)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let meta = metadata {
                    VStack(alignment: .leading, spacing: 12) {
                        GroupBox(label: Label("Description", systemImage: "doc.text")) {
                            Text(meta.entitlementDescription)
                                .font(.body)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.top, 4)
                        }

                        GroupBox(label: Label("Recommended Usage", systemImage: "hand.thumbsup")) {
                            Text(meta.recommendedUsage)
                                .font(.body)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.top, 4)
                        }

                        GroupBox(label: Label("Metadata Info", systemImage: "info.circle")) {
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text("Category:")
                                        .bold()
                                    Text(meta.category.rawValue)
                                }
                                HStack {
                                    Text("Value Type:")
                                        .bold()
                                    Text(meta.valueType.rawValue)
                                }
                                HStack {
                                    Text("Platforms:")
                                        .bold()
                                    Text(meta.supportedPlatforms.map { $0.rawValue }.joined(separator: ", "))
                                }
                            }
                            .font(.caption)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 4)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Value Editor")
                        .font(.headline)

                    if let boolVal = value as? Bool {
                        Toggle("Enabled", isOn: Binding(
                            get: { boolVal },
                            set: { onUpdateValue($0) }
                        ))
                        .toggleStyle(.checkbox)
                    } else if let arrVal = value as? [String] {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(0..<arrVal.count, id: \.self) { idx in
                                HStack {
                                    TextField("Item \(idx + 1)", text: Binding(
                                        get: { arrVal[idx] },
                                        set: { newVal in
                                            var copy = arrVal
                                            copy[idx] = newVal
                                            onUpdateValue(copy)
                                        }
                                    ))
                                    .textFieldStyle(.roundedBorder)

                                    Button {
                                        var copy = arrVal
                                        copy.remove(at: idx)
                                        onUpdateValue(copy)
                                    } label: {
                                        Image(systemName: "minus.circle")
                                            .foregroundStyle(.red)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }

                            Button {
                                var copy = arrVal
                                copy.append("")
                                onUpdateValue(copy)
                            } label: {
                                Label("Add Item", systemImage: "plus")
                            }
                            .buttonStyle(.bordered)
                        }
                    } else {
                        TextField("Value", text: Binding(
                            get: { String(describing: value) },
                            set: { onUpdateValue($0) }
                        ))
                        .textFieldStyle(.roundedBorder)
                    }
                }
                .padding()
                .background(Color.secondary.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))
            }
            .padding()
        }
    }
}
