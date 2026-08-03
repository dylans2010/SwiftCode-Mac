import SwiftUI
import AppKit

public struct TemplateItem: Identifiable {
    public let id: String
    public let name: String
    public let icon: String
    public let color: Color
    public let defaultFilename: String
    public let resourceName: String
    public let resourceExtension: String
    public let isFolder: Bool
}

public struct FileTemplatesView: View {
    @Environment(\.dismiss) private var dismiss
    let viewModel: ProjectTreeViewModel

    @State private var selectedItem: TemplateItem?
    @State private var filename: String = ""
    @State private var errorMsg: String?

    let templates: [TemplateItem] = [
        TemplateItem(id: "swiftui", name: "SwiftUI View", icon: "swift", color: .orange, defaultFilename: "ContentView.swift", resourceName: "SwiftUI.swift", resourceExtension: "txt", isFolder: false),
        TemplateItem(id: "uikit", name: "UIKit ViewController", icon: "swift", color: .blue, defaultFilename: "ViewController.swift", resourceName: "UIKit.swift", resourceExtension: "txt", isFolder: false),
        TemplateItem(id: "appkit", name: "AppKit ViewController", icon: "swift", color: .purple, defaultFilename: "ViewController.swift", resourceName: "AppKit.swift", resourceExtension: "txt", isFolder: false),
        TemplateItem(id: "cfile", name: "C File", icon: "chevron.left.forwardslash.chevron.right", color: .green, defaultFilename: "main.c", resourceName: "CFile.c", resourceExtension: "txt", isFolder: false),
        TemplateItem(id: "storyboard", name: "Storyboard", icon: "macwindow", color: .pink, defaultFilename: "Main.storyboard", resourceName: "Storyboard.storyboard", resourceExtension: "txt", isFolder: false),
        TemplateItem(id: "xctest", name: "XCTest Unit Test", icon: "checkmark.seal.fill", color: .teal, defaultFilename: "MyTests.swift", resourceName: "XCTestUnitTest.swift", resourceExtension: "txt", isFolder: false),
        TemplateItem(id: "markdown", name: "Markdown File", icon: "doc.text.fill", color: .secondary, defaultFilename: "README.md", resourceName: "Markdown.md", resourceExtension: "txt", isFolder: false),
        TemplateItem(id: "infoplist", name: "Info.plist", icon: "list.bullet.rectangle.fill", color: .indigo, defaultFilename: "Info.plist", resourceName: "InfoPlist.plist", resourceExtension: "txt", isFolder: false),
        TemplateItem(id: "entitlements", name: "Entitlements", icon: "lock.shield.fill", color: .red, defaultFilename: "App.entitlements", resourceName: "Entitlements.entitlements", resourceExtension: "txt", isFolder: false),
        TemplateItem(id: "shell", name: "Shell Script", icon: "terminal.fill", color: .primary, defaultFilename: "script.sh", resourceName: "ShellScript.sh", resourceExtension: "txt", isFolder: false),
        TemplateItem(id: "folder", name: "Clean Folder", icon: "folder.fill", color: .yellow, defaultFilename: "New Folder", resourceName: "", resourceExtension: "", isFolder: true)
    ]

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
                    Text("Select a professional starter file template to create.")
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
            .padding(.vertical, 16)
            .background(.thinMaterial)

            Divider()

            HStack(spacing: 0) {
                // Left Panel: Template Grid List
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 110, maximum: 130), spacing: 12)], spacing: 12) {
                        ForEach(templates) { item in
                            Button {
                                selectedItem = item
                                filename = item.defaultFilename
                            } label: {
                                VStack(spacing: 8) {
                                    ZStack {
                                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                                            .fill(item.color.opacity(selectedItem?.id == item.id ? 0.25 : 0.08))
                                        Image(systemName: item.icon)
                                            .font(.system(size: 24))
                                            .foregroundStyle(item.color)
                                    }
                                    .frame(width: 48, height: 48)

                                    Text(item.name)
                                        .font(.caption.weight(.medium))
                                        .foregroundStyle(selectedItem?.id == item.id ? .orange : .primary)
                                        .multilineTextAlignment(.center)
                                        .lineLimit(2)
                                }
                                .padding(8)
                                .frame(maxWidth: .infinity, minHeight: 90)
                                .background(selectedItem?.id == item.id ? Color.orange.opacity(0.05) : Color.clear)
                                .cornerRadius(12)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .stroke(selectedItem?.id == item.id ? Color.orange : Color.clear, lineWidth: 1.5)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(16)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                Divider()

                // Right Panel: Configuration & Input
                VStack(alignment: .leading, spacing: 16) {
                    if let item = selectedItem {
                        Text("Configuration")
                            .font(.subheadline.bold())
                            .foregroundStyle(.secondary)

                        VStack(alignment: .leading, spacing: 6) {
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

                        Spacer()

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
                    } else {
                        VStack(spacing: 12) {
                            Image(systemName: "doc.badge.plus")
                                .font(.system(size: 36))
                                .foregroundStyle(.tertiary)
                            Text("Select a Template")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .padding(20)
                .frame(width: 240)
                .background(.regularMaterial)
            }
        }
        .frame(width: 620, height: 440)
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
                    if !item.resourceName.isEmpty {
                        if let templateURL = Bundle.main.url(forResource: item.resourceName, withExtension: item.resourceExtension, subdirectory: "File Templates") {
                            content = try String(contentsOf: templateURL, encoding: .utf8)
                        } else {
                            // Fallback read from Resources directory directly if Bundle.main is not ready in tests/sandbox
                            let resourceDir = projectURL.appendingPathComponent("SwiftCode/Resources/File Templates")
                            let directURL = resourceDir.appendingPathComponent("\(item.resourceName).\(item.resourceExtension)")
                            if FileManager.default.fileExists(atPath: directURL.path) {
                                content = try String(contentsOf: directURL, encoding: .utf8)
                            }
                        }
                    }
                    try content.write(to: destinationURL, atomically: true, encoding: .utf8)
                }

                viewModel.invalidateCache(at: targetDir)
                await viewModel.refresh()
                viewModel.selectedNodeID = destinationURL.path
                dismiss()
            } catch {
                errorMsg = "Failed to create: \(error.localizedDescription)"
            }
        }
    }
}
