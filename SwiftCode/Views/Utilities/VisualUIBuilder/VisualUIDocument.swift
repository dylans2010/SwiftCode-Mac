import SwiftUI
import Observation
import os

/// Document controller managing file I/O, autosave, and standard undo/redo states
@Observable
public final class VisualUIDocument: Identifiable {
    public let id = UUID()
    public var scene: VisualUIScene
    public var filePath: String?
    public var isDirty = false

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
    }

    // MARK: - Undo & Redo System

    public func checkpoint() {
        if let data = try? JSONEncoder().encode(scene), let jsonStr = String(data: data, encoding: .utf8) {
            undoStack.append(jsonStr)
            redoStack.removeAll()
            isDirty = true
            logger.debug("Checkpoint recorded for Undo.")
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
