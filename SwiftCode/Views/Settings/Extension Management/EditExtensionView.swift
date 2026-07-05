import SwiftUI

// MARK: - Edit Extension View

/// Allows users to edit an existing user-created Extension: update its name,
/// category, description, capabilities, Swift files, and installation status.
struct EditExtensionView: View {
    let `extension`: ExtensionManifest

    @StateObject private var manager = ExtensionManager.shared
    @Environment(\.dismiss) private var dismiss

    // Editable state mirroring the manifest
    @State private var name: String
    @State private var author: String
    @State private var version: String
    @State private var description: String
    @State private var selectedCategory: ExtensionManifest.ExtensionCategory
    @State private var selectedCapabilities: Set<ExtensionManifest.ExtensionCapability>
    @State private var isEnabled: Bool
    @State private var swiftCodeAssistCapable: Bool

    // Swift file editing (loads existing files from disk)
    @State private var swiftFiles: [EditableSwiftFile] = []
    @State private var editingFileIndex: Int?
    @State private var showAddFileSheet = false
    @State private var newFileName = ""

    // Status
    @State private var isSaving = false
    @State private var saveError: String?
    @State private var showError = false
    @State private var showDeleteConfirm = false

    init(extension ext: ExtensionManifest) {
        self.`extension` = ext
        _name = State(initialValue: ext.name)
        _author = State(initialValue: ext.author)
        _version = State(initialValue: ext.version)
        _description = State(initialValue: ext.description)
        _selectedCategory = State(initialValue: ext.category)
        _selectedCapabilities = State(initialValue: Set(ext.capabilities))
        _isEnabled = State(initialValue: ext.isEnabled)
        _swiftCodeAssistCapable = State(initialValue: ext.swiftCodeAssistCapable)
    }

    var hasChanges: Bool {
        name != `extension`.name ||
        author != `extension`.author ||
        version != `extension`.version ||
        description != `extension`.description ||
        selectedCategory != `extension`.category ||
        Set(selectedCapabilities) != Set(`extension`.capabilities) ||
        isEnabled != `extension`.isEnabled ||
        swiftCodeAssistCapable != `extension`.swiftCodeAssistCapable
    }

