import SwiftUI

/// Full-pane editor for `Localizable.xcstrings` — the user never sees
/// the raw JSON. One organized page, no sidebar, no tab bar, no
/// toolbar inside the view (the workspace hides its chrome while
/// this view is on screen, like the Info.plist editor):
/// header, AI assistant, filters, then the strings themselves.
///
/// Editing here writes this file directly (it *is* the file's
/// editor). The "Localize App" AI flow is stricter: it may only
/// change files through the localization tools — see
/// `LocalizingAppService` — while the model only supplies
/// translation text and never touches a file.
public struct LocalizingAppNewView: View {
    public let fileURL: URL

    @State private var root: [String: Any]?
    @State private var originalData: Data?
    @State private var loadError: String?
    @State private var saveError: String?

    @State private var searchQuery = ""
    @State private var displayLanguage = "en"
    @State private var stateFilter = "All"
    @State private var selectedLanguages: Set<String> = []
    @State private var customLanguage = ""
    @State private var isLocalizing = false
    @State private var localizeProgress = ""
    @State private var localizeResult: String?

    @State private var showingAddString = false
    @State private var newKey = ""
    @State private var newSourceValue = ""

    private let stateFilters = ["All", "translated", "new", "needs_review", "variations"]
    private let commonLanguages = [
        "es", "fr", "de", "it", "pt", "pt-BR", "ja", "ko", "zh-Hans", "zh-Hant",
        "nl", "sv", "da", "fi", "no", "pl", "ru", "uk", "ar", "he", "hi", "th", "vi", "id", "ms", "tr",
    ]

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    // MARK: - Derived catalog state

    private var sourceLanguage: String {
        root?["sourceLanguage"] as? String ?? "en"
    }

    private var stringsDict: [String: Any] {
        root?["strings"] as? [String: Any] ?? [:]
    }

    private var allLanguages: [String] {
        var set = Set<String>()
        set.insert(sourceLanguage)
        for entry in stringsDict.values {
            let localizations = (entry as? [String: Any])?["localizations"] as? [String: Any] ?? [:]
            set.formUnion(localizations.keys)
        }
        return set.sorted()
    }

    private var isDirty: Bool {
        guard let root, let originalData else { return false }
        let current = try? JSONSerialization.data(withJSONObject: root, options: [.sortedKeys])
        return current != originalData
    }

    private var filteredKeys: [String] {
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return stringsDict.keys.sorted().filter { key in
            if !query.isEmpty {
                let entry = stringsDict[key] as? [String: Any] ?? [:]
                let comment = (entry["comment"] as? String ?? "").lowercased()
                let value = localizationValue(for: key, language: displayLanguage).lowercased()
                guard key.lowercased().contains(query) || comment.contains(query) || value.contains(query) else {
                    return false
                }
            }
            if stateFilter != "All" {
                return localizationState(for: key, language: displayLanguage) == stateFilter
            }
            return true
        }
    }

    private func localizationValue(for key: String, language: String) -> String {
        let entry = stringsDict[key] as? [String: Any] ?? [:]
        let localizations = entry["localizations"] as? [String: Any] ?? [:]
        let unit = (localizations[language] as? [String: Any])?["stringUnit"] as? [String: Any]
        return unit?["value"] as? String ?? ""
    }

    private func localizationState(for key: String, language: String) -> String {
        let entry = stringsDict[key] as? [String: Any] ?? [:]
        let localizations = entry["localizations"] as? [String: Any] ?? [:]
        guard let loc = localizations[language] as? [String: Any] else { return "new" }
        if let unit = loc["stringUnit"] as? [String: Any] {
            return unit["state"] as? String ?? "new"
        }
        return "variations"
    }

    private func counts() -> (total: Int, translated: Int, untranslated: Int) {
        let total = stringsDict.count
        var translated = 0
        for key in stringsDict.keys {
            if localizationState(for: key, language: displayLanguage) == "translated" {
                translated += 1
            }
        }
        return (total, translated, total - translated)
    }

    // MARK: - Body

