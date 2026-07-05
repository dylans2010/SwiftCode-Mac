import SwiftUI
import UniformTypeIdentifiers

struct CreateGistView: View {
    @EnvironmentObject private var gistService: GitHubGistService
    @Environment(\.dismiss) private var dismiss

    @State private var description = ""
    @State private var isPublic = false
    @State private var commentsEnabled = true
    @State private var creationStyle: CreationStyle = .tabs
    @State private var files: [GistFile]
    @State private var selectedFileID: UUID?
    @State private var successGist: GistResponse?
    @State private var showFileImporter = false
    @State private var showPasteSheet = false
    @State private var pasteContent = ""
    @State private var pasteFilename = ""
    @State private var preserveFolderStructure = true

    enum CreationStyle: String, CaseIterable, Identifiable {
        case tabs = "Tabs"
        case list = "List"
        var id: String { self.rawValue }
    }

    init(initialFilename: String? = nil, initialContent: String? = nil) {
        let defaultFile = GistFile(
            filename: initialFilename ?? "",
            content: initialContent ?? ""
        )
        _files = State(initialValue: [defaultFile])
        _selectedFileID = State(initialValue: defaultFile.id)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(red: 0.10, green: 0.10, blue: 0.14).ignoresSafeArea()

                if let success = successGist {
                    GistSuccessView(gist: success, onDismiss: { dismiss() }, onCreateAnother: {
                        successGist = nil
                        description = ""
                        isPublic = false
                        files = [GistFile(filename: "", content: "")]
                        selectedFileID = files[0].id
                    })
                } else {
                    VStack(spacing: 0) {
                        formSection

                        if creationStyle == .tabs {
                            GistFileTabBar(files: files, selectedFileID: $selectedFileID, isEditing: true, onRemoveFile: removeFile)
                            editorSection
                        } else {
                            listViewSection
                        }

                        importToolbar
                    }
                }
            }
            .navigationTitle("New Gist")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if successGist == nil {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        if gistService.isLoading {
                            ProgressView()
                        } else {
                            Button("Create") {
                                Task { await createGist() }
                            }
                            .disabled(files.allSatisfy { $0.content.isEmpty } || files.allSatisfy { $0.filename.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
                        }
                    }
                }
            }
            .overlay {
                if showFileImporter {
                    FileImporterRepresentableView(
                        allowedContentTypes: [.item],
                        allowsMultipleSelection: true
                    ) { urls in
                        showFileImporter = false
                        if !urls.isEmpty {
                            handleFileImport(.success(urls))
                        }
                    }
                    .ignoresSafeArea()
                }
            }
            .sheet(isPresented: $showPasteSheet) {
                pasteSnippetSheet
            }
            .overlay {
                if let error = gistService.errorMessage {
                    errorBanner(message: error)
                }
            }
        }
    }

    private func errorBanner(message: String) -> some View {
        VStack {
            Spacer()
            Text(message)
                .font(.subheadline)
                .padding()
                .background(Color.red.opacity(0.9), in: RoundedRectangle(cornerRadius: 12))
                .padding()
                .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    private var formSection: some View {
        VStack(spacing: 12) {
            TextField("Gist description...", text: $description)
                .padding(12)
                .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))

            HStack(spacing: 16) {
                Toggle(isOn: $isPublic) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Public Gist")
                            .font(.subheadline.bold())
                        Text("Anyone can see")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                Toggle(isOn: $commentsEnabled) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Comments")
                            .font(.subheadline.bold())
                        Text("Allow replies")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.horizontal, 4)

            Picker("Creation Style", selection: $creationStyle) {
                ForEach(CreationStyle.allCases) { style in
                    Text(style.rawValue).tag(style)
                }
            }
            .pickerStyle(.segmented)
            .padding(.top, 4)

            Toggle("Preserve folder names when importing", isOn: $preserveFolderStructure)
                .font(.caption)
                .tint(.blue)
        }
        .padding()
        .background(Color(red: 0.12, green: 0.12, blue: 0.16))
    }

    private var editorSection: some View {
        Group {
            if let index = files.firstIndex(where: { $0.id == selectedFileID }) {
                GistFileEditorView(file: $files[index], isEditing: true)
            } else {
                Color.clear
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var listViewSection: some View {
        List {
            ForEach($files) { $file in
                VStack(alignment: .leading, spacing: 8) {
                    TextField("Filename", text: $file.filename)
                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                        .padding(8)
                        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 4))

                    TextEditor(text: $file.content)
                        .font(.system(size: 13, design: .monospaced))
                        .frame(minHeight: 100)
                        .padding(8)
                        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 4))
                        .scrollContentBackground(.hidden)
                }
                .padding(.vertical, 8)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }
            .onDelete { indices in
                files.remove(atOffsets: indices)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    private var importToolbar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                importButton(title: "Add File", icon: "plus.circle") {
                    let newFile = GistFile(filename: "", content: "")
                    files.append(newFile)
                    selectedFileID = newFile.id
                }

                importButton(title: "From Editor", icon: "arrow.down.doc") {
                    importFromEditor()
                }

                importButton(title: "Import File", icon: "doc.badge.plus") {
                    showFileImporter = true
                }

                importButton(title: "Paste", icon: "doc.on.clipboard") {
                    if let content = UIPasteboard.general.string {
                        updateCurrentFileContent(content)
                    }
                }

                importButton(title: "Snippet", icon: "curlybraces") {
                    showPasteSheet = true
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .background(Color(red: 0.12, green: 0.12, blue: 0.16))
        .overlay(Rectangle().fill(Color.white.opacity(0.05)).frame(height: 1), alignment: .top)
    }

    private func importButton(title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .bold))
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
            .foregroundStyle(.white)
        }
        .buttonStyle(.plain)
    }

    private var pasteSnippetSheet: some View {
        NavigationStack {
            VStack(spacing: 0) {
                TextField("Filename (optional)", text: $pasteFilename)
                    .padding()
                    .background(Color.white.opacity(0.05))
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)

                TextEditor(text: $pasteContent)
                    .font(.system(size: 14, design: .monospaced))
                    .padding()
                    .background(Color(red: 0.11, green: 0.11, blue: 0.14))
                    .scrollContentBackground(.hidden)
                    .onChange(of: pasteContent) { _, newValue in
                        if pasteFilename.isEmpty {
                            pasteFilename = suggestFilename(for: newValue)
                        }
                    }

                Divider()

                HStack {
                    Button("Cancel") { showPasteSheet = false }
                        .padding()
                    Spacer()
                    Button("Import Snippet") {
                        let filename = pasteFilename.isEmpty ? "snippet-\(files.count + 1).txt" : pasteFilename
                        let newFile = GistFile(filename: filename, content: pasteContent)
                        files.append(newFile)
                        selectedFileID = newFile.id
                        pasteContent = ""
                        pasteFilename = ""
                        showPasteSheet = false
                    }
                    .bold()
                    .disabled(pasteContent.isEmpty)
                    .padding()
                }
            }
            .navigationTitle("Paste Snippet")
            .navigationBarTitleDisplayMode(.inline)
            .background(Color(red: 0.10, green: 0.10, blue: 0.14))
        }
        .presentationDetents([.medium, .large])
    }

    private func updateCurrentFileContent(_ content: String) {
        if let index = files.firstIndex(where: { $0.id == selectedFileID }) {
            files[index].content = content
        }
    }

    private func importFromEditor() {
        let activeContent = ProjectManager.shared.activeFileContent
        let activeName = ProjectManager.shared.activeFileNode?.name ?? ""
        let newFile = GistFile(filename: activeName, content: activeContent)
        files.append(newFile)
        selectedFileID = newFile.id
    }

    private func suggestFilename(for content: String) -> String {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("import SwiftUI") || trimmed.hasPrefix("import UIKit") {
            return "View.swift"
        }
        if trimmed.hasPrefix("import Foundation") || trimmed.contains("func ") || trimmed.contains("struct ") {
            return "File.swift"
        }
        if trimmed.hasPrefix("{") || trimmed.hasPrefix("[") {
            return "data.json"
        }
        if trimmed.hasPrefix("#") || trimmed.contains("##") {
            return "README.md"
        }
        return ""
    }

    private func removeFile(id: UUID) {
        files.removeAll { $0.id == id }
        if selectedFileID == id {
            selectedFileID = files.first?.id
        }
    }

    private func createGist() async {
        do {
            let result = try await gistService.createGist(files: files, description: description, isPublic: isPublic)
            self.successGist = result
        } catch {
            print("Failed to create Gist: \(error)")
        }
    }

    private func handleFileImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            for url in urls {
                if let imported = importEntries(from: url) {
                    for entry in imported {
                        let newFile = GistFile(filename: entry.name, content: entry.content)
                        files.append(newFile)
                        selectedFileID = newFile.id
                    }
                }
            }
        case .failure(let error):
            print("File import failed: \(error)")
        }
    }

    private func importEntries(from url: URL) -> [(name: String, content: String)]? {
        let hasAccess = url.startAccessingSecurityScopedResource()
        defer { if hasAccess { url.stopAccessingSecurityScopedResource() } }

        guard let values = try? url.resourceValues(forKeys: [.isDirectoryKey]) else { return nil }

        if values.isDirectory == true {
            guard let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) else {
                return nil
            }

            var entries: [(name: String, content: String)] = []
            while let fileURL = enumerator.nextObject() as? URL {
                let fileValues = try? fileURL.resourceValues(forKeys: [.isDirectoryKey])
                guard fileValues?.isDirectory != true else { continue }
                guard let content = try? String(contentsOf: fileURL) else { continue }

                let filename: String
                if preserveFolderStructure {
                    let relative = fileURL.path.replacingOccurrences(of: url.path + "/", with: "")
                    filename = relative
                } else {
                    filename = fileURL.lastPathComponent
                }
                entries.append((filename, content))
            }
            return entries
        }

        guard let content = try? String(contentsOf: url) else { return nil }
        return [(url.lastPathComponent, content)]
    }
}

