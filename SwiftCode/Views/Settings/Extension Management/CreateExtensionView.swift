import SwiftUI

// MARK: - Create Extension View

struct CreateExtensionView: View {
    @StateObject private var manager = ExtensionManager.shared
    @Environment(\.dismiss) private var dismiss

    // Manifest fields
    @State private var name = ""
    @State private var author = ""
    @State private var version = "1.0.0"
    @State private var description = ""
    @State private var selectedCategory: ExtensionManifest.ExtensionCategory = .other
    @State private var selectedCapabilities: Set<ExtensionManifest.ExtensionCapability> = []

    // Swift files
    @State private var swiftFiles: [SwiftFileEntry] = [
        SwiftFileEntry(name: "Main.swift", content: "// MARK: - Extension Entry Point\n\nimport Foundation\n\n// TODO: Implement your extension logic here.\n")
    ]
    @State private var showAddFileSheet = false
    @State private var newFileName = ""
    @State private var editingFileIndex: Int?
    @State private var swiftCodeAssistCapable = false

    // Status
    @State private var installImmediately = true
    @State private var isCreating = false
    @State private var creationError: String?
    @State private var showError = false

    var canCreate: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty &&
        !author.trimmingCharacters(in: .whitespaces).isEmpty &&
        !swiftFiles.isEmpty
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
            }
            .scrollContentBackground(.hidden)
            .background(Color(red: 0.08, green: 0.08, blue: 0.12).ignoresSafeArea())
            .navigationTitle("Create Extension")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") { Task { await createExtension() } }
                        .disabled(!canCreate || isCreating)
                        .overlay {
                            if isCreating { ProgressView().scaleEffect(0.8) }
                        }
                }
            }
            .alert("Failed to Create Extension", isPresented: $showError, presenting: creationError) { _ in
                Button("OK") {}
            } message: { msg in Text(msg) }
            .sheet(isPresented: $showAddFileSheet) {
                addFileSheet
            }
            .sheet(item: Binding(
                get: { editingFileIndex.map { EditingFile(index: $0) } },
                set: { editingFileIndex = $0?.index }
            )) { ef in
                editFileSheet(index: ef.index)
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Sections

    private var basicInfoSection: some View {
        Section("Extension Info") {
            LabeledContent {
                TextField("Extension Name", text: $name)
                    .multilineTextAlignment(.trailing)
                    .autocorrectionDisabled()
            } label: {
                Label("Name", systemImage: "puzzlepiece.extension")
            }

            LabeledContent {
                TextField("Your Name", text: $author)
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
                    .foregroundStyle(.primary)
                TextEditor(text: $description)
                    .frame(minHeight: 80)
                    .font(.body)
                    .scrollContentBackground(.hidden)
                    .overlay(alignment: .topLeading) {
                        if description.isEmpty {
                            Text("Extension Description")
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
            .onDelete { offsets in
                swiftFiles.remove(atOffsets: offsets)
            }

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
            Text("At least one Swift file is required for the Extension code logic. Tap a file to edit its content.")
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
        Section("Installation") {
            Toggle("Install Immediately", isOn: $installImmediately)
                .tint(.orange)
            if installImmediately {
                Label("Extension will be enabled in the code editor after creation.", systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Add File Sheet

    private var addFileSheet: some View {
        NavigationStack {
            Form {
                Section("File Name") {
                    TextField("MyFeature.swift", text: $newFileName)
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
                        swiftFiles.append(SwiftFileEntry(
                            name: safeName,
                            content: "import Foundation\n\n// TODO: Implement \(safeName)\n"
                        ))
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

    // MARK: - Create Action

    private func createExtension() async {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty else { return }
        isCreating = true
        defer { isCreating = false }

        // Build a safe folder ID from the name
        let safeID = trimmedName
            .lowercased()
            .replacingOccurrences(of: " ", with: "-")
            .filter { $0.isLetter || $0.isNumber || $0 == "-" }

        let manifest = ExtensionManifest(
            id: "\(safeID)-\(UUID().uuidString.prefix(8).lowercased())",
            name: trimmedName,
            version: version.isEmpty ? "1.0.0" : version,
            description: description,
            author: author.trimmingCharacters(in: .whitespaces),
            category: selectedCategory,
            capabilities: Array(selectedCapabilities),
            entryPoint: swiftFiles.first?.name ?? "Main.swift",
            assetPaths: [],
            isInstalled: installImmediately,
            isEnabled: installImmediately,
            isUserCreated: true,
            swiftCodeAssistCapable: swiftCodeAssistCapable,
            identificationTags: AssistCapability.identifiers(enabled: swiftCodeAssistCapable)
        )

        let files = swiftFiles.map { (name: $0.name, content: $0.content) }

        do {
            try manager.createExtension(manifest: manifest, swiftFiles: files, assetFiles: [])
            dismiss()
        } catch {
            creationError = error.localizedDescription
            showError = true
        }
    }
}

// MARK: - Supporting Types

private struct SwiftFileEntry: Identifiable {
    let id = UUID()
    var name: String
    var content: String
}

private struct EditingFile: Identifiable {
    let index: Int
    var id: Int { index }
}
