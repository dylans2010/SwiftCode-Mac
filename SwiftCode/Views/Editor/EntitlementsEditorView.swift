import SwiftUI

public struct EntitlementsEditorView: View {
    @State private var manager: EntitlementsEditorManager
    @State private var entitlementsDict: [String: Any] = [:]
    @State private var searchQuery = ""
    @State private var selectedCategory: EntitlementCategory? = nil
    @State private var selectedKey: String? = nil
    @State private var xmlEditorText = ""
    @State private var showXMLSplit = true
    @State private var favorites: Set<String> = []
    @State private var showingAddPopover = false

    public init(fileURL: URL) {
        let m = EntitlementsEditorManager(fileURL: fileURL)
        _manager = State(initialValue: m)
        _entitlementsDict = State(initialValue: (try? m.readEntitlements()) ?? [:])
    }

    private var activeKeys: [String] {
        entitlementsDict.keys.sorted().filter { key in
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
        HSplitView {
            // Left Column: Main Entitlements Configurator & List
            VStack(spacing: 0) {
                // Header / Toolbar
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
                    .padding(6)
                    .background(Color.white.opacity(0.06))
                    .cornerRadius(8)

                    Spacer()

                    // Add Cap Button
                    Button {
                        showingAddPopover = true
                    } label: {
                        Label("Capability", systemImage: "plus")
                    }
                    .buttonStyle(.borderedProminent)
                    .popover(isPresented: $showingAddPopover) {
                        addCapabilityPopoverView
                    }

                    // Save Button
                    Button {
                        try? manager.writeEntitlements(entitlementsDict)
                    } label: {
                        Text("Save")
                    }
                    .buttonStyle(.bordered)

                    // Toggle Split XML Editor
                    Button {
                        showXMLSplit.toggle()
                    } label: {
                        Image(systemName: "sidebar.trailing")
                            .foregroundStyle(showXMLSplit ? .blue : .primary)
                    }
                    .buttonStyle(.plain)
                }
                .padding()
                .background(.ultraThinMaterial)

                Divider()

                // Validation Status Summary Banner
                validationBanner

                // Entitlements list
                List {
                    // Category Filters
                    Section("Categories") {
                        HStack {
                            Button("All") { selectedCategory = nil }
                                .buttonStyle(.bordered)
                                .tint(selectedCategory == nil ? .blue : nil)

                            ForEach(EntitlementCategory.allCases, id: \.self) { cat in
                                Button(cat.rawValue) { selectedCategory = cat }
                                    .buttonStyle(.bordered)
                                    .tint(selectedCategory == cat ? .blue : nil)
                            }
                        }
                        .padding(.vertical, 4)
                    }

                    Section("Active App Capabilities") {
                        if activeKeys.isEmpty {
                            ContentUnavailableView("No Active Capabilities", systemImage: "lock.shield", description: Text("Click '+' or browse capabilities below to enable them."))
                                .padding()
                        } else {
                            ForEach(activeKeys.filter { key in
                                if let cat = selectedCategory {
                                    let meta = EntitlementsCatalog.all.first(where: { $0.rawKey == key })
                                    return meta?.category == cat
                                }
                                return true
                            }, id: \.self) { key in
                                EntitlementRowView(
                                    key: key,
                                    value: entitlementsDict[key] ?? "",
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
                                        entitlementsDict.removeValue(forKey: key)
                                        if selectedKey == key { selectedKey = nil }
                                        syncXMLText()
                                    },
                                    onValueChange: { newVal in
                                        entitlementsDict[key] = newVal
                                        syncXMLText()
                                    }
                                )
                            }
                        }
                    }
                }
                .listStyle(.inset)
            }
            .frame(minWidth: 450, idealWidth: 650)

            // Right Column: Live XML Editor & Inspector
            if showXMLSplit {
                HSplitView {
                    // Inspector Panel
                    VStack(spacing: 0) {
                        Text("Inspector")
                            .font(.headline)
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(.ultraThinMaterial)
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
                            ContentUnavailableView("Select a Capability", systemImage: "info.circle", description: Text("Select any enabled capability to view technical documentation, platforms, and validation requirements."))
                                .padding()
                        }
                    }
                    .frame(minWidth: 250, idealWidth: 320)

                    // XML Code Editor
                    VStack(spacing: 0) {
                        Text("Raw Entitlements XML")
                            .font(.headline)
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(.ultraThinMaterial)
                        Divider()

                        TextEditor(text: $xmlEditorText)
                            .font(.system(.body, design: .monospaced))
                            .onChange(of: xmlEditorText) { _, newValue in
                                if let parsed = try? manager.parseRawXML(newValue) {
                                    self.entitlementsDict = parsed
                                }
                            }
                    }
                    .frame(minWidth: 250, idealWidth: 350)
                }
            }
        }
        .onAppear {
            syncXMLText()
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

    private var addCapabilityPopoverView: some View {
        let available = EntitlementsCatalog.all.filter { entitlementsDict[$0.rawKey] == nil }
        return VStack(alignment: .leading, spacing: 12) {
            Text("Add Capability Entitlement")
                .font(.headline)

            if available.isEmpty {
                Text("All capabilities in catalog are already configured.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
                        showingAddPopover = false
                    } label: {
                        HStack {
                            Image(systemName: meta.sfSymbol)
                                .foregroundStyle(.blue)
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
                .frame(height: 250)
            }

            Button("Close") {
                showingAddPopover = false
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding()
        .frame(width: 350, height: 360)
    }
}

// MARK: - Row View

struct EntitlementRowView: View {
    let key: String
    let value: Any
    let isFavorite: Bool
    let onSelect: () -> Void
    let onToggleFavorite: () -> Void
    let onDelete: () -> Void
    let onValueChange: (Any) -> Void

    var body: some View {
        let metadata = EntitlementsCatalog.all.first(where: { $0.rawKey == key })
        HStack(alignment: .top, spacing: 12) {
            Button(action: onToggleFavorite) {
                Image(systemName: isFavorite ? "star.fill" : "star")
                    .foregroundColor(isFavorite ? .yellow : .secondary)
            }
            .buttonStyle(.plain)
            .padding(.top, 4)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(metadata?.displayName ?? key)
                        .font(.body.bold())
                    Spacer()
                    if let category = metadata?.category {
                        Text(category.rawValue)
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

                valueEditorView
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
    private var valueEditorView: some View {
        if let boolVal = value as? Bool {
            Toggle(isOn: Binding(
                get: { boolVal },
                set: { onValueChange($0) }
            )) {
                Text(boolVal ? "Enabled" : "Disabled")
                    .font(.caption2.bold())
            }
        } else if let arrayVal = value as? [String] {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(arrayVal.indices, id: \.self) { index in
                    HStack {
                        TextField("Group / Access Group Identifier", text: Binding(
                            get: { arrayVal[index] },
                            set: { newVal in
                                var copy = arrayVal
                                copy[index] = newVal
                                onValueChange(copy)
                            }
                        ))
                        .textFieldStyle(.roundedBorder)

                        Button {
                            var copy = arrayVal
                            copy.remove(at: index)
                            onValueChange(copy)
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.plain)
                    }
                }
                Button {
                    var copy = arrayVal
                    copy.append("")
                    onValueChange(copy)
                } label: {
                    Label("Add Identifier", systemImage: "plus")
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

// MARK: - Inspector Panel

struct EntitlementInspectorPanel: View {
    let key: String
    let value: Any
    let metadata: EntitlementMetadata?
    let onUpdateValue: (Any) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    if let symbol = metadata?.sfSymbol {
                        Image(systemName: symbol)
                            .font(.title)
                            .foregroundStyle(.blue)
                    }
                    Text(metadata?.displayName ?? key)
                        .font(.title3.bold())
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("RAW KEY")
                        .font(.caption2.bold())
                        .foregroundStyle(.secondary)
                    Text(key)
                        .font(.system(.body, design: .monospaced))
                }

                if let desc = metadata?.entitlementDescription {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("DESCRIPTION")
                            .font(.caption2.bold())
                            .foregroundStyle(.secondary)
                        Text(desc)
                    }
                }

                if let usage = metadata?.recommendedUsage {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("RECOMMENDED USAGE")
                            .font(.caption2.bold())
                            .foregroundStyle(.secondary)
                        Text(usage)
                            .font(.callout.italic())
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("SUPPORTED PLATFORMS")
                        .font(.caption2.bold())
                        .foregroundStyle(.secondary)
                    if let platforms = metadata?.supportedPlatforms {
                        HStack {
                            ForEach(platforms, id: \.self) { plat in
                                Text(plat.rawValue)
                                    .font(.caption2)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.blue.opacity(0.1))
                                    .cornerRadius(4)
                            }
                        }
                    } else {
                        Text("macOS, iOS, watchOS, tvOS")
                    }
                }
            }
            .padding()
        }
    }
}
