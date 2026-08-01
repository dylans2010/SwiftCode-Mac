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
        // Setup initial default artboard if empty
        if scene.artboards.isEmpty {
            let rootNode = VisualComponentNode(
                type: .vStack,
                children: [
                    VisualComponentNode(type: .text, properties: ["textValue": "Welcome to Visual UI Builder"]),
                    VisualComponentNode(type: .button, properties: ["textValue": "Get Started"])
                ]
            )
            let defaultArtboard = VisualUIArtboard(name: "Home View", rootNode: rootNode)
            scene.artboards.append(defaultArtboard)
            scene.activeArtboardID = defaultArtboard.id
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
        let generator = VisualUICodeGenerator()
        let code = generator.generateCode(for: scene, targetFramework: .swiftUI)
        NotificationCenter.default.post(
            name: NSNotification.Name("com.swiftcode.visualUIEditorUpdate"),
            object: nil,
            userInfo: ["code": code]
        )
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
