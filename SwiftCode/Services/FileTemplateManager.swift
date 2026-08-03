import SwiftUI
import Combine

/// Strongly-typed file template model loaded dynamically from the filesystem.
public struct FileTemplate: Identifiable, Sendable, Hashable {
    public let id: String
    public let name: String
    public let extensionName: String
    public let icon: String
    public let colorName: String // Keep Color representation platform agnostic / serializable
    public let resourceName: String
    public let resourceExtension: String
    public let isFolder: Bool
    public let fileURL: URL?
    public let category: String

    public var idValue: String { id }

    public var color: Color {
        switch colorName.lowercased() {
        case "yellow": return .yellow
        case "teal": return .teal
        case "orange": return .orange
        case "blue": return .blue
        case "purple": return .purple
        case "red": return .red
        case "green": return .green
        case "pink": return .pink
        case "indigo": return .indigo
        case "primary": return .primary
        default: return .secondary
        }
    }

    public var defaultFilename: String {
        if isFolder {
            return "New Folder"
        }
        if id == "simple_file" {
            return "Untitled.swift"
        }
        return "Untitled.\(extensionName)"
    }

    public init(
        id: String,
        name: String,
        extensionName: String,
        icon: String,
        colorName: String,
        resourceName: String,
        resourceExtension: String,
        isFolder: Bool,
        fileURL: URL?,
        category: String
    ) {
        self.id = id
        self.name = name
        self.extensionName = extensionName
        self.icon = icon
        self.colorName = colorName
        self.resourceName = resourceName
        self.resourceExtension = resourceExtension
        self.isFolder = isFolder
        self.fileURL = fileURL
        self.category = category
    }
}

/// Directory watcher utilizing DispatchSourceFileSystemObject for real-time filesystem change observation.
public final class DirectoryWatcher: Sendable {
    private let fileDescriptor: Int32
    private let source: DispatchSourceFileSystemObject?

    public init?(url: URL, onChange: @escaping @Sendable () -> Void) {
        let fd = open(url.path, O_EVTONLY)
        guard fd >= 0 else {
            self.fileDescriptor = -1
            self.source = nil
            return nil
        }
        self.fileDescriptor = fd

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .delete, .rename],
            queue: DispatchQueue.global(qos: .default)
        )
        source.setEventHandler {
            onChange()
        }
        source.setCancelHandler {
            close(fd)
        }
        self.source = source
        source.resume()
    }

    deinit {
        source?.cancel()
    }
}

/// Loader handles robust resolution and metadata discovery for bundled & user file templates.
public final class TemplateLoader: Sendable {
    public init() {}

    public static func resolveTemplatesDirectory() -> URL? {
        let fm = FileManager.default

        // 1. App Bundle subdirectory
        if let bundleURL = Bundle.main.url(forResource: "File Templates", withExtension: nil) {
            if fm.fileExists(atPath: bundleURL.path) {
                return bundleURL
            }
        }

        // 2. Sample file path anchor
        if let sampleURL = Bundle.main.url(forResource: "CFile.c", withExtension: "txt", subdirectory: "File Templates") {
            let bundleDir = sampleURL.deletingLastPathComponent()
            if fm.fileExists(atPath: bundleDir.path) {
                return bundleDir
            }
        }

        // 3. Project disk paths
        let paths = [
            "SwiftCode/Resources/File Templates",
            "../SwiftCode/Resources/File Templates",
            "./Resources/File Templates"
        ]

        for p in paths {
            let diskURL = URL(fileURLWithPath: p)
            if fm.fileExists(atPath: diskURL.path) {
                return diskURL
            }
        }

        return nil
    }

    public func loadTemplates(from directoryURL: URL) throws -> [FileTemplate] {
        let fm = FileManager.default
        var result: [FileTemplate] = []

        let contents = try fm.contentsOfDirectory(at: directoryURL, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)

        for url in contents {
            let lastComponent = url.lastPathComponent
            guard lastComponent.hasSuffix(".txt") else { continue }

            let baseName = url.deletingPathExtension().lastPathComponent // "CFile.c"
            let pathExtension = URL(fileURLWithPath: baseName).pathExtension // "c"
            let cleanID = baseName.lowercased().replacingOccurrences(of: ".", with: "_")

            let (name, icon, colorName, category) = getTemplateAttributes(filename: baseName, ext: pathExtension)

            result.append(FileTemplate(
                id: cleanID,
                name: name,
                extensionName: pathExtension.isEmpty ? "txt" : pathExtension,
                icon: icon,
                colorName: colorName,
                resourceName: baseName,
                resourceExtension: "txt",
                isFolder: false,
                fileURL: url,
                category: category
            ))
        }

        return result.sorted { $0.name < $1.name }
    }

