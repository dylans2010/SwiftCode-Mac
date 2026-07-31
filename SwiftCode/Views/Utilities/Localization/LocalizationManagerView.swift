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
    @State private var aiTranslationPrompt = ""
    @State private var aiTranslationResult = ""

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

    public var body: some View {
        HSplitView {
            // Panel 1: Left Navigation Sidebar
            VStack(alignment: .leading, spacing: 0) {
                // Header
                HStack {
                    Label("String Catalogs", systemImage: "text.book.closed.fill")
                        .font(.headline)
                        .foregroundColor(.orange)
                    Spacer()
                }
                .padding()
                .background(Color(NSColor.windowBackgroundColor))

                Divider()

                List(core.availableFiles, id: \.path) { file in
                    Button {
                        core.selectedFile = file
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "doc.text.fill")
                                .foregroundColor(file.type == "xcstrings" ? .orange : .blue)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(file.name)
                                    .font(.subheadline.bold())
                                    .foregroundColor(core.selectedFile?.path == file.path ? .accentColor : .primary)
                                Text(file.type.uppercased())
                                    .font(.system(size: 9, design: .monospaced))
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .padding(.vertical, 4)
                }
                .listStyle(.sidebar)

                Divider()

                // Language selection configurations
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("ACTIVE LANGUAGES")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.secondary)
                        Spacer()
                        Button {
                            showLanguageSettings.toggle()
                        } label: {
                            Image(systemName: "plus.circle")
                                .foregroundColor(.blue)
                        }
                        .buttonStyle(.plain)
                        .help("Manage Languages")
                    }

                    ForEach(core.languages, id: \.self) { lang in
                        HStack {
                            Toggle("", isOn: Binding(
                                get: { core.activeLanguages.contains(lang) },
                                set: { _ in core.toggleLanguageActive(lang) }
                            ))
                            .toggleStyle(.checkbox)

                            Text(lang.uppercased())
                                .font(.system(.caption, design: .monospaced))
                                .bold()

                            Spacer()

                            if lang == core.defaultLanguage {
                                Text("DEFAULT")
                                    .font(.system(size: 8, weight: .bold))
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 1)
                                    .background(Color.green.opacity(0.15), in: RoundedRectangle(cornerRadius: 3))
                                    .foregroundStyle(.green)
                            } else {
                                Button {
                                    core.removeLanguage(lang)
                                } label: {
                                    Image(systemName: "trash")
                                        .font(.caption2)
                                        .foregroundColor(.red)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
                .padding()
                .background(Color(NSColor.windowBackgroundColor))
            }
            .frame(width: 250)

            // Panel 2: Spreadsheet Keys Editor
            VStack(spacing: 0) {
                // Toolbar
                HStack(spacing: 12) {
                    // Search Bar
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.secondary)
                        TextField("Search translations...", text: $core.searchEditorQuery)
                            .textFieldStyle(.plain)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
                    .frame(width: 250)

                    // Missing filter toggle
                    Toggle("Missing Only", isOn: $core.filterMissingOnly)
                        .toggleStyle(.button)

                    Spacer()

                    // Add key button
                    Button {
                        showKeyCreationSheet = true
                    } label: {
                        Label("Add Key", systemImage: "plus.circle.fill")
                    }
                    .buttonStyle(.bordered)

                    // Validation triggers
                    Button(action: runValidationChecks) {
                        Label("Validate", systemImage: "checkmark.shield")
                    }
                    .buttonStyle(.bordered)

                    // Export / Import
                    Menu("Share") {
                        Button("Export as CSV...") { exportCSVReport() }
                        Button("Import from CSV...") { importCSVFile() }
                    }
                    .menuStyle(.button)
                }
                .padding()
                .background(Color(NSColor.windowBackgroundColor))

                Divider()

                // Key rows grid scroll list
                if filteredKeys.isEmpty {
                    ContentUnavailableView("No Keys Found", systemImage: "text.badge.plus", description: Text("Create translation keys or adjust search criteria to inspect records."))
                        .frame(maxHeight: .infinity)
                } else {
                    List(filteredKeys, selection: $core.selectedKey) { record in
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(alignment: .top) {
                                Text(record.key)
                                    .font(.system(.subheadline, design: .monospaced))
                                    .bold()
                                    .textSelection(.enabled)

                                Spacer()

                                Button {
                                    core.deleteKey(record.key)
                                } label: {
                                    Image(systemName: "trash")
                                        .foregroundColor(.red)
                                }
                                .buttonStyle(.plain)
                            }

                            if let comment = record.comment, !comment.isEmpty {
                                Text("Comment: \(comment)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }

                            // Spreadsheet value cells for each active language
                            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
                                ForEach(Array(core.activeLanguages), id: \.self) { lang in
                                    GridRow {
                                        Text(lang.uppercased())
                                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                                            .foregroundColor(.secondary)
                                            .frame(width: 32, alignment: .leading)

                                        TextField("Translation value...", text: Binding(
                                            get: { record.translations[lang] ?? "" },
                                            set: { core.updateTranslation(key: record.key, lang: lang, value: $0) }
                                        ))
                                        .textFieldStyle(.roundedBorder)
                                        .font(.subheadline)
                                        .textSelection(.enabled)
                                    }
                                }
                            }
                        }
                        .padding()
                        .background(core.selectedKey?.key == record.key ? Color.accentColor.opacity(0.08) : Color.secondary.opacity(0.03))
                        .cornerRadius(8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(core.selectedKey?.key == record.key ? Color.accentColor : Color.secondary.opacity(0.12), lineWidth: 1)
                        )
                        .padding(.vertical, 4)
                        .tag(record)
                    }
                    .listStyle(.inset)
                }
            }
            .frame(minWidth: 500)

            // Panel 3: Right Side Details & AI Assistant
            VStack(alignment: .leading, spacing: 20) {
                if let keyRecord = core.selectedKey {
                    Text("Translation Editor Details")
                        .font(.headline)
                        .foregroundColor(.secondary)

                    Divider()

                    VStack(alignment: .leading, spacing: 6) {
                        Text("KEY IDENTIFIER")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.secondary)
                        Text(keyRecord.key)
                            .font(.system(.body, design: .monospaced))
                            .bold()
                            .textSelection(.enabled)
                    }

                    if let comment = keyRecord.comment {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("DEVELOPER COMMENT")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(.secondary)
                            Text(comment)
                                .font(.subheadline)
                                .textSelection(.enabled)
                        }
                    }

                    Divider()

                    // AI Localization Actions Card
                    GroupBox {
                        VStack(alignment: .leading, spacing: 12) {
                            Label("AI Translator Co-Pilot", systemImage: "sparkles")
                                .font(.headline)
                                .foregroundColor(.purple)

                            Text("Automatically translate the active key value to all other active languages, or polish word phrasing with native context patterns.")
                                .font(.caption)
                                .foregroundColor(.secondary)

                            Button {
                                runAITranslation(for: keyRecord)
                            } label: {
                                HStack {
                                    if isAIProcessing {
                                        ProgressView()
                                            .scaleEffect(0.6)
                                            .padding(.trailing, 4)
                                        Text("Translating...")
                                    } else {
                                        Image(systemName: "sparkles")
                                        Text("Translate with AI")
                                    }
                                }
                                .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(isAIProcessing)

                            if !aiTranslationResult.isEmpty {
                                ScrollView {
                                    Text(aiTranslationResult)
                                        .font(.caption)
                                        .textSelection(.enabled)
                                        .padding(8)
                                        .background(Color.black.opacity(0.12))
                                        .cornerRadius(6)
                                }
                                .frame(height: 120)
                            }
                        }
                        .padding(6)
                    }
                    .groupBoxStyle(ModernGroupBoxStyle())

                    // Character count validation
                    VStack(alignment: .leading, spacing: 6) {
                        Text("TRANSLATION STATISTICS")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.secondary)

                        let baseLength = (keyRecord.translations[core.defaultLanguage] ?? "").count
                        Text("Default text character count: \(baseLength)")
                            .font(.caption)
                    }

                } else {
                    ContentUnavailableView("Select a Key", systemImage: "text.cursor")
                }
                Spacer()
            }
            .padding()
            .frame(width: 280)
            .background(Color(NSColor.windowBackgroundColor))
        }
        .onAppear {
            core.scanProjectFiles()
        }
        .sheet(isPresented: $showLanguageSettings) {
            VStack(spacing: 16) {
                Text("Manage Active Languages")
                    .font(.headline)

                Form {
                    TextField("Language Code (e.g. de, fr, ja, it)", text: $selectedLanguageCodeToAdd)
                }

                HStack {
                    Button("Close") { showLanguageSettings = false }
                    Spacer()
                    Button("Add Language") {
                        core.addLanguage(selectedLanguageCodeToAdd)
                        showLanguageSettings = false
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(selectedLanguageCodeToAdd.isEmpty)
                }
            }
            .padding()
            .frame(width: 300)
        }
        .sheet(isPresented: $showKeyCreationSheet) {
            VStack(alignment: .leading, spacing: 16) {
                Text("Add Localization Key")
                    .font(.headline)

                Form {
                    TextField("Key Name (e.g. dashboard_title)", text: $newKeyName)
                    TextField("Developer Comment / Usage", text: $newKeyComment)
                }

                HStack {
                    Button("Cancel") { showKeyCreationSheet = false }
                    Spacer()
                    Button("Create") {
                        core.addKey(newKeyName, comment: newKeyComment)
                        newKeyName = ""
                        newKeyComment = ""
                        showKeyCreationSheet = false
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(newKeyName.isEmpty)
                }
            }
            .padding()
            .frame(width: 350)
        }
        .sheet(isPresented: $isShowingValidationHUD) {
            VStack(spacing: 16) {
                HStack {
                    Text("Localization Validation Results")
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
                        Text("All keys contain intact format specifiers and valid translation segments.")
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
                        .padding(.vertical, 6)
                    }
                }
            }
            .frame(width: 480, height: 400)
        }
        .alert(alertTitle, isPresented: $showingAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(alertMessage)
        }
    }

    // MARK: - Core Operations

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

        let baseVal = record.translations[core.defaultLanguage] ?? ""
        let targets = core.activeLanguages.filter { $0 != core.defaultLanguage }

        let prompt = """
You are SwiftCode's translation engine. Translate the following key/text into these target languages: \(targets.joined(separator: ", ")).
Key Name: \(record.key)
Default Text (\(core.defaultLanguage)): \(baseVal)

Respond in a valid JSON-like format or clean list:
Target Language: Translation
"""

        Task {
            do {
                let response = try await LLMService.shared.generateResponse(prompt: prompt, useContext: false)
                aiTranslationResult = response
            } catch {
                aiTranslationResult = "AI Translation Failed: \(error.localizedDescription)"
            }
            isAIProcessing = false
        }
    }
}