// MARK: - Success View

struct GistSuccessView: View {
    let gist: GistResponse
    var onDismiss: () -> Void
    var onCreateAnother: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 80))
                .foregroundStyle(.green)
                .symbolEffect(.bounce, value: gist.id)

            VStack(spacing: 8) {
                Text("Gist Created!")
                    .font(.title2.bold())
                Text("Your code has been uploaded to GitHub")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 12) {
                Button {
                    UIPasteboard.general.string = gist.htmlUrl
                } label: {
                    HStack {
                        Image(systemName: "link")
                        Text("Copy Link")
                        Spacer()
                        Text(gist.htmlUrl)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                    .padding()
                    .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)

                Button {
                    if let url = URL(string: gist.htmlUrl) {
                        UIApplication.shared.open(url)
                    }
                } label: {
                    Label("Open in Browser", systemImage: "safari")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue, in: RoundedRectangle(cornerRadius: 10))
                        .foregroundStyle(.white)
                        .bold()
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 32)

            Spacer()

            HStack(spacing: 16) {
                Button("Create Another", action: onCreateAnother)
                    .buttonStyle(.bordered)
                Button("Done", action: onDismiss)
                    .buttonStyle(.borderedProminent)
            }
            .padding(.bottom, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(red: 0.10, green: 0.10, blue: 0.14))
    }
}
