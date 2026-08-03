import SwiftUI
import AppKit

// MARK: - Filename Validator

public struct FilenameValidator {
    public static let reservedNames = [
        "con", "prn", "aux", "nul", "com1", "com2", "com3", "com4", "com5", "com6", "com7", "com8", "com9",
        "lpt1", "lpt2", "lpt3", "lpt4", "lpt5", "lpt6", "lpt7", "lpt8", "lpt9"
    ]

    public static func validate(filename: String, inDirectory url: URL, isFolder: Bool) -> String? {
        let trimmed = filename.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return "Filename cannot be empty."
        }

        // Invalid characters
        let invalidCharacters = CharacterSet(charactersIn: "\\/:*?\"<>|")
        if trimmed.rangeOfCharacter(from: invalidCharacters) != nil {
            return "Filename contains invalid characters (\\ / : * ? \" < > |)."
        }

        // Reserved names check
        let baseName = URL(fileURLWithPath: trimmed).deletingPathExtension().lastPathComponent.lowercased()
        if reservedNames.contains(baseName) {
            return "Filename is a reserved system name."
        }

        // Must include extension if it's a file
        if !isFolder {
            let pathExt = URL(fileURLWithPath: trimmed).pathExtension
            if pathExt.isEmpty {
                return "File name must include its extension (e.g. .swift, .json, .md)."
            }
        }

        // Duplicate check
        let destinationURL = url.appendingPathComponent(trimmed)
        if FileManager.default.fileExists(atPath: destinationURL.path) {
            return "A file or folder already exists with this name."
        }

        return nil
    }
}

// MARK: - FileTemplatesView

@MainActor
public struct FileTemplatesView: View {
    @Environment(\.dismiss) private var dismiss
    let viewModel: ProjectTreeViewModel

    @State private var manager = TemplateManager.shared
    @State private var selectedCategory: String = "All Templates"
    @State private var searchText: String = ""
    @State private var isGridView: Bool = true
    @State private var sortBy: String = "Name"

    @State private var selectedTemplate: FileTemplate?
    @State private var filenameInput: String = ""
    @State private var isFolderCreation: Bool = false
    @State private var errorMsg: String?

    // Quick Sheet / Modal state for blank creations
    @State private var showingBlankCreationSheet: Bool = false
    @State private var blankIsFolder: Bool = false
    @State private var blankFilename: String = ""
    @State private var blankErrorMsg: String?

    public init(viewModel: ProjectTreeViewModel) {
        self.viewModel = viewModel
    }

    private var sortedAndFilteredTemplates: [FileTemplate] {
        var result = manager.templates

        // 1. Sidebar Category filter
        if selectedCategory == "Favorites" {
            result = result.filter { manager.favorites.contains($0.id) }
        } else if selectedCategory == "Recently Used" {
            result = manager.recentlyUsed.compactMap { id in
                manager.templates.first { $0.id == id }
            }
        } else if selectedCategory != "All Templates" {
            result = result.filter { $0.category == selectedCategory }
        }

        // 2. Search Text filter
        if !searchText.isEmpty {
            result = result.filter {
                $0.name.localizedCaseInsensitiveContains(searchText) ||
                $0.category.localizedCaseInsensitiveContains(searchText) ||
                $0.description.localizedCaseInsensitiveContains(searchText) ||
                $0.suggestedExtension.localizedCaseInsensitiveContains(searchText)
            }
        }

        // 3. Sorting
        if sortBy == "Name" {
            result.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        } else if sortBy == "Category" {
            result.sort { $0.category.localizedCaseInsensitiveCompare($1.category) == .orderedAscending }
        } else if sortBy == "Size" {
            result.sort { $0.estimatedLineCount > $1.estimatedLineCount }
        }

        return result
    }

    private var allDiscoveredCategories: [String] {
        let cats = Set(manager.templates.map { $0.category })
        return Array(cats).sorted(by: { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending })
    }