    private func getTemplateAttributes(filename: String, ext: String) -> (name: String, icon: String, colorName: String, category: String) {
        let lowerExt = ext.lowercased()
        let lowerName = filename.lowercased()

        if lowerName.contains("swiftui") {
            return ("SwiftUI View", "swift", "orange", "Code")
        } else if lowerName.contains("uikit") {
            return ("UIKit Controller", "swift", "blue", "Code")
        } else if lowerName.contains("appkit") {
            return ("AppKit Controller", "swift", "purple", "Code")
        } else if lowerName.contains("swiftactor") {
            return ("Swift Actor", "swift", "red", "Code")
        } else if lowerName.contains("packageswift") || lowerName.contains("package.swift") {
            return ("SPM Manifest", "shippingbox.fill", "blue", "Configs")
        } else if lowerName.contains("xctest") {
            return ("XCTest Suite", "checkmark.seal.fill", "teal", "Testing")
        } else if lowerName.contains("unittest") {
            return ("Unit Test File", "checkmark.seal.fill", "teal", "Testing")
        } else if lowerName.contains("cfile") || lowerExt == "c" {
            return ("C Source File", "chevron.left.forwardslash.chevron.right", "green", "Code")
        } else if lowerName.contains("storyboard") || lowerExt == "storyboard" {
            return ("Storyboard", "macwindow", "pink", "Code")
        } else if lowerName.contains("infoplist") || lowerName.contains("info.plist") || lowerExt == "plist" {
            return ("Info.plist File", "list.bullet.rectangle.fill", "indigo", "Configs")
        } else if lowerName.contains("entitlements") {
            return ("Entitlements", "lock.shield.fill", "red", "Configs")
        } else if lowerName.contains("shell") || lowerExt == "sh" {
            return ("Shell Script", "terminal.fill", "primary", "Scripting")
        } else if lowerName.contains("python") || lowerExt == "py" {
            return ("Python Script", "terminal.fill", "green", "Scripting")
        } else if lowerName.contains("yaml") || lowerName.contains("yml") || lowerExt == "yml" || lowerExt == "yaml" {
            return ("YAML Config", "gearshape.2.fill", "secondary", "Configs")
        } else if lowerName.contains("readme") {
            return ("Project README", "doc.text.fill", "secondary", "Docs")
        } else if lowerExt == "md" {
            return ("Markdown Doc", "doc.text.fill", "secondary", "Docs")
        } else if lowerExt == "json" {
            return ("JSON Configuration", "curlybraces.square.fill", "orange", "Configs")
        } else if lowerExt == "html" {
            return ("HTML5 Document", "globe", "blue", "Web")
        } else if lowerExt == "css" {
            return ("CSS Stylesheet", "paintbrush.fill", "pink", "Web")
        } else if lowerExt == "js" {
            return ("JavaScript File", "chevron.left.forwardslash.chevron.right", "yellow", "Web")
        }

        return ("Raw \(ext.uppercased()) File", "doc.text.fill", "secondary", "Other")
    }
}

/// Dynamic manager coordinating discovered templates, status, and active directory watchers.
@Observable
@MainActor
public final class FileTemplateManager {
    public static let shared = FileTemplateManager()

    public private(set) var templates: [FileTemplate] = []
    public private(set) var errorMessage: String? = nil
    public private(set) var isLoading = false

    private let loader = TemplateLoader()
    private var directoryWatcher: DirectoryWatcher?

    private init() {
        startWatching()
    }

    /// Automatically sets up a watcher on the resolved templates directory.
    public func startWatching() {
        guard let templatesDir = TemplateLoader.resolveTemplatesDirectory() else {
            errorMessage = "Failed to locate 'File Templates' resource directory."
            return
        }

        directoryWatcher = DirectoryWatcher(url: templatesDir) { [weak self] in
            guard let self = self else { return }
            Task { @MainActor in
                self.reloadTemplates()
            }
        }

        reloadTemplates()
    }

    /// Dynamically loads templates and handles error boundaries safely.
    public func reloadTemplates() {
        isLoading = true
        errorMessage = nil

        guard let templatesDir = TemplateLoader.resolveTemplatesDirectory() else {
            isLoading = false
            errorMessage = "File Templates directory could not be resolved."
            templates = []
            return
        }

        do {
            let loaded = try loader.loadTemplates(from: templatesDir)

            // Inject built-in virtual templates (Simple File, Clean Folder)
            let cleanFolder = FileTemplate(
                id: "clean_folder",
                name: "Clean Folder",
                extensionName: "",
                icon: "folder.fill",
                colorName: "yellow",
                resourceName: "",
                resourceExtension: "",
                isFolder: true,
                fileURL: nil,
                category: "Other"
            )

            let simpleFile = FileTemplate(
                id: "simple_file",
                name: "Simple Blank File",
                extensionName: "",
                icon: "doc.badge.plus",
                colorName: "teal",
                resourceName: "",
                resourceExtension: "",
                isFolder: false,
                fileURL: nil,
                category: "Other"
            )

            self.templates = [simpleFile, cleanFolder] + loaded
            self.isLoading = false
        } catch {
            self.isLoading = false
            self.errorMessage = "Failed to load templates: \(error.localizedDescription)"
            self.templates = []
        }
    }
}
