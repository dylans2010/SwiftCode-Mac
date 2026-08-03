import SwiftUI
import AppKit

public struct FileTemplatesView: View {
    @Environment(\.dismiss) private var dismiss
    let viewModel: ProjectTreeViewModel

    @State private var selectedItem: FileTemplate?
    @State private var filename: String = ""
    @State private var errorMsg: String?
    @State private var searchText: String = ""
    @State private var selectedCategory: String = "All"
    @State private var previewContent: String = ""

    // Observe the centralized FileTemplateManager
    private var templateManager: FileTemplateManager {
        FileTemplateManager.shared
    }

    let categories = ["All", "Code", "Web", "Configs", "Scripting", "Testing", "Docs", "Other"]

    public init(viewModel: ProjectTreeViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("New File / Folder Template")
                        .font(.headline)
                        .fontWeight(.bold)
                    Text("Select a professional starter file template or add a blank new file.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Cancel") {
                    dismiss()
                }
                .buttonStyle(.bordered)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .background(.thinMaterial)

            Divider()

            if let error = templateManager.errorMessage {
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 40))
                        .foregroundColor(.orange)
                    Text("Template Discovery Failure")
                        .font(.headline)
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                    Button("Reload Templates") {
                        templateManager.reloadTemplates()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.regularMaterial)
            } else if templateManager.isLoading {
                VStack(spacing: 16) {
                    ProgressView()
                    Text("Loading Templates...")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.regularMaterial)
            } else {
                HStack(spacing: 0) {
                    // Left Panel: Template List & Selection
                    VStack(spacing: 0) {
                        // Search & Categories Bar
                        VStack(spacing: 8) {
                            HStack(spacing: 6) {
                                Image(systemName: "magnifyingglass")
                                    .foregroundStyle(.secondary)
                                TextField("Search templates...", text: $searchText)
                                    .textFieldStyle(.plain)
                                    .font(.subheadline)
                                if !searchText.isEmpty {
                                    Button {
                                        searchText = ""
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .foregroundColor(.secondary)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(6)
                            .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))

                            // Segmented-style category picker (custom ScrollView)
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 6) {
                                    ForEach(categories, id: \.self) { cat in
                                        Button {
                                            selectedCategory = cat
                                        } label: {
                                            Text(cat)
                                                .font(.caption)
                                                .padding(.horizontal, 8)
                                                .padding(.vertical, 4)
                                                .background(selectedCategory == cat ? Color.orange.opacity(0.15) : Color.clear)
                                                .foregroundStyle(selectedCategory == cat ? Color.orange : Color.primary)
                                                .cornerRadius(6)
                                                .overlay(
                                                    RoundedRectangle(cornerRadius: 6)
                                                        .stroke(selectedCategory == cat ? Color.orange : Color.secondary.opacity(0.2), lineWidth: 1)
                                                )
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                        }
                        .padding(12)
                        .background(.ultraThinMaterial)

                        Divider()

                        // Scrollable Template Grid
                        ScrollView {
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 110, maximum: 130), spacing: 10)], spacing: 10) {
                                ForEach(filteredTemplates) { item in
                                    Button {
                                        selectedItem = item
                                        filename = item.defaultFilename
                                        loadPreviewContent(for: item)
                                    } label: {
                                        VStack(spacing: 8) {
                                            ZStack {
                                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                                    .fill(item.color.opacity(selectedItem?.id == item.id ? 0.25 : 0.08))
                                                Image(systemName: item.icon)
                                                    .font(.system(size: 20))
                                                    .foregroundStyle(item.color)
                                            }
                                            .frame(width: 42, height: 42)

                                            Text(item.name)
                                                .font(.system(size: 11, weight: .semibold))
                                                .foregroundStyle(selectedItem?.id == item.id ? .orange : .primary)
                                                .multilineTextAlignment(.center)
                                                .lineLimit(2)
                                                .frame(height: 28)
                                        }
                                        .padding(8)
                                        .frame(maxWidth: .infinity, minHeight: 88)
                                        .background(selectedItem?.id == item.id ? Color.orange.opacity(0.04) : Color.clear)
                                        .cornerRadius(10)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                                .stroke(selectedItem?.id == item.id ? Color.orange : Color.clear, lineWidth: 1.5)
                                        )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(12)
                        }
                    }
                    .frame(width: 320)

                    Divider()

                    // Right Panel: Split into Preview Code & Configuration details
                    VStack(spacing: 0) {
                        if let item = selectedItem {
                            // Top Section: Code Preview Pane
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Template Preview")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 16)
                                    .padding(.top, 12)

                                ScrollView {
                                    Text(previewContent)
                                        .font(.system(.caption, design: .monospaced))
                                        .foregroundStyle(.primary)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(12)
                                        .background(Color.black.opacity(0.15))
                                        .cornerRadius(8)
                                }
                                .padding(.horizontal, 16)
                            }
                            .frame(maxHeight: .infinity)

                            Divider()

                            // Bottom Section: Configuration details & Actions
                            VStack(alignment: .leading, spacing: 12) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(item.isFolder ? "Folder Name" : "Filename")
                                        .font(.caption.weight(.medium))
                                        .foregroundStyle(.secondary)

                                    TextField(item.isFolder ? "New Folder" : "filename.swift", text: $filename)
                                        .textFieldStyle(.roundedBorder)
                                        .autocorrectionDisabled()
                                }

                                if let error = errorMsg {
                                    Text(error)
                                        .font(.caption)
                                        .foregroundColor(.red)
                                        .fixedSize(horizontal: false, vertical: true)
                                }

                                Button(action: createTemplate) {
                                    HStack {
                                        Image(systemName: "plus.circle.fill")
                                        Text(item.isFolder ? "Create Folder" : "Create File")
                                    }
                                    .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.large)
                                .tint(.orange)
                                .disabled(filename.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            }
                            .padding(16)
                            .background(.ultraThinMaterial)
                        } else {
                            VStack(spacing: 12) {
                                Image(systemName: "doc.badge.plus")
                                    .font(.system(size: 40))
                                    .foregroundStyle(.tertiary)
                                Text("Select a template to configure & create")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .background(.regularMaterial)
                }
            }
        }
        .frame(width: 740, height: 480)
        .onAppear {
            templateManager.reloadTemplates()
            if let first = templateManager.templates.first {
                selectedItem = first
                filename = first.defaultFilename
                loadPreviewContent(for: first)
            }
        }
        .onChange(of: templateManager.templates) { _, newTemplates in
            if selectedItem == nil, let first = newTemplates.first {
                selectedItem = first
                filename = first.defaultFilename
                loadPreviewContent(for: first)
            }
        }
    }

    private var filteredTemplates: [FileTemplate] {
        templateManager.templates.filter { item in
            // Search text filter
            let matchSearch: Bool
            if searchText.isEmpty {
                matchSearch = true
            } else {
                matchSearch = item.name.localizedCaseInsensitiveContains(searchText) ||
                              item.extensionName.localizedCaseInsensitiveContains(searchText)
            }

            // Category filter
            let matchCategory: Bool
            if selectedCategory == "All" {
                matchCategory = true
            } else {
                matchCategory = item.category == selectedCategory
            }

            return matchSearch && matchCategory
        }
    }

    private func loadPreviewContent(for item: FileTemplate) {
        if item.isFolder {
            previewContent = "/* Empty Folder Directory */"
            return
        }

        if item.id == "simple_file" {
            previewContent = "/* Empty File - Custom name and extension */"
            return
        }

        guard let fileURL = item.fileURL else {
            previewContent = "/* No source template content */"
            return
        }

        Task {
            do {
                let content = try String(contentsOf: fileURL, encoding: .utf8)
                await MainActor.run {
                    self.previewContent = content
                }
            } catch {
                await MainActor.run {
                    self.previewContent = "/* Failed to load template preview contents */"
                }
            }
        }
    }

    private func createTemplate() {
        guard let item = selectedItem else { return }
        let trimmedName = filename.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }

        guard let projectURL = viewModel.projectURL else {
            errorMsg = "No active project URL."
            return
        }

        // Determine destination URL
        // If a node is currently selected and is a folder, create inside it; otherwise create in project root.
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

        let destinationURL = targetDir.appendingPathComponent(trimmedName)

        if FileManager.default.fileExists(atPath: destinationURL.path) {
            errorMsg = "A file or folder already exists with this name."
            return
        }

        Task {
            do {
                if item.isFolder {
                    try FileManager.default.createDirectory(at: destinationURL, withIntermediateDirectories: true)
                } else {
                    var content = ""
                    if let fileURL = item.fileURL {
                        content = try String(contentsOf: fileURL, encoding: .utf8)
                    }
                    try content.write(to: destinationURL, atomically: true, encoding: .utf8)
                }

                viewModel.invalidateCache(at: targetDir)
                await viewModel.refresh(bypassDebounce: true)
                viewModel.selectedNodeID = destinationURL.path
                dismiss()
            } catch {
                errorMsg = "Failed to create: \(error.localizedDescription)"
            }
        }
    }
}
