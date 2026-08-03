import SwiftUI

public struct InfoPlistView: View {
    private let fileURL: URL?
    @State private var editor: InfoPlistEditor
    @State private var searchQuery = ""
    @State private var selectedKey: String? = nil
    @State private var showXMLSheet = false
    @State private var xmlEditorText = ""
    @State private var showingAddKeySheet = false
    @State private var newCustomKey = ""
    @State private var newCustomType: InfoPlistNSString.ValueType = .string
    @State private var showingInspectorSheet = false

    @Environment(\.undoManager) private var undoManager
    @Environment(WorkspaceViewModel.self) private var workspaceViewModel
    @State private var isCreating = false
    @State private var creationError: String? = nil

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
                    if isCreating {
                        ProgressView()
                            .controlSize(.small)
                            .padding(.horizontal)
                    } else {
                        Text("Create Info.plist")
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
                // Modern Top Toolbar Panel
                HStack(spacing: 12) {
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(.secondary)
                        TextField("Search keys or descriptions...", text: $searchQuery)
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

                    // Undo/Redo
                    HStack(spacing: 6) {
                        Button {
                            editor.undo()
                            syncXMLPreview()
                        } label: {
                            Image(systemName: "arrow.uturn.backward")
                                .font(.subheadline.bold())
                        }
                        .buttonStyle(.plain)
                        .disabled(!editor.canUndo)
                        .help("Undo")

                        Button {
                            editor.redo()
                            syncXMLPreview()
                        } label: {
                            Image(systemName: "arrow.uturn.forward")
                                .font(.subheadline.bold())
                        }
                        .buttonStyle(.plain)
                        .disabled(!editor.canRedo)
                        .help("Redo")
                    }
                    .padding(6)
                    .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))

                    // Raw XML Sheet Trigger
                    Button {
                        syncXMLPreview()
                        showXMLSheet = true
                    } label: {
                        Label("Raw XML", systemImage: "chevron.left.forwardslash.chevron.right")
                            .font(.subheadline.bold())
                    }
                    .buttonStyle(.bordered)

                    // Add Key Button
                    Button {
                        showingAddKeySheet = true
                    } label: {
                        Label("Add Key", systemImage: "plus")
                            .bold()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                }
                .padding()
                .background(.thinMaterial)

                Divider()

                // Plist Key Value Table/List
                List {
                    Section("Common Apple Privacy & Security Keys") {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(InfoPlistNSStrings.all.filter { editor.entries[$0.key] == nil }) { meta in
                                    Button {
                                        editor.addMissingKey(meta.key)
                                        syncXMLPreview()
                                    } label: {
                                        HStack {
                                            Image(systemName: meta.sfSymbol)
                                            Text(meta.name)
                                                .font(.caption)
                                        }
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 6)
                                        .background(Color.orange.opacity(0.12))
                                        .cornerRadius(8)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }

                    Section("Configured Properties") {
                        if filteredKeys.isEmpty {
                            ContentUnavailableView("No Keys Found", systemImage: "doc.text.magnifyingglass", description: Text("Click 'Add Key' or use common shortcuts above to begin."))
                                .padding()
                        } else {
                            ForEach(filteredKeys, id: \.self) { key in
                                InfoPlistRow(
                                    key: key,
                                    value: editor.entries[key] ?? "",
                                    editor: editor,
                                    isFavorite: false,
                                    onSelect: {
                                        selectedKey = key
                                        showingInspectorSheet = true
                                    },
                                    onToggleFavorite: {},
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
                // Live raw XML sheet
                VStack(spacing: 0) {
                    HStack {
                        Label("Raw Plist XML Editor", systemImage: "doc.text")
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
                            if (try? editor.updateFromXML(newValue)) != nil {
                                // Real-time parse success
                            }
                        }
                }
                .frame(width: 650, height: 480)
            }
            .sheet(isPresented: $showingAddKeySheet) {
                // Add Key sheet
                addKeySheetView
            }
            .sheet(isPresented: $showingInspectorSheet) {
                // Inspector Details Sheet
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
                    .background(.thinMaterial)

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
            .onAppear {
                if fileURL != nil {
                    syncXMLPreview()
                }
            }
        }
    }

    private func syncXMLPreview() {
        xmlEditorText = editor.generateRawXML()
    }

    // Add Key Sheet

    private var addKeySheetView: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Add New Info.plist Key")
                .font(.headline)

            Picker("Suggested Key", selection: $newCustomKey) {
                Text("Custom...").tag("")
                ForEach(InfoPlistNSStrings.all) { meta in
                    Text("\(meta.name) (\(meta.key))").tag(meta.key)
                }
            }
            .pickerStyle(.menu)

            if newCustomKey.isEmpty {
                TextField("Custom Key Name", text: $newCustomKey)
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
                Spacer()
                Button("Add") {
                    if !newCustomKey.isEmpty {
                        editor.addMissingKey(newCustomKey)
                        syncXMLPreview()
                        showingAddKeySheet = false
                        newCustomKey = ""
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
            }
        }
        .padding()
        .frame(width: 400, height: 300)
    }
}

// MARK: - Subviews for Info.plist Rows & Inspector

struct InfoPlistRow: View {
    let key: String
    let value: Any
    let editor: InfoPlistEditor
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

                if let meta = InfoPlistNSStrings.all.first(where: { $0.key == key }) {
                    Text(meta.name)
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
            } else if let arrVal = value as? [Any] {
                Text("\(arrVal.count) items")
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
            } else if let dictVal = value as? [String: Any] {
                Text("Dictionary (\(dictVal.count) keys)")
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
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let meta = metadata {
                    VStack(alignment: .leading, spacing: 12) {
                        GroupBox(label: Label("Description", systemImage: "doc.text")) {
                            Text(meta.description)
                                .font(.body)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.top, 4)
                        }

                        GroupBox(label: Label("Recommended Wording", systemImage: "hand.thumbsup")) {
                            Text(meta.recommendedWording)
                                .font(.body)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.top, 4)
                        }

                        GroupBox(label: Label("Metadata Info", systemImage: "info.circle")) {
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text("Category:")
                                        .bold()
                                    Text(meta.category)
                                }
                                HStack {
                                    Text("Value Type:")
                                        .bold()
                                    Text(meta.valueType.rawValue)
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
                            set: { onSaveValue($0) }
                        ))
                        .toggleStyle(.checkbox)
                    } else if let arrVal = value as? [Any] {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(0..<arrVal.count, id: \.self) { idx in
                                HStack {
                                    TextField("Item \(idx + 1)", text: Binding(
                                        get: { String(describing: arrVal[idx]) },
                                        set: { newVal in
                                            var copy = arrVal
                                            copy[idx] = newVal
                                            onSaveValue(copy)
                                        }
                                    ))
                                    .textFieldStyle(.roundedBorder)

                                    Button {
                                        var copy = arrVal
                                        copy.remove(at: idx)
                                        onSaveValue(copy)
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
                                onSaveValue(copy)
                            } label: {
                                Label("Add Item", systemImage: "plus")
                            }
                            .buttonStyle(.bordered)
                        }
                    } else {
                        TextField("Value", text: Binding(
                            get: { String(describing: value) },
                            set: { onSaveValue($0) }
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
