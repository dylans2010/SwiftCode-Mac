import SwiftUI
import Observation
import os

/// Document controller managing file I/O, autosave, and standard undo/redo states
@Observable
@MainActor
public final class VisualUIDocument: Identifiable {
    public let id = UUID()
    public var scene: VisualUIScene
    public var filePath: String?
    public var isDirty = false {
        didSet {
            // Keep DocumentCoordinator in sync
            let dirty = isDirty
            Task { @MainActor in
                DocumentCoordinator.shared.updateUnsavedStatus(isDirty: dirty)
            }
        }
    }

    // Undo / Redo Stacks
    private var undoStack: [String] = [] // Encoded JSON state representations
    private var redoStack: [String] = []

    private let logger = Logger(subsystem: "com.swiftcode.visualuibuilder", category: "VisualUIDocument")

    public init(scene: VisualUIScene = VisualUIScene()) {
        self.scene = scene

        let rootNode = VisualComponentNode(type: .vStack)
        let defaultArtboard = VisualUIArtboard(name: "Default", deviceFrame: "iPhone 16 Pro", rootNode: rootNode)

        let simNode = VisualComponentNode(type: .vStack)
        let simulatorArtboard = VisualUIArtboard(name: "Simulator", deviceFrame: "iPhone 16 Pro", rootNode: simNode)

        if scene.artboards.isEmpty {
            scene.artboards.append(defaultArtboard)
            scene.artboards.append(simulatorArtboard)
            scene.activeArtboardID = defaultArtboard.id
        } else {
            // Ensure "Default" artboard is always present and first
            if !scene.artboards.contains(where: { $0.name == "Default" }) {
                scene.artboards.insert(defaultArtboard, at: 0)
            }
            // Ensure "Simulator" artboard is always present and second
            if !scene.artboards.contains(where: { $0.name == "Simulator" }) {
                let idx = scene.artboards.firstIndex(where: { $0.name == "Default" }) ?? 0
                scene.artboards.insert(simulatorArtboard, at: idx + 1)
            }
        }
        startListeningToCodeSync()
    }