    var body: some View {
        NavigationStack {
            Form {
                basicInfoSection
                categorySection
                capabilitiesSection
                assistSection
                swiftFilesSection
                installationSection
                deleteSection
            }
            .scrollContentBackground(.hidden)
            .background(Color(red: 0.08, green: 0.08, blue: 0.12).ignoresSafeArea())
            .navigationTitle("Edit Extension")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task { await saveExtension() } }
                        .disabled(!hasChanges || isSaving)
                        .overlay {
                            if isSaving { ProgressView().scaleEffect(0.8) }
                        }
                }
            }
            .alert("Failed to Save", isPresented: $showError, presenting: saveError) { _ in
                Button("OK") {}
            } message: { msg in Text(msg) }
            .confirmationDialog(
                "Delete \(name)?",
                isPresented: $showDeleteConfirm,
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) { deleteExtension() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will permanently delete the extension and remove it from the IDE.")
            }
            .sheet(isPresented: $showAddFileSheet) {
                addFileSheet
            }
            .sheet(item: Binding(
                get: { editingFileIndex.map { EditableFileWrapper(index: $0) } },
                set: { editingFileIndex = $0?.index }
            )) { wrapper in
                editFileSheet(index: wrapper.index)
            }
        }
        .preferredColorScheme(.dark)
        .task { loadSwiftFiles() }
    }

    // MARK: - Sections

    private var basicInfoSection: some View {
        Section("Extension Info") {
            LabeledContent {
                TextField("Name", text: $name)
                    .multilineTextAlignment(.trailing)
                    .autocorrectionDisabled()
            } label: {
                Label("Name", systemImage: "puzzlepiece.extension")
            }

            LabeledContent {
                TextField("Author", text: $author)
                    .multilineTextAlignment(.trailing)
                    .autocorrectionDisabled()
            } label: {
                Label("Author", systemImage: "person")
            }

            LabeledContent {
                TextField("1.0.0", text: $version)
                    .multilineTextAlignment(.trailing)
                    .autocorrectionDisabled()
                    .keyboardType(.numbersAndPunctuation)
            } label: {
                Label("Version", systemImage: "number")
            }

            VStack(alignment: .leading, spacing: 6) {
                Label("Description", systemImage: "doc.text")
                    .font(.subheadline)
                TextEditor(text: $description)
                    .frame(minHeight: 80)
                    .font(.body)
                    .scrollContentBackground(.hidden)
                    .overlay(alignment: .topLeading) {
                        if description.isEmpty {
                            Text("Describe this extension…")
                                .foregroundStyle(.tertiary)
                                .font(.body)
                                .padding(.top, 8)
                                .padding(.leading, 4)
                                .allowsHitTesting(false)
                        }
                    }
            }
        }
    }

    private var categorySection: some View {
        Section("Category") {
            Picker("Category", selection: $selectedCategory) {
                ForEach(ExtensionManifest.ExtensionCategory.allCases) { cat in
                    Label(cat.rawValue, systemImage: cat.icon).tag(cat)
                }
            }
            .pickerStyle(.navigationLink)
        }
    }

    private var capabilitiesSection: some View {
        Section("Capabilities") {
            ForEach(ExtensionManifest.ExtensionCapability.allCases, id: \.self) { cap in
                Toggle(cap.rawValue, isOn: Binding(
                    get: { selectedCapabilities.contains(cap) },
                    set: { enabled in
                        if enabled { selectedCapabilities.insert(cap) }
                        else { selectedCapabilities.remove(cap) }
                    }
                ))
                .tint(.orange)
            }
        }
    }

    private var swiftFilesSection: some View {
        Section {
            ForEach(swiftFiles.indices, id: \.self) { idx in
                HStack {
                    Image(systemName: "swift")
                        .foregroundStyle(.orange)
                    Text(swiftFiles[idx].name)
                        .font(.subheadline)
                    Spacer()
                    Button {
                        editingFileIndex = idx
                    } label: {
                        Image(systemName: "pencil")
                            .foregroundStyle(.blue)
                    }
                    .buttonStyle(.plain)
                }
            }
            .onDelete { offsets in swiftFiles.remove(atOffsets: offsets) }

            Button {
                newFileName = ""
                showAddFileSheet = true
            } label: {
                Label("Add Swift File", systemImage: "plus.circle")
                    .foregroundStyle(.orange)
            }
        } header: {
            Text("Swift Files")
        } footer: {
            Text("Changes to Swift files are saved to disk when you tap Save.")
        }
    }

    private var assistSection: some View {
        Section("Assist API") {
            Toggle("SwiftCode Assist Capable", isOn: $swiftCodeAssistCapable)
                .tint(.orange)
            if swiftCodeAssistCapable {
                Text("Identifier added: \(AssistCapability.toolIdentifier)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var installationSection: some View {
        Section("Status") {
            Toggle("Enabled", isOn: $isEnabled)
                .tint(.orange)

            HStack {
                Label("Extension ID", systemImage: "tag")
                Spacer()
                Text(`extension`.id)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
    }

    private var deleteSection: some View {
        Section {
            Button(role: .destructive) {
                showDeleteConfirm = true
            } label: {
                Label("Delete Extension", systemImage: "trash")
                    .foregroundStyle(.red)
            }
        } footer: {
            Text("Deleting an extension removes its folder and unloads it from the IDE.")
        }
    }

    // MARK: - Add File Sheet

    private var addFileSheet: some View {
        NavigationStack {
            Form {
                Section("File Name") {
                    TextField("NewFeature.swift", text: $newFileName)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color(red: 0.08, green: 0.08, blue: 0.12).ignoresSafeArea())
            .navigationTitle("Add File")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showAddFileSheet = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        let safeName = newFileName.hasSuffix(".swift") ? newFileName : "\(newFileName).swift"
                        swiftFiles.append(EditableSwiftFile(name: safeName, content: "import Foundation\n\n// TODO: Implement \(safeName)\n", isNew: true))
                        showAddFileSheet = false
                    }
                    .disabled(newFileName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Edit File Sheet

    private func editFileSheet(index: Int) -> some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 0) {
                Text(swiftFiles[index].name)
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
                    .padding(.top, 8)
                TextEditor(text: $swiftFiles[index].content)
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundStyle(.white)
                    .scrollContentBackground(.hidden)
                    .padding()
            }
            .background(Color(red: 0.08, green: 0.08, blue: 0.12).ignoresSafeArea())
            .navigationTitle("Edit File")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { editingFileIndex = nil }
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Actions

    private func loadSwiftFiles() {
        let folderURL = manager.extensionsDirectory.appendingPathComponent(`extension`.id)
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: folderURL, includingPropertiesForKeys: nil, options: .skipsHiddenFiles) else { return }
        swiftFiles = files
            .filter { $0.pathExtension == "swift" }
            .compactMap { url -> EditableSwiftFile? in
                guard let content = try? String(contentsOf: url, encoding: .utf8) else { return nil }
                return EditableSwiftFile(name: url.lastPathComponent, content: content, isNew: false)
            }
            .sorted { $0.name < $1.name }
    }

    private func saveExtension() async {
        isSaving = true
        defer { isSaving = false }

        var updated = `extension`
        updated.name = name.trimmingCharacters(in: .whitespaces)
        updated.author = author.trimmingCharacters(in: .whitespaces)
        updated.version = version
        updated.description = description
        updated.category = selectedCategory
        updated.capabilities = Array(selectedCapabilities)
        updated.isEnabled = isEnabled
        updated.swiftCodeAssistCapable = swiftCodeAssistCapable
        updated.identificationTags = AssistCapability.identifiers(enabled: swiftCodeAssistCapable)

        do {
            try manager.updateExtension(manifest: updated)
            // Save modified Swift files
            let folderURL = manager.extensionsDirectory.appendingPathComponent(`extension`.id)
            for file in swiftFiles {
                let fileURL = folderURL.appendingPathComponent(file.name)
                try file.content.write(to: fileURL, atomically: true, encoding: String.Encoding.utf8)
            }
            dismiss()
        } catch {
            saveError = error.localizedDescription
            showError = true
        }
    }

    private func deleteExtension() {
        try? manager.uninstallExtension(`extension`)
        dismiss()
    }
}

// MARK: - Supporting Types

private struct EditableSwiftFile: Identifiable {
    let id = UUID()
    var name: String
    var content: String
    let isNew: Bool
}

private struct EditableFileWrapper: Identifiable {
    let index: Int
    var id: Int { index }
}