    public var body: some View {
        Group {
            if let loadError {
                ContentUnavailableView {
                    Label("Couldn't Read Localizable.xcstrings", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(loadError)
                } actions: {
                    Button("Reload") { load() }
                }
            } else if root != nil {
                editorBody
            } else {
                ProgressView("Loading strings…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onAppear {
            load()
            NotificationCenter.default.post(name: .specialEditorActive, object: nil, userInfo: ["active": true])
        }
        .onDisappear {
            NotificationCenter.default.post(name: .specialEditorActive, object: nil, userInfo: ["active": false])
        }
    }

    private var editorBody: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    aiAssistantSection
                    Divider()
                    filtersSection
                    stringsSection
                }
                .padding(20)
            }
        }
    }

    // MARK: - Header (in-view, not a toolbar)

    private var header: some View {
        let count = counts()
        return HStack(spacing: 12) {
            Image(systemName: "character.bubble")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Color.accentColor)
            VStack(alignment: .leading, spacing: 2) {
                Text("Localizable.xcstrings")
                    .font(.system(size: 15, weight: .bold))
                Text("\(count.total) strings · \(count.translated) translated in \(displayLanguage) · \(count.untranslated) untranslated · Source: \(sourceLanguage)")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if isDirty {
                Text("Unsaved changes")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            Button("Revert") { load() }
                .disabled(!isDirty)
            Button("Save") { save() }
                .buttonStyle(.borderedProminent)
                .disabled(!isDirty)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(VisualEffectView(material: .headerView, blendingMode: .withinWindow))
    }

    // MARK: - AI assistant

    private var aiAssistantSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("AI Assistant — Localize App", systemImage: "sparkles")
                .font(.system(size: 14, weight: .bold))
            Text("One click fully localizes the app into the languages you select: it discovers the app's strings, builds the catalog, translates every string with the selected model, and writes the translations back. File changes go only through the localization tools (localize_app, strings_localization); the model only supplies translation text and never touches a file.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Text("Localize into")
                .font(.system(size: 12, weight: .semibold))
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 72))], spacing: 8) {
                ForEach(allLanguages.filter { $0 != sourceLanguage } + commonLanguages.filter { !allLanguages.contains($0) }, id: \.self) { language in
                    Toggle(language, isOn: Binding(
                        get: { selectedLanguages.contains(language) },
                        set: { if $0 { selectedLanguages.insert(language) } else { selectedLanguages.remove(language) } }
                    ))
                    .toggleStyle(.button)
                    .controlSize(.small)
                }
            }
            HStack(spacing: 8) {
                TextField("Custom language code (e.g. pt-BR)", text: $customLanguage)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 260)
                Button("Add Language") {
                    let code = customLanguage.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !code.isEmpty else { return }
                    selectedLanguages.insert(code)
                    customLanguage = ""
                }
                .disabled(customLanguage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Spacer()
            }

            HStack(spacing: 12) {
                Button("Localize App") {
                    Task { await runLocalizeApp() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(selectedLanguages.isEmpty || isLocalizing)
                if isLocalizing {
                    ProgressView()
                        .controlSize(.small)
                    Text(localizeProgress)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            if let localizeResult {
                Text(localizeResult)
                    .font(.callout)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.accentColor.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            if let saveError {
                Text(saveError)
                    .font(.callout)
                    .foregroundStyle(.red)
            }
        }
    }

    // MARK: - Filters + strings

    private var filtersSection: some View {
        HStack(spacing: 12) {
            TextField("Search strings…", text: $searchQuery)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 320)
            Picker("Language", selection: $displayLanguage) {
                ForEach(allLanguages, id: \.self) { language in
                    Text(language).tag(language)
                }
            }
            .frame(maxWidth: 160)
            Picker("State", selection: $stateFilter) {
                ForEach(stateFilters, id: \.self) { state in
                    Text(state).tag(state)
                }
            }
            .frame(maxWidth: 160)
            Spacer()
            Button("Add String") { showingAddString.toggle() }
        }
    }

    private var stringsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            if showingAddString {
                HStack(spacing: 8) {
                    TextField("New key", text: $newKey)
                        .textFieldStyle(.roundedBorder)
                    TextField("Source text (\(sourceLanguage))", text: $newSourceValue)
                        .textFieldStyle(.roundedBorder)
                    Button("Add") { addString() }
                        .disabled(newKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || newSourceValue.isEmpty)
                    Button("Cancel") {
                        showingAddString = false
                        newKey = ""
                        newSourceValue = ""
                    }
                }
            }
            if filteredKeys.isEmpty {
                ContentUnavailableView {
                    Label("No Strings Match", systemImage: "magnifyingglass")
                } description: {
                    Text("Try a different search, language, or state filter — or add a new string.")
                }
                .frame(maxWidth: .infinity)
            }
            ForEach(filteredKeys, id: \.self) { key in
                stringRow(for: key)
            }
        }
    }

    private func stringRow(for key: String) -> some View {
        let state = localizationState(for: key, language: displayLanguage)
        let entry = stringsDict[key] as? [String: Any] ?? [:]
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(key)
                    .font(.system(size: 13, weight: .semibold))
                    .monospaced()
                    .lineLimit(1)
                Spacer()
                stateBadge(state)
            }
            if let comment = entry["comment"] as? String, !comment.isEmpty {
                Text(comment)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            if state == "variations" {
                Text("This string uses variations (plurals/device variants) — edit it in Xcode's catalog editor; values are preserved on save.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            } else {
                TextField("Value (\(displayLanguage))", text: Binding(
                    get: { localizationValue(for: key, language: displayLanguage) },
                    set: { setValue($0, for: key, language: displayLanguage) }
                ))
                .textFieldStyle(.roundedBorder)
            }
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func stateBadge(_ state: String) -> some View {
        let color: Color = switch state {
        case "translated": .green
        case "new": .orange
        case "needs_review": .yellow
        default: .secondary
        }
        return Text(state)
            .font(.system(size: 10, weight: .semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.18))
            .foregroundStyle(color == .yellow ? .primary : color)
            .clipShape(Capsule())
    }

    // MARK: - Editing the catalog document

    private func setValue(_ value: String, for key: String, language: String) {
        guard var strings = root?["strings"] as? [String: Any],
              var entry = strings[key] as? [String: Any],
              var localizations = entry["localizations"] as? [String: Any] else { return }
        var loc = (localizations[language] as? [String: Any]) ?? [:]
        let newState = value.isEmpty ? "new" : "translated"
        loc["stringUnit"] = ["state": newState, "value": value]
        localizations[language] = loc
        entry["localizations"] = localizations
        strings[key] = entry
        root?["strings"] = strings
    }

    private func addString() {
        let key = newKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty, !newSourceValue.isEmpty else { return }
        var strings = root?["strings"] as? [String: Any] ?? [:]
        guard strings[key] == nil else {
            saveError = "A string with key '\(key)' already exists."
            return
        }
        var localizations: [String: Any] = [
            sourceLanguage: ["stringUnit": ["state": "translated", "value": newSourceValue]],
        ]
        for language in allLanguages where language != sourceLanguage {
            localizations[language] = ["stringUnit": ["state": "new", "value": ""]]
        }
        strings[key] = ["localizations": localizations]
        root?["strings"] = strings
        saveError = nil
        showingAddString = false
        newKey = ""
        newSourceValue = ""
    }

    // MARK: - AI run

    private func runLocalizeApp() async {
        let languages = Array(selectedLanguages).sorted()
        guard !languages.isEmpty else { return }
        isLocalizing = true
        localizeResult = nil
        localizeProgress = "Starting localization…"
        defer { isLocalizing = false }
        let workspaceRoot = ProjectSessionStore.shared.activeProject?.directoryURL
            ?? fileURL.deletingLastPathComponent()
        do {
            let summary = try await LocalizingAppService.localizeApp(
                catalogURL: fileURL,
                workspaceRoot: workspaceRoot,
                languages: languages,
                sourceLanguage: sourceLanguage
            ) { progress in
                localizeProgress = progress.stage
            }
            localizeResult = summary
            load()
        } catch {
            localizeResult = "Localization failed: \(error.localizedDescription). Nothing was faked — strings left as \"new\" are still untranslated."
        }
        localizeProgress = ""
    }

    // MARK: - Load / save

    private func load() {
        loadError = nil
        saveError = nil
        do {
            let data = try Data(contentsOf: fileURL)
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw NSError(domain: "LocalizingAppNewView", code: 400, userInfo: [NSLocalizedDescriptionKey: "Localizable.xcstrings is not a JSON object."])
            }
            root = json
            originalData = try JSONSerialization.data(withJSONObject: json, options: [.sortedKeys])
            if !allLanguages.contains(displayLanguage) {
                displayLanguage = sourceLanguage
            }
        } catch {
            loadError = error.localizedDescription
        }
    }

    private func save() {
        guard let root else { return }
        do {
            let data = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: fileURL, options: [.atomic])
            originalData = try JSONSerialization.data(withJSONObject: root, options: [.sortedKeys])
            saveError = nil
        } catch {
            saveError = error.localizedDescription
        }
    }
}
