import Foundation
import Observation
import os
import SwiftCodePreviews
#if os(macOS)
import AppKit
#endif

@Observable
@MainActor
public final class DocumentCoordinator: Sendable {
    public static let shared = DocumentCoordinator()

    private let logger = Logger(subsystem: "com.swiftcode.app", category: "DocumentCoordinator")

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

    public var cursorPosition: Int = 0
    public var scrollPosition: Double = 0.0
    public var selection: NSRange?
    public var foldingState: [String: Bool] = [:]

    public var visualUIDocument: VisualUIDocument?
    public var lastOpenedComponent: String?

    #if os(macOS)
    public var compiledArtboardViews: [UUID: NSView] = [:]
    #else
    public var compiledArtboardViews: [UUID: Any] = [:]
    #endif
    public var compiledArtboardErrors: [UUID: String] = [:]

    public var previewSession: PreviewSession?

    public var inspectorSelection: String?

    private init() {}

    public func updateUnsavedStatus(isDirty: Bool) {
        self.unsavedChanges = isDirty
        if activeDocument != nil {
            activeDocument?.isDirty = isDirty
        }
        if let visDoc = visualUIDocument {
            visDoc.isDirty = isDirty
        }
    }
}
