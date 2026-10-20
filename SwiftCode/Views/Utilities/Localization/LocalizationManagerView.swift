import SwiftUI
import AppKit

public struct LocalizationManagerView: View {
    @State private var core = LocalizationCore.shared
    @State private var showLanguageSettings = false
    @State private var showKeyCreationSheet = false
    @State private var newKeyName = ""
    @State private var newKeyComment = ""
    @State private var selectedLanguageCodeToAdd = "it"

    // Validation alerts
    @State private var activeIssues: [LocalizationValidationIssue] = []
    @State private var isShowingValidationHUD = false

    // AI Translation
    @State private var isAIProcessing = false
    @State private var aiTranslationResult = ""
    @State private var parsedAITranslations: [String: String] = [:]
    @State private var aiDidApply = false

    // Sheet alerts
    @State private var alertTitle = ""
    @State private var alertMessage = ""
    @State private var showingAlert = false

    public init() {}

    private var filteredKeys: [LocalizedKey] {
        var list = core.keys
        if core.filterMissingOnly {
            list = list.filter { record in
                core.activeLanguages.contains { lang in
                    (record.translations[lang] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                }
            }
        }
        if !core.searchEditorQuery.isEmpty {
            let q = core.searchEditorQuery.lowercased()
            list = list.filter { record in
                record.key.lowercased().contains(q) ||
                (record.comment ?? "").lowercased().contains(q) ||
                record.translations.values.contains { $0.lowercased().contains(q) }
            }
        }
        return list
    }

    private var missingKeysCount: Int {
        core.keys.filter { record in
            core.activeLanguages.contains { lang in
                (record.translations[lang] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
        }.count
    }

    public var body: some View {
        HSplitView {
            // MARK: - Panel 1: Catalogs & Languages Sidebar
            sidebarPanel
                .frame(minWidth: 230, idealWidth: 250, maxWidth: 300)

            // MARK: - Panel 2: Keys Directory & Search
            keysBrowserPanel
                .frame(minWidth: 340, idealWidth: 380, maxWidth: 480)

            // MARK: - Panel 3: Translation Editor & AI Co-Pilot
            detailEditorPanel
                .frame(minWidth: 460, idealWidth: 570, maxWidth: .infinity)
        }
        .clipped()
        .navigationTitle("Localization Manager")
        .navigationSubtitle(core.selectedFile?.name ?? "String Catalogs")
        .onAppear {
            core.scanProjectFiles()
            ensureSelection()
        }
        .onChange(of: core.keys.count) { _, _ in
            ensureSelection()
        }
        .sheet(isPresented: $showLanguageSettings) {
            languageManagementSheet
        }
        .sheet(isPresented: $showKeyCreationSheet) {
            keyCreationSheet
        }
        .sheet(isPresented: $isShowingValidationHUD) {
            validationResultsSheet
        }
        .alert(alertTitle, isPresented: $showingAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(alertMessage)
        }
    }

    private func ensureSelection() {
        if core.selectedKey == nil, let first = filteredKeys.first {
            core.selectedKey = first
        }
    }

    // MARK: - Sidebar Panel

    private var sidebarPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Catalog Files Section
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label("STRING CATALOGS", systemImage: "text.book.closed.fill")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        core.scanProjectFiles()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Rescan project for string catalogs")
                }
                .padding(.horizontal, 14)
                .padding(.top, 14)

                List(core.availableFiles, id: \.path) { file in
                    Button {
                        core.selectedFile = file
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: file.type == "xcstrings" ? "doc.text.fill" : "doc.plaintext.fill")
                                .font(.system(size: 14))
                                .foregroundColor(file.type == "xcstrings" ? .orange : .blue)

                            VStack(alignment: .leading, spacing: 1) {
                                Text(file.name)
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(core.selectedFile?.path == file.path ? .accentColor : .primary)
                                    .lineLimit(1)
                                Text(file.type.uppercased())
                                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            if core.selectedFile?.path == file.path {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(Color.accentColor)
                            }
                        }
                        .padding(.vertical, 4)
                        .padding(.horizontal, 8)
                        .background(core.selectedFile?.path == file.path ? Color.accentColor.opacity(0.12) : Color.clear, in: RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)
                }
                .listStyle(.plain)
                .frame(maxHeight: 180)
            }

            Divider()

            // Active Languages Section
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label("ACTIVE LOCALES", systemImage: "globe")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        showLanguageSettings.toggle()
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 13))
                            .foregroundColor(.blue)
                    }
                    .buttonStyle(.plain)
                    .help("Add language locale")
                }
                .padding(.horizontal, 14)
                .padding(.top, 12)

                ScrollView {
                    VStack(spacing: 4) {
                        ForEach(core.languages, id: \.self) { lang in
                            HStack(spacing: 8) {
                                Toggle("", isOn: Binding(
                                    get: { core.activeLanguages.contains(lang) },
                                    set: { _ in core.toggleLanguageActive(lang) }
                                ))
                                .toggleStyle(.checkbox)
                                .labelsHidden()

                                Text(lang.uppercased())
                                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 2)
                                    .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 4))

                                Text(displayName(for: lang))
                                    .font(.system(size: 12))
                                    .lineLimit(1)

                                Spacer()

                                if lang == core.defaultLanguage {
                                    Text("DEFAULT")
                                        .font(.system(size: 8, weight: .bold))
                                        .padding(.horizontal, 4)
                                        .padding(.vertical, 2)
                                        .background(Color.green.opacity(0.15), in: RoundedRectangle(cornerRadius: 3))
                                        .foregroundStyle(.green)
                                } else {
                                    Button {
                                        core.removeLanguage(lang)
                                    } label: {
                                        Image(systemName: "trash")
                                            .font(.caption2)
                                            .foregroundColor(.red.opacity(0.7))
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 4)
                        }
                    }
                }
            }

            Spacer()

            Divider()

            // Footer Metrics
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(core.keys.count) Keys in Catalog")
                        .font(.system(size: 11, weight: .semibold))
                    Text("\(core.activeLanguages.count) of \(core.languages.count) Locales Active")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if missingKeysCount > 0 {
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(.orange)
                        Text("\(missingKeysCount) untranslated")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.orange)
                    }
                }
            }
            .padding(12)
            .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
        }
        .background(Color(NSColor.windowBackgroundColor))
    }

    // MARK: - Keys Browser Panel

    private var keysBrowserPanel: some View {
        VStack(spacing: 0) {
            // Browser Toolbar
            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    // Search bar
                    HStack(spacing: 6) {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.secondary)
                            .font(.system(size: 11))
                        TextField("Search keys, comments, values...", text: $core.searchEditorQuery)
                            .textFieldStyle(.plain)
                            .font(.system(size: 12))
                        if !core.searchEditorQuery.isEmpty {
                            Button {
                                core.searchEditorQuery = ""
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))

                    // Add key button
                    Button {
                        showKeyCreationSheet = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 12, weight: .bold))
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .help("Add new localization key")
                }

                // Filter & Actions row
                HStack(spacing: 8) {
                    Toggle(isOn: $core.filterMissingOnly) {
                        HStack(spacing: 4) {
                            Text("Missing Only")
                            if missingKeysCount > 0 {
                                Text("\(missingKeysCount)")
                                    .font(.system(size: 9, weight: .bold))
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 1)
                                    .background(core.filterMissingOnly ? Color.white.opacity(0.3) : Color.orange.opacity(0.2), in: Capsule())
                            }
                        }
                        .font(.system(size: 11))
                    }
                    .toggleStyle(.button)
                    .controlSize(.small)

                    Spacer()

                    Button(action: runValidationChecks) {
                        Label("Validate", systemImage: "checkmark.shield")
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Menu {
                        Button("Export CSV Report...") { exportCSVReport() }
                        Button("Import from CSV...") { importCSVFile() }
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 11))
                    }
                    .menuStyle(.button)
                    .controlSize(.small)
                }
            }
            .padding(10)
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            // Keys List
            if core.isScanning && filteredKeys.isEmpty {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Scanning project for string catalogs...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxHeight: .infinity)
            } else if filteredKeys.isEmpty {
                ContentUnavailableView(
                    core.filterMissingOnly ? "No Missing Keys" : "No Keys Found",
                    systemImage: "text.badge.plus",
                    description: Text(core.filterMissingOnly ? "All keys have complete translations across active languages." : "Create translation keys or adjust search criteria.")
                )
                .frame(maxHeight: .infinity)
            } else {
                List(filteredKeys, selection: $core.selectedKey) { record in
                    let isSelected = core.selectedKey?.key == record.key
                    let missingLangs = core.activeLanguages.filter { (record.translations[$0] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                    let isComplete = missingLangs.isEmpty

                    Button {
                        core.selectedKey = record
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(alignment: .center, spacing: 6) {
                                Text(record.key)
                                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                                    .foregroundColor(isSelected ? .accentColor : .primary)
                                    .lineLimit(1)

                                Spacer()

                                if isComplete {
                                    HStack(spacing: 2) {
                                        Image(systemName: "checkmark.circle.fill")
                                            .font(.system(size: 9))
                                            .foregroundStyle(.green)
                                        Text("Translated")
                                            .font(.system(size: 9, weight: .semibold))
                                            .foregroundStyle(.green)
                                    }
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 2)
                                    .background(Color.green.opacity(0.12), in: Capsule())
                                } else {
                                    HStack(spacing: 2) {
                                        Image(systemName: "exclamationmark.circle.fill")
                                            .font(.system(size: 9))
                                            .foregroundStyle(.orange)
                                        Text("\(missingLangs.count) missing")
                                            .font(.system(size: 9, weight: .semibold))
                                            .foregroundStyle(.orange)
                                    }
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 2)
                                    .background(Color.orange.opacity(0.12), in: Capsule())
                                }
                            }

                            // Default translation preview
                            let defaultVal = record.translations[core.defaultLanguage] ?? ""
                            if !defaultVal.isEmpty {
                                Text(defaultVal)
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                            }

                            // Developer comment preview if present
                            if let comment = record.comment, !comment.isEmpty {
                                Text("/* \(comment) */")
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundColor(.secondary.opacity(0.7))
                                    .lineLimit(1)
                            }
                        }
                        .padding(.vertical, 6)
                        .padding(.horizontal, 8)
                        .background(
                            isSelected ? Color.accentColor.opacity(0.12) : Color.clear,
                            in: RoundedRectangle(cornerRadius: 6)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(isSelected ? Color.accentColor.opacity(0.3) : Color.clear, lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                    .tag(record)
                }
                .listStyle(.plain)
            }
        }
        .background(Color(NSColor.controlBackgroundColor).opacity(0.4))
    }

    // MARK: - Detail Editor Panel

    private var detailEditorPanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if let keyRecord = core.selectedKey {
                    // Key Header
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .center) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("KEY IDENTIFIER")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(.secondary)
                                Text(keyRecord.key)
                                    .font(.system(size: 16, weight: .bold, design: .monospaced))
                                    .textSelection(.enabled)
                            }

                            Spacer()

                            Button {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(keyRecord.key, forType: .string)
                            } label: {
                                Label("Copy Key", systemImage: "doc.on.doc")
                                    .font(.system(size: 11))
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)

                            Button(role: .destructive) {
                                core.deleteKey(keyRecord.key)
                                ensureSelection()
                            } label: {
                                Image(systemName: "trash")
                                    .font(.system(size: 12))
                                    .foregroundColor(.red)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .help("Delete key")
                        }

                        // Developer Comment
                        VStack(alignment: .leading, spacing: 4) {
                            Text("DEVELOPER COMMENT")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(.secondary)

                            TextField("Describe context or usage for translators...", text: Binding(
                                get: { keyRecord.comment ?? "" },
                                set: { newComment in
                                    if let idx = core.keys.firstIndex(where: { $0.key == keyRecord.key }) {
                                        core.keys[idx].comment = newComment.isEmpty ? nil : newComment
                                        core.selectedKey = core.keys[idx]
                                        core.saveFileContents()
                                    }
                                }
                            ))
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 12))
                        }
                    }
                    .padding(14)
                    .background(Color(NSColor.windowBackgroundColor), in: RoundedRectangle(cornerRadius: 8))

                    // Translations per language
                    VStack(alignment: .leading, spacing: 12) {
                        Text("TRANSLATIONS")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.secondary)

                        ForEach(Array(core.activeLanguages.sorted()), id: \.self) { lang in
                            let val = keyRecord.translations[lang] ?? ""
                            let isDefault = lang == core.defaultLanguage
                            let isMissing = val.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text(lang.uppercased())
                                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(isDefault ? Color.green.opacity(0.15) : Color.blue.opacity(0.12), in: RoundedRectangle(cornerRadius: 4))
                                        .foregroundColor(isDefault ? .green : .blue)

                                    Text(displayName(for: lang))
                                        .font(.system(size: 12, weight: .semibold))

                                    if isDefault {
                                        Text("(Source Language)")
                                            .font(.system(size: 10))
                                            .foregroundStyle(.secondary)
                                    }

                                    Spacer()

                                    Text("\(val.count) chars")
                                        .font(.system(size: 10))
                                        .foregroundStyle(.secondary)

                                    Button {
                                        NSPasteboard.general.clearContents()
                                        NSPasteboard.general.setString(val, forType: .string)
                                    } label: {
                                        Image(systemName: "doc.on.doc")
                                            .font(.system(size: 10))
                                    }
                                    .buttonStyle(.plain)
                                    .help("Copy translation")
                                }

                                TextField("Enter \(displayName(for: lang)) translation...", text: Binding(
                                    get: { keyRecord.translations[lang] ?? "" },
                                    set: { newVal in
                                        core.updateTranslation(key: keyRecord.key, lang: lang, value: newVal)
                                        if let updated = core.keys.first(where: { $0.key == keyRecord.key }) {
                                            core.selectedKey = updated
                                        }
                                    }
                                ), axis: .vertical)
                                .lineLimit(2...5)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(size: 13))
                            }
                            .padding(12)
                            .background(
                                isMissing ? Color.orange.opacity(0.04) : Color(NSColor.windowBackgroundColor),
                                in: RoundedRectangle(cornerRadius: 8)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(isMissing ? Color.orange.opacity(0.25) : Color.secondary.opacity(0.12), lineWidth: 1)
                            )
                        }
                    }

                    // AI Translator Co-Pilot Card
                    GroupBox {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Label("AI Translator Co-Pilot", systemImage: "sparkles")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundStyle(LinearGradient(colors: [.purple, .blue], startPoint: .leading, endPoint: .trailing))

                                Spacer()

                                if !parsedAITranslations.isEmpty && !aiDidApply {
                                    Button("Apply All to Keys") {
                                        applyAITranslations(to: keyRecord)
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .controlSize(.small)
                                    .tint(.purple)
                                } else if aiDidApply {
                                    Label("Applied!", systemImage: "checkmark")
                                        .font(.system(size: 11, weight: .bold))
                                        .foregroundStyle(.green)
                                }
                            }

                            Text("Automatically generates context-aware translations for missing active languages from your default string.")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)

                            Button {
                                runAITranslation(for: keyRecord)
                            } label: {
                                HStack {
                                    if isAIProcessing {
                                        ProgressView()
                                            .scaleEffect(0.6)
                                            .padding(.trailing, 4)
                                        Text("Generating Translations with AI...")
                                    } else {
                                        Image(systemName: "sparkles")
                                        Text("Translate with AI")
                                    }
                                }
                                .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                            .disabled(isAIProcessing || (keyRecord.translations[core.defaultLanguage] ?? "").isEmpty)

                            if !aiTranslationResult.isEmpty {
                                ScrollView {
                                    Text(aiTranslationResult)
                                        .font(.system(size: 11, design: .monospaced))
                                        .textSelection(.enabled)
                                        .padding(8)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .background(Color.black.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
                                }
                                .frame(maxHeight: 140)
                            }
                        }
                        .padding(8)
                    }
                    .groupBoxStyle(ModernGroupBoxStyle())

                    // Quality & Format Specifiers Notice
                    let formatSpecifiers = extractFormatSpecifiers(from: keyRecord.translations[core.defaultLanguage] ?? "")
                    if !formatSpecifiers.isEmpty {
                        HStack(spacing: 8) {
                            Image(systemName: "info.circle.fill")
                                .foregroundStyle(.blue)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Format Specifiers Detected: \(formatSpecifiers.joined(separator: ", "))")
                                    .font(.system(size: 11, weight: .semibold))
                                Text("Ensure all translated strings retain identical format variables (%@, %d, etc.) in correct positional order.")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(10)
                        .background(Color.blue.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
                    }

                } else {
                    ContentUnavailableView(
                        "No Key Selected",
                        systemImage: "character.bubble",
                        description: Text("Select a key from the directory on the left to edit its translations and launch AI actions.")
                    )
                    .padding(.top, 60)
                }
            }
            .padding(16)
        }
        .background(Color(NSColor.windowBackgroundColor).opacity(0.5))
    }

    // MARK: - Sheets

    private var languageManagementSheet: some View {
        VStack(spacing: 16) {
            Text("Add Language Locale")
                .font(.headline)

            Form {
                TextField("Language Code (e.g. de, fr, ja, it, es, pt, ko)", text: $selectedLanguageCodeToAdd)
                    .textFieldStyle(.roundedBorder)

                let previewName = displayName(for: selectedLanguageCodeToAdd.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
                if !selectedLanguageCodeToAdd.isEmpty {
                    Text("Locale Display Name: \(previewName)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            HStack {
                Button("Close") { showLanguageSettings = false }
                Spacer()
                Button("Add Language") {
                    core.addLanguage(selectedLanguageCodeToAdd)
                    showLanguageSettings = false
                }
                .buttonStyle(.borderedProminent)
                .disabled(selectedLanguageCodeToAdd.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding()
        .frame(width: 340)
    }

    private var keyCreationSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Add Localization Key")
                .font(.headline)

            Form {
                TextField("Key Identifier (e.g. welcome_message, title_label)", text: $newKeyName)
                    .textFieldStyle(.roundedBorder)
                TextField("Developer Comment / Context (optional)", text: $newKeyComment)
                    .textFieldStyle(.roundedBorder)
            }

            HStack {
                Button("Cancel") { showKeyCreationSheet = false }
                Spacer()
                Button("Create Key") {
                    core.addKey(newKeyName, comment: newKeyComment)
                    if let newRecord = core.keys.first(where: { $0.key == newKeyName.trimmingCharacters(in: .whitespacesAndNewlines) }) {
                        core.selectedKey = newRecord
                    }
                    newKeyName = ""
                    newKeyComment = ""
                    showKeyCreationSheet = false
                }
                .buttonStyle(.borderedProminent)
                .disabled(newKeyName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding()
        .frame(width: 380)
    }

    private var validationResultsSheet: some View {
        VStack(spacing: 16) {
            HStack {
                Label("Localization Validation Results", systemImage: "checkmark.shield.fill")
                    .font(.headline)
                Spacer()
                Button("Dismiss") { isShowingValidationHUD = false }
                    .buttonStyle(.bordered)
            }
            .padding(.horizontal)
            .padding(.top)

            Divider()

            if activeIssues.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 44))
                        .foregroundColor(.green)
                    Text("Zero translation issues found!")
                        .font(.headline)
                    Text("All keys contain intact format specifiers and valid translation segments across active languages.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }
                .frame(maxHeight: .infinity)
            } else {
                List(activeIssues) { issue in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: issue.severity == "ERROR" ? "exclamationmark.octagon.fill" : "exclamationmark.triangle.fill")
                            .foregroundColor(issue.severity == "ERROR" ? .red : .orange)

                        VStack(alignment: .leading, spacing: 4) {
                            Text(issue.key)
                                .font(.system(.subheadline, design: .monospaced))
                                .bold()
                            Text(issue.message)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .frame(width: 500, height: 400)
    }

    // MARK: - Helpers

    private func displayName(for languageCode: String) -> String {
        Locale.current.localizedString(forLanguageCode: languageCode)?.capitalized ?? languageCode.uppercased()
    }

    private func extractFormatSpecifiers(from text: String) -> [String] {
        let pattern = #"%(\d+\$)?[@dfiouxXeEgGcsq]"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
        return matches.compactMap { match in
            Range(match.range, in: text).map { String(text[$0]) }
        }
    }

    private func runValidationChecks() {
        activeIssues = core.validateTranslations()
        isShowingValidationHUD = true
    }

    private func exportCSVReport() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.utf8PlainText]
        panel.nameFieldStringValue = "Translations.csv"

        if panel.runModal() == .OK, let url = panel.url {
            do {
                try core.exportCSV(to: url)
                alertTitle = "Export CSV Success"
                alertMessage = "Spreadsheet translations exported to \(url.lastPathComponent) successfully."
            } catch {
                alertTitle = "Export Failed"
                alertMessage = "Failed to export translations: \(error.localizedDescription)"
            }
            showingAlert = true
        }
    }

    private func importCSVFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.utf8PlainText]
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false

        if panel.runModal() == .OK, let url = panel.url {
            do {
                try core.importCSV(from: url)
                alertTitle = "Import CSV Success"
                alertMessage = "Spreadsheet translations successfully loaded."
            } catch {
                alertTitle = "Import Failed"
                alertMessage = "Failed to parse CSV translations: \(error.localizedDescription)"
            }
            showingAlert = true
        }
    }

    private func runAITranslation(for record: LocalizedKey) {
        isAIProcessing = true
        aiTranslationResult = ""
        parsedAITranslations = [:]
        aiDidApply = false

        let baseVal = record.translations[core.defaultLanguage] ?? ""
        let targets = core.activeLanguages.filter { $0 != core.defaultLanguage }

        guard !targets.isEmpty else {
            aiTranslationResult = "No secondary active languages to translate to."
            isAIProcessing = false
            return
        }

        let prompt = """
You are SwiftCode's translation engine. Translate the following text from \(core.defaultLanguage) into: \(targets.joined(separator: ", ")).
Key Name: \(record.key)
Original Text (\(core.defaultLanguage)): \(baseVal)

Format your response strictly as key-value pairs (one per line):
[language_code]: [translated_text]
For example:
es: Hola Mundo
fr: Bonjour le monde
"""

        Task {
            do {
                let response = try await LLMService.shared.generateResponse(prompt: prompt, useContext: false)
                aiTranslationResult = response

                // Parse into dictionary
                var dict: [String: String] = [:]
                let lines = response.components(separatedBy: .newlines)
                for line in lines {
                    let parts = line.split(separator: ":", maxSplits: 1).map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
                    if parts.count == 2 {
                        let lang = parts[0].lowercased()
                        let text = parts[1]
                        if targets.contains(lang) {
                            dict[lang] = text
                        }
                    }
                }
                parsedAITranslations = dict
            } catch {
                aiTranslationResult = "AI Translation Failed: \(error.localizedDescription)"
            }
            isAIProcessing = false
        }
    }

    private func applyAITranslations(to record: LocalizedKey) {
        for (lang, val) in parsedAITranslations {
            core.updateTranslation(key: record.key, lang: lang, value: val)
        }
        if let updated = core.keys.first(where: { $0.key == record.key }) {
            core.selectedKey = updated
        }
        aiDidApply = true
    }
}
