import SwiftUI

public struct InfoPlistView: View {
    private let fileURL: URL?
    @State private var editor: InfoPlistEditor
    @State private var searchQuery = ""
    @State private var selectedCategory: String? = nil
    @State private var favorites: Set<String> = []
    @State private var selectedKey: String? = nil
    @State private var showXMLSplit = true
    @State private var xmlEditorText = ""
    @State private var showingAddKeyPopover = false
    @State private var newCustomKey = ""
    @State private var newCustomType: InfoPlistNSString.ValueType = .string

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
            HSplitView {
                // Left Side: Visual Editor
            VStack(spacing: 0) {
                // Toolbar Area
                HStack(spacing: 12) {
                    // Search
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
                    .padding(6)
                    .background(Color.white.opacity(0.06))
                    .cornerRadius(8)

                    Spacer()

                    // Undo/Redo
                    Button {
                        editor.undo()
                        syncXMLPreview()
                    } label: {
                        Image(systemName: "arrow.uturn.backward")
                    }
                    .buttonStyle(.plain)
                    .disabled(!editor.canUndo)
                    .help("Undo")

                    Button {
                        editor.redo()
                        syncXMLPreview()
                    } label: {
                        Image(systemName: "arrow.uturn.forward")
                    }
                    .buttonStyle(.plain)
                    .disabled(!editor.canRedo)
                    .help("Redo")

                    // Add Key Button
                    Button {
                        showingAddKeyPopover = true
                    } label: {
                        Label("Add Key", systemImage: "plus")
                    }
                    .buttonStyle(.borderedProminent)
                    .popover(isPresented: $showingAddKeyPopover) {
                        addKeyPopoverView
                    }

                    // Save Button
                    Button {
                        try? editor.save()
                    } label: {
                        Text("Save")
                    }
                    .buttonStyle(.bordered)
                    .disabled(!editor.isDirty)

                    // Toggle Split View
                    Button {
                        showXMLSplit.toggle()
                    } label: {
                        Image(systemName: "sidebar.trailing")
                            .foregroundStyle(showXMLSplit ? .blue : .primary)
                    }
                    .buttonStyle(.plain)
                    .help("Toggle Split XML Editor")
                }
                .padding()
                .background(.ultraThinMaterial)

                Divider()

                // Plist Key Value Table/List
                List {
                    // Quick-add Apple Privacy Keys Suggestions
                    Section("Common Apple Privacy & Security Keys") {
                        DisclosureGroup("Browse Common Keys") {
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
                                            .background(Color.blue.opacity(0.15))
                                            .cornerRadius(8)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                                .padding(.vertical, 4)
                            }
                        }
                    }

                    Section("Configured Properties") {
                        if filteredKeys.isEmpty {
                            ContentUnavailableView("No Keys Found", systemImage: "doc.text.magnifyingglass", description: Text("Click '+' or add a common key to begin."))
                                .padding()
                        } else {
                            ForEach(filteredKeys, id: \.self) { key in
                                InfoPlistRow(
                                    key: key,
                                    value: editor.entries[key] ?? "",
                                    editor: editor,
                                    isFavorite: favorites.contains(key),
                                    onSelect: { selectedKey = key },
                                    onToggleFavorite: {
                                        if favorites.contains(key) {
                                            favorites.remove(key)
                                        } else {
                                            favorites.insert(key)
                                        }
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
                            }
                        }
                    }
                }
                .listStyle(.inset)
            }
            .frame(minWidth: 400, idealWidth: 600)

            // Right Side: Live Raw XML Editor & Inspector Detail
            if showXMLSplit {
                HSplitView {
                    // Inspector/Detail View
                    VStack(spacing: 0) {
                        Text("Inspector")
                            .font(.headline)
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(.ultraThinMaterial)
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
                            ContentUnavailableView("Select a Key", systemImage: "info.circle", description: Text("Select any key to view description, documentation, and recommended wording."))
                                .padding()
                        }
                    }
                    .frame(minWidth: 250, idealWidth: 300)

                    // XML View
                    VStack(spacing: 0) {
                        Text("Raw XML Editor")
                            .font(.headline)
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(.ultraThinMaterial)
                        Divider()

                        TextEditor(text: $xmlEditorText)
                            .font(.system(.body, design: .monospaced))
                            .onChange(of: xmlEditorText) { _, newValue in
                                if (try? editor.updateFromXML(newValue)) != nil {
                                    // successfully parsed XML in real-time
                                }
                            }
                    }
                    .frame(minWidth: 250, idealWidth: 350)
                }
            }
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

    // MARK: - Add Key Popover

    private var addKeyPopoverView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Add New Info.plist Key")
                .font(.headline)

            Picker("Suggested Key", selection: $newCustomKey) {
                Text("Custom...").tag("")
                ForEach(InfoPlistNSStrings.all) { meta in
                    Text("\(meta.name) (\(meta.key))").tag(meta.key)
                }
            }

            if newCustomKey.isEmpty {
                TextField("Custom Key Name", text: $newCustomKey)
                    .textFieldStyle(.roundedBorder)

                Picker("Value Type", selection: $newCustomType) {
                    ForEach(InfoPlistNSString.ValueType.allCases, id: \.self) { type in
                        Text(type.rawValue).tag(type)
                    }
                }
            }

            HStack {
                Button("Cancel") {
                    showingAddKeyPopover = false
                }
                Spacer()
                Button("Add") {
                    if !newCustomKey.isEmpty {
                        editor.addMissingKey(newCustomKey)
                        syncXMLPreview()
                        showingAddKeyPopover = false
                        newCustomKey = ""
                    }
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .frame(width: 320)
    }
}

// MARK: - Row Subview

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
        let metadata = InfoPlistNSStrings.all.first(where: { $0.key == key })
        HStack(alignment: .top, spacing: 12) {
            Button(action: onToggleFavorite) {
                Image(systemName: isFavorite ? "star.fill" : "star")
                    .foregroundColor(isFavorite ? .yellow : .secondary)
            }
            .buttonStyle(.plain)
            .padding(.top, 4)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(metadata?.name ?? key)
                        .font(.body.bold())
                    Spacer()
                    if let category = metadata?.category {
                        Text(category)
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.blue.opacity(0.12))
                            .foregroundStyle(.blue)
                            .cornerRadius(4)
                    }
                }

