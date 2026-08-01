import Foundation
import Observation
import os

/// Centralized coordinator managing editor, visual UI, and preview session synchronization
@Observable
@MainActor
public final class DocumentCoordinator: Sendable {
    public static let shared = DocumentCoordinator()

    private let logger = Logger(subsystem: "com.swiftcode.app", category: "DocumentCoordinator")

    // Active SwiftUI/Swift document under editing
    public var activeDocument: SourceFileDocument? {
        didSet {
            if let doc = activeDocument {
                self.fileURL = doc.url
                self.unsavedChanges = doc.isDirty
            } else {
                self.fileURL = nil
                self.unsavedChanges = false
            }
        }
    }

    public var fileURL: URL?
    public var projectURL: URL?
    public var unsavedChanges: Bool = false
    public var generatedMetadata: [String: String] = [:]

    // Editor state
    public var cursorPosition: Int = 0
    public var scrollPosition: Double = 0.0
    public var selection: NSRange?
    public var foldingState: [String: Bool] = [:]

    // Visual UI Builder state
    public var visualUIDocument: VisualUIDocument?
    public var lastOpenedComponent: String?

    // Preview session reference
    public var previewSession: PreviewSession?

    // Inspector Selection
    public var inspectorSelection: String?

    private init() {}

    /// Synchronizes isDirty/unsaved indicators across editor and visual designer
    public func updateUnsavedStatus(isDirty: Bool) {
        self.unsavedChanges = isDirty
        if let doc = activeDocument {
            doc.isDirty = isDirty
        }
        if let visDoc = visualUIDocument {
            visDoc.isDirty = isDirty
        }
    }
}