    private var destinationDirectory: URL {
        guard let projectURL = viewModel.projectURL else {
            return URL(fileURLWithPath: "/")
        }
        var targetDir = projectURL
        if let selectedNodeID = viewModel.selectedNodeID {
            let selectedURL = URL(fileURLWithPath: selectedNodeID)
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: selectedURL.path, isDirectory: &isDir), isDir.boolValue {
                targetDir = selectedURL
            } else {
                targetDir = selectedURL.deletingLastPathComponent()
            }
        }
        return targetDir
    }

    public var body: some View {
        HStack(spacing: 0) {
            // MARK: - Left Sidebar: Categories list and Quick Actions
            VStack(alignment: .leading, spacing: 0) {
                Text("File Templates")
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                    .padding(.bottom, 12)

                List(selection: $selectedCategory) {
                    Section(header: Text("Smart Filters").font(.system(size: 9, weight: .bold))) {
                        categoryRow(name: "All Templates", icon: "square.grid.2x2.fill", color: .blue)
                        categoryRow(name: "Favorites", icon: "star.fill", color: .yellow)
                        categoryRow(name: "Recently Used", icon: "clock.fill", color: .purple)
                    }

                    Section(header: Text("Categories").font(.system(size: 9, weight: .bold))) {
                        ForEach(allDiscoveredCategories, id: \.self) { cat in
                            let details = manager.templates.first { $0.category == cat }
                            categoryRow(
                                name: cat,
                                icon: details?.iconName ?? "folder.fill",
                                color: details?.iconColor ?? .primary
                            )
                        }
                    }
                }
                .listStyle(.sidebar)

                Divider()

                // Sidebar Footer Quick Actions
                VStack(spacing: 8) {
                    Button(action: { showBlankCreation(isFolder: false) }) {
                        Label("Create Empty File...", systemImage: "doc.badge.plus")
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .font(.caption)
                    .padding(.horizontal, 12)

                    Button(action: { showBlankCreation(isFolder: true) }) {
                        Label("Create Empty Folder...", systemImage: "folder.badge.plus")
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .font(.caption)
                    .padding(.horizontal, 12)
                }
                .padding(.vertical, 12)
                .background(.ultraThinMaterial)
            }
            .frame(width: 200)
            .background(.regularMaterial)

            Divider()

            // MARK: - Center Pane: Toolbar, Grid/List browser
            VStack(spacing: 0) {
                // Toolbar
                HStack(spacing: 12) {
                    // Search Bar
                    HStack(spacing: 6) {
                        Image(systemName: "magnifyingglass")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        TextField("Search templates...", text: $searchText)
                            .textFieldStyle(.plain)
                            .font(.subheadline)
                        if !searchText.isEmpty {
                            Button {
                                searchText = ""
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))

                    Spacer()

                    // Sorting Picker
                    Picker("Sort", selection: $sortBy) {
                        Text("Name").tag("Name")
                        Text("Category").tag("Category")
                        Text("Line Count").tag("Size")
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 180)

                    // Layout Grid/List Toggle
                    Picker("Layout", selection: $isGridView) {
                        Image(systemName: "square.grid.2x2.fill").tag(true)
                        Image(systemName: "list.bullet").tag(false)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 70)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(.thinMaterial)

                Divider()

                // Templates Browser (Grid or List)
                if manager.isLoading {
                    VStack {
                        ProgressView()
                        Text("Scanning file templates...")
                            .foregroundStyle(.secondary)
                            .padding(.top, 8)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if sortedAndFilteredTemplates.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "doc.questionmark.fill")
                            .font(.system(size: 36))
                            .foregroundStyle(.tertiary)
                        Text("No templates match the selection.")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        if isGridView {
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 110, maximum: 130), spacing: 14)], spacing: 14) {
                                ForEach(sortedAndFilteredTemplates) { template in
                                    templateGridCard(template)
                                }
                            }
                            .padding(16)
                        } else {
                            LazyVStack(spacing: 0) {
                                ForEach(sortedAndFilteredTemplates) { template in
                                    templateListRow(template)
                                    Divider()
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            // MARK: - Right Pane: Preview and Customizer Settings
            VStack(alignment: .leading, spacing: 16) {
                if let template = selectedTemplate {
                    // Header Details
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            ZStack {
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(template.iconColor.opacity(0.12))
                                Image(systemName: template.iconName)
                                    .font(.system(size: 20))
                                    .foregroundStyle(template.iconColor)
                            }
                            .frame(width: 40, height: 40)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(template.name)
                                    .font(.headline)
                                    .lineLimit(1)
                                Text("\(template.category) • .\(template.suggestedExtension)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            Button {
                                manager.toggleFavorite(template: template)
                            } label: {
                                Image(systemName: manager.favorites.contains(template.id) ? "star.fill" : "star")
                                    .foregroundStyle(manager.favorites.contains(template.id) ? .yellow : .secondary)
                            }
                            .buttonStyle(.plain)
                        }

                        Text(template.description)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .lineLimit(3)
                            .padding(.top, 4)

                        Text("Estimated length: \(template.estimatedLineCount) lines")
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .padding(.top, 2)
                    }

                    Divider()

                    // Code Monospace Scrollable Preview
                    VStack(alignment: .leading, spacing: 4) {
                        Text("TEMPLATE PREVIEW")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.secondary)

                        ScrollView {
                            Text(template.content.isEmpty ? "// Empty Template File" : template.content)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(.primary)
                                .multilineTextAlignment(.leading)
                                .padding(10)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .background(Color.black.opacity(0.15))
                        .cornerRadius(8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.secondary.opacity(0.15), lineWidth: 1)
                        )
                    }
                    .frame(maxHeight: .infinity)

                    Divider()

                    // Target Settings and Filename TextField
                    VStack(alignment: .leading, spacing: 10) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("TARGET DIRECTORY")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(.secondary)
                            Text(destinationDirectory.lastPathComponent)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text("SAVE AS FILENAME")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(.secondary)

                            HStack(spacing: 4) {
                                TextField("Filename", text: $filenameInput)
                                    .textFieldStyle(.roundedBorder)
                                    .autocorrectionDisabled()
                                    .font(.subheadline)
                                    .onSubmit {
                                        if FilenameValidator.validate(filename: filenameInput, inDirectory: destinationDirectory, isFolder: isFolderCreation) == nil {
                                            executeFileCreation()
                                        }
                                    }
                            }
                        }

                        // Error output inline
                        if let error = errorMsg {
                            Text(error)
                                .font(.caption)
                                .foregroundColor(.red)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    // Bottom Buttons
                    HStack(spacing: 12) {
                        Button("Cancel") {
                            dismiss()
                        }
                        .buttonStyle(.bordered)

                        Button(action: executeFileCreation) {
                            HStack {
                                Image(systemName: "plus.circle.fill")
                                Text("Create File")
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.orange)
                        .controlSize(.large)
                        .disabled(FilenameValidator.validate(filename: filenameInput, inDirectory: destinationDirectory, isFolder: isFolderCreation) != nil)
                    }

                } else {
                    VStack(spacing: 12) {
                        Image(systemName: "doc.badge.plus")
                            .font(.system(size: 44))
                            .foregroundStyle(.tertiary)
                        Text("Select a template to configure and preview.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .padding(20)
            .frame(width: 320)
            .background(.regularMaterial)
        }
        .frame(minWidth: 920, minHeight: 620)
        .onAppear {
            manager.scanTemplates(projectURL: viewModel.projectURL)
            // Pre-select first template if none selected
            if let first = manager.templates.first {
                selectTemplate(first)
            }
        }
        // Blank creation Modal sheet overlay
        .sheet(isPresented: $showingBlankCreationSheet) {
            VStack(alignment: .leading, spacing: 16) {
                Text(blankIsFolder ? "Create New Folder" : "Create New Empty File")
                    .font(.headline)

                VStack(alignment: .leading, spacing: 6) {
                    Text(blankIsFolder ? "Folder Name" : "Filename (including extension)")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    TextField(blankIsFolder ? "My Folder" : "file.swift", text: $blankFilename)
                        .textFieldStyle(.roundedBorder)
                        .autocorrectionDisabled()
                        .onSubmit {
                            executeBlankCreation()
                        }
                }

                if let err = blankErrorMsg {
                    Text(err)
                        .font(.caption)
                        .foregroundColor(.red)
                }

                HStack {
                    Button("Cancel") {
                        showingBlankCreationSheet = false
                    }
                    .buttonStyle(.bordered)

                    Spacer()

                    Button("Create") {
                        executeBlankCreation()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                }
            }
            .padding(20)
            .frame(width: 340)
        }
    }

    // MARK: - Category Row

    @ViewBuilder
    private func categoryRow(name: String, icon: String, color: Color) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.subheadline)
                .foregroundStyle(color)
                .frame(width: 18)
            Text(name)
                .font(.subheadline)
        }
        .tag(name)
    }

    // MARK: - Grid Card UI

    @ViewBuilder
    private var emptyState: some View {
        VStack {
            Text("No Templates Discovered")
        }
    }

    @ViewBuilder
    private func templateGridCard(_ template: FileTemplate) -> some View {
        Button {
            selectTemplate(template)
        } label: {
            VStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(template.iconColor.opacity(selectedTemplate?.id == template.id ? 0.25 : 0.08))

                    Image(systemName: template.iconName)
                        .font(.system(size: 26))
                        .foregroundStyle(template.iconColor)
                }
                .frame(width: 52, height: 52)

                Text(template.name)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(selectedTemplate?.id == template.id ? .orange : .primary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .frame(height: 32)

                Text(".\(template.suggestedExtension)")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            .padding(10)
            .frame(maxWidth: .infinity, minHeight: 120)
            .background(selectedTemplate?.id == template.id ? Color.orange.opacity(0.04) : Color.clear)
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(selectedTemplate?.id == template.id ? Color.orange : Color.clear, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Favorite") {
                manager.toggleFavorite(template: template)
            }
            Button("Create Immediately") {
                selectTemplate(template)
                executeFileCreation()
            }
        }
        .onTapGesture(count: 2) {
            selectTemplate(template)
            executeFileCreation()
        }
        .onDrag {
            NSItemProvider(object: template.content as NSString)
        }
    }

    // MARK: - List Row UI

    @ViewBuilder
    private func templateListRow(_ template: FileTemplate) -> some View {
        Button {
            selectTemplate(template)
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(template.iconColor.opacity(selectedTemplate?.id == template.id ? 0.25 : 0.08))
                    Image(systemName: template.iconName)
                        .font(.headline)
                        .foregroundStyle(template.iconColor)
                }
                .frame(width: 36, height: 36)

                VStack(alignment: .leading, spacing: 2) {
                    Text(template.name)
                        .font(.subheadline.bold())
                        .foregroundStyle(selectedTemplate?.id == template.id ? .orange : .primary)
                    Text(template.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                Text(".\(template.suggestedExtension)")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .padding(.trailing, 16)
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 16)
            .background(selectedTemplate?.id == template.id ? Color.orange.opacity(0.05) : Color.clear)
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Favorite") {
                manager.toggleFavorite(template: template)
            }
            Button("Create Immediately") {
                selectTemplate(template)
                executeFileCreation()
            }
        }
        .onTapGesture(count: 2) {
            selectTemplate(template)
            executeFileCreation()
        }
        .onDrag {
            NSItemProvider(object: template.content as NSString)
        }
    }

    // MARK: - Selection & Creation Operations

    private func selectTemplate(_ template: FileTemplate) {
        selectedTemplate = template
        isFolderCreation = template.isFolder

        // Formulate suggested filename base
        let rawBase = template.name.replacingOccurrences(of: " ", with: "")
        if template.isFolder {
            filenameInput = rawBase
        } else {
            filenameInput = "\(rawBase).\(template.suggestedExtension)"
        }

        validateCurrentFilename()
    }

    private func validateCurrentFilename() {
        errorMsg = FilenameValidator.validate(filename: filenameInput, inDirectory: destinationDirectory, isFolder: isFolderCreation)
    }

    private func executeFileCreation() {
        guard let template = selectedTemplate else { return }
        let trimmed = filenameInput.trimmingCharacters(in: .whitespacesAndNewlines)
        if let err = FilenameValidator.validate(filename: trimmed, inDirectory: destinationDirectory, isFolder: isFolderCreation) {
            errorMsg = err
            return
        }

        let destinationURL = destinationDirectory.appendingPathComponent(trimmed)

        Task {
            do {
                if template.isFolder {
                    try FileManager.default.createDirectory(at: destinationURL, withIntermediateDirectories: true)
                } else {
                    // Replace placeholder __FILENAME__ in content
                    let fileBaseName = destinationURL.deletingPathExtension().lastPathComponent
                    let finalContent = template.content.replacingOccurrences(of: "__FILENAME__", with: fileBaseName)
                    try finalContent.write(to: destinationURL, atomically: true, encoding: .utf8)
                }

                // Record Usage, refresh, and select
                manager.recordUsage(template: template)
                viewModel.invalidateCache(at: destinationDirectory)
                await viewModel.refresh()
                viewModel.selectedNodeID = destinationURL.path
                dismiss()
            } catch {
                errorMsg = "Failed to create: \(error.localizedDescription)"
            }
        }
    }

    // MARK: - Blank Creation Helpers

    private func showBlankCreation(isFolder: Bool) {
        blankIsFolder = isFolder
        blankFilename = isFolder ? "New Folder" : "main.swift"
        blankErrorMsg = nil
        showingBlankCreationSheet = true
    }

    private func executeBlankCreation() {
        let trimmed = blankFilename.trimmingCharacters(in: .whitespacesAndNewlines)
        if let err = FilenameValidator.validate(filename: trimmed, inDirectory: destinationDirectory, isFolder: blankIsFolder) {
            blankErrorMsg = err
            return
        }

        let destinationURL = destinationDirectory.appendingPathComponent(trimmed)

        Task {
            do {
                if blankIsFolder {
                    try FileManager.default.createDirectory(at: destinationURL, withIntermediateDirectories: true)
                } else {
                    try "".write(to: destinationURL, atomically: true, encoding: .utf8)
                }

                viewModel.invalidateCache(at: destinationDirectory)
                await viewModel.refresh()
                viewModel.selectedNodeID = destinationURL.path
                showingBlankCreationSheet = false
                dismiss()
            } catch {
                blankErrorMsg = "Failed to create: \(error.localizedDescription)"
            }
        }
    }
}