    public func startListeningToCodeSync() {
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("com.swiftcode.visualUIBuilderSync"),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self = self, let code = notification.userInfo?["code"] as? String else { return }
            self.synchronizeFromCode(code)
        }
    }

    public func propagateToEditor() {
        // No-op. The Preview Engine and Visual UI Builder do not automatically generate or propagate SwiftUI source code.
    }

    public func synchronizeFromCode(_ code: String) {
        // Safe regex matching Text("...")
        let pattern = #"Text\(\"([^\"]+)\"\)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return }

        let nsRange = NSRange(code.startIndex..<code.endIndex, in: code)
        let matches = regex.matches(in: code, options: [], range: nsRange)

        var extractedTexts: [String] = []
        for match in matches {
            if let range = Range(match.range(at: 1), in: code) {
                extractedTexts.append(String(code[range]))
            }
        }

        // Apply extracted texts back to the document's nodes (matching type: .text or .button) sequentially!
        guard !extractedTexts.isEmpty else { return }

        // Depth-first traversal of all nodes and update properties
        var index = 0
        func updateNodesRecursively(_ node: VisualComponentNode) {
            if node.type == .text || node.type == .button {
                if index < extractedTexts.count {
                    node.properties["textValue"] = extractedTexts[index]
                    index += 1
                }
            }
            for child in node.children {
                updateNodesRecursively(child)
            }
        }

        for artboard in scene.artboards {
            updateNodesRecursively(artboard.rootNode)
        }

        // Also check for padding values e.g. .padding(12)
        let paddingPattern = #"\.padding\((\d+)\)"#
        if let paddingRegex = try? NSRegularExpression(pattern: paddingPattern, options: []) {
            let paddingMatches = paddingRegex.matches(in: code, options: [], range: nsRange)
            var extractedPaddings: [String] = []
            for match in paddingMatches {
                if let range = Range(match.range(at: 1), in: code) {
                    extractedPaddings.append(String(code[range]))
                }
            }

            var pIndex = 0
            func updatePaddingsRecursively(_ node: VisualComponentNode) {
                if pIndex < extractedPaddings.count {
                    node.properties["padding"] = extractedPaddings[pIndex]
                    pIndex += 1
                }
                for child in node.children {
                    updatePaddingsRecursively(child)
                }
            }

            for artboard in scene.artboards {
                updatePaddingsRecursively(artboard.rootNode)
            }
        }

        // Mark dirty to trigger UI updates
        self.isDirty = true
        logger.info("Synchronized edits from editor back to Visual UI Builder nodes.")
    }

    // MARK: - Undo & Redo System

    public func checkpoint() {
        if let data = try? JSONEncoder().encode(scene), let jsonStr = String(data: data, encoding: .utf8) {
            undoStack.append(jsonStr)
            redoStack.removeAll()
            isDirty = true
            logger.debug("Checkpoint recorded for Undo.")
            propagateToEditor()
        }
    }

    public func undo() {
        guard !undoStack.isEmpty else { return }
        if let currentData = try? JSONEncoder().encode(scene), let currentJson = String(data: currentData, encoding: .utf8) {
            redoStack.append(currentJson)
        }
        let previousJson = undoStack.removeLast()
        if let data = previousJson.data(using: .utf8),
           let restoredScene = try? JSONDecoder().decode(VisualUIScene.self, from: data) {
            self.scene = restoredScene
            isDirty = true
            logger.info("Executed Undo.")
            propagateToEditor()
        }
    }

    public func redo() {
        guard !redoStack.isEmpty else { return }
        if let currentData = try? JSONEncoder().encode(scene), let currentJson = String(data: currentData, encoding: .utf8) {
            undoStack.append(currentJson)
        }
        let nextJson = redoStack.removeLast()
        if let data = nextJson.data(using: .utf8),
           let restoredScene = try? JSONDecoder().decode(VisualUIScene.self, from: data) {
            self.scene = restoredScene
            isDirty = true
            logger.info("Executed Redo.")
            propagateToEditor()
        }
    }

    public var canUndo: Bool {
        !undoStack.isEmpty
    }

    public var canRedo: Bool {
        !redoStack.isEmpty
    }

    // MARK: - File Management

    public func save(to path: String) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        let data = try encoder.encode(scene)
        try data.write(to: URL(fileURLWithPath: path), options: .atomic)
        self.filePath = path
        self.isDirty = false
        logger.info("Saved Visual UI Document to path: \(path)")
    }

    public func load(from path: String) throws {
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        let decodedScene = try JSONDecoder().decode(VisualUIScene.self, from: data)
        self.scene = decodedScene
        self.filePath = path
        self.isDirty = false
        self.undoStack.removeAll()
        self.redoStack.removeAll()
        logger.info("Loaded Visual UI Document from path: \(path)")
    }

    public func autosave() {
        guard isDirty, let path = filePath else { return }
        do {
            try save(to: path)
            logger.info("Autosave completed successfully.")
        } catch {
            logger.error("Autosave failed: \(error.localizedDescription)")
        }
    }
}

// MARK: - Saved Artboard Model

@Observable
public final class SavedArtboard: Identifiable, Codable, Hashable {
    public let id: UUID
    public var name: String
    public var layout: VisualUIArtboard
    public var tags: [String]
    public var category: String
    public var isFavorite: Bool
    public var creationDate: Date
    public var lastModifiedDate: Date
    public var previewConfigDevice: String
    public var isDarkMode: Bool

    public init(
        id: UUID = UUID(),
        name: String,
        layout: VisualUIArtboard,
        tags: [String] = [],
        category: String = "Uncategorized",
        isFavorite: Bool = false,
        creationDate: Date = Date(),
        lastModifiedDate: Date = Date(),
        previewConfigDevice: String = "iPhone 16 Pro",
        isDarkMode: Bool = false
    ) {
        self.id = id
        self.name = name
        self.layout = layout
        self.tags = tags
        self.category = category
        self.isFavorite = isFavorite
        self.creationDate = creationDate
        self.lastModifiedDate = lastModifiedDate
        self.previewConfigDevice = previewConfigDevice
        self.isDarkMode = isDarkMode
    }