                Text(key)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.secondary)

                valueControlView
                    .padding(.top, 4)
            }

            Spacer()

            Button(role: .destructive, action: onDelete) {
                Image(systemName: "trash")
                    .foregroundStyle(.red)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .onTapGesture {
            onSelect()
        }
    }

    @ViewBuilder
    private var valueControlView: some View {
        if let boolVal = value as? Bool {
            Toggle(isOn: Binding(
                get: { boolVal },
                set: { onValueChange($0) }
            )) {
                Text(boolVal ? "YES" : "NO")
                    .font(.caption2.bold())
            }
        } else if let arrayVal = value as? [String] {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(arrayVal.indices, id: \.self) { index in
                    HStack {
                        TextField("Item \(index)", text: Binding(
                            get: { arrayVal[index] },
                            set: { newVal in
                                var mutable = arrayVal
                                mutable[index] = newVal
                                onValueChange(mutable)
                            }
                        ))
                        .textFieldStyle(.roundedBorder)

                        Button {
                            var mutable = arrayVal
                            mutable.remove(at: index)
                            onValueChange(mutable)
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.plain)
                    }
                }
                Button {
                    var mutable = arrayVal
                    mutable.append("")
                    onValueChange(mutable)
                } label: {
                    Label("Add Item", systemImage: "plus")
                        .font(.caption)
                }
                .buttonStyle(.plain)
            }
        } else {
            let strVal = String(describing: value)
            TextField("Value", text: Binding(
                get: { strVal },
                set: { onValueChange($0) }
            ))
            .textFieldStyle(.roundedBorder)
        }
    }
}

// MARK: - Inspector Subview

struct InfoPlistInspectorPanel: View {
    let key: String
    let value: Any
    let metadata: InfoPlistNSString?
    let onSaveValue: (Any) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    if let symbol = metadata?.sfSymbol {
                        Image(systemName: symbol)
                            .font(.title)
                            .foregroundStyle(.blue)
                    }
                    Text(metadata?.name ?? key)
                        .font(.title3.bold())
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("KEY")
                        .font(.caption2.bold())
                        .foregroundStyle(.secondary)
                    Text(key)
                        .font(.system(.body, design: .monospaced))
                }

                if let desc = metadata?.description {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("DESCRIPTION")
                            .font(.caption2.bold())
                            .foregroundStyle(.secondary)
                        Text(desc)
                    }
                }

                if let wording = metadata?.recommendedWording {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("RECOMMENDED WORDING")
                            .font(.caption2.bold())
                            .foregroundStyle(.secondary)
                        Text(wording)
                            .font(.callout.italic())
                            .padding(8)
                            .background(Color.white.opacity(0.04))
                            .cornerRadius(8)
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("VALUE TYPE")
                        .font(.caption2.bold())
                        .foregroundStyle(.secondary)
                    Text(metadata?.valueType.rawValue ?? "String")
                }
            }
            .padding()
        }
    }
}