    enum CodingKeys: CodingKey {
        case id, name, layout, tags, category, isFavorite, creationDate, lastModifiedDate, previewConfigDevice, isDarkMode
    }

    public required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        layout = try container.decode(VisualUIArtboard.self, forKey: .layout)
        name = try container.decode(String.self, forKey: .name)
        tags = try container.decode([String].self, forKey: .tags)
        category = try container.decode(String.self, forKey: .category)
        isFavorite = try container.decode(Bool.self, forKey: .isFavorite)
        creationDate = try container.decode(Date.self, forKey: .creationDate)
        lastModifiedDate = try container.decode(Date.self, forKey: .lastModifiedDate)
        previewConfigDevice = try container.decode(String.self, forKey: .previewConfigDevice)
        isDarkMode = try container.decode(Bool.self, forKey: .isDarkMode)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(layout, forKey: .layout)
        try container.encode(name, forKey: .name)
        try container.encode(tags, forKey: .tags)
        try container.encode(category, forKey: .category)
        try container.encode(isFavorite, forKey: .isFavorite)
        try container.encode(creationDate, forKey: .creationDate)
        try container.encode(lastModifiedDate, forKey: .lastModifiedDate)
        try container.encode(previewConfigDevice, forKey: .previewConfigDevice)
        try container.encode(isDarkMode, forKey: .isDarkMode)
    }

    public static func == (lhs: SavedArtboard, rhs: SavedArtboard) -> Bool {
        lhs.id == rhs.id
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

// MARK: - Saved Artboard Manager

@MainActor
@Observable
public final class SavedArtboardManager {
    public static let shared = SavedArtboardManager()

    public var savedArtboards: [SavedArtboard] = []

    private init() {
        loadSavedArtboards()
    }

    public func loadSavedArtboards() {
        if let data = UserDefaults.standard.data(forKey: "com.swiftcode.visualUIBuilder.savedArtboards") {
            do {
                self.savedArtboards = try JSONDecoder().decode([SavedArtboard].self, from: data)
            } catch {
                self.savedArtboards = []
            }
        } else {
            self.savedArtboards = []
        }
    }

    public func saveAll() {
        do {
            let data = try JSONEncoder().encode(savedArtboards)
            UserDefaults.standard.set(data, forKey: "com.swiftcode.visualUIBuilder.savedArtboards")
        } catch {
            print("Failed to save artboards: \(error)")
        }
    }

    public func createArtboard(name: String, artboard: VisualUIArtboard, category: String = "Uncategorized") {
        // Deep copy root node so it's fully isolated
        let copiedLayout = VisualUIArtboard(
            name: artboard.name,
            deviceFrame: artboard.deviceFrame,
            rootNode: artboard.rootNode.duplicated()
        )
        let saved = SavedArtboard(name: name, layout: copiedLayout, category: category)
        savedArtboards.append(saved)
        saveAll()
    }

    public func deleteArtboard(id: UUID) {
        savedArtboards.removeAll { $0.id == id }
        saveAll()
    }

    public func duplicateArtboard(id: UUID) {
        if let original = savedArtboards.first(where: { $0.id == id }) {
            // Prevent duplicate of Default or Simulator artboards
            if original.name == "Default" || original.name == "Simulator" || original.layout.name == "Default" || original.layout.name == "Simulator" { return }
            let dupLayout = VisualUIArtboard(
                name: "\(original.layout.name) Copy",
                deviceFrame: original.layout.deviceFrame,
                rootNode: original.layout.rootNode.duplicated()
            )
            let duplicated = SavedArtboard(
                name: "\(original.name) Copy",
                layout: dupLayout,
                tags: original.tags,
                category: original.category,
                isFavorite: original.isFavorite,
                previewConfigDevice: original.previewConfigDevice,
                isDarkMode: original.isDarkMode
            )
            savedArtboards.append(duplicated)
            saveAll()
        }
    }
}
