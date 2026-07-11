import Foundation
import Observation
import SwiftUI

@Observable
@MainActor
public class EditorViewModel {
    public var activeDocument: SourceFileDocument?
    public var openDocuments: [SourceFileDocument] = []
    public var selectedTabID: UUID?
    public var tokenizedLines: [TokenizedLine] = []

    public init() {}

    public func openFile(url: URL) async {
        if let existing = openDocuments.first(where: { $0.url == url }) {
            // SAFETY: Clear tokens before switching document to avoid stale highlighting
            tokenizedLines = []
            activeDocument = existing
            selectedTabID = existing.id
            await tokenize()
            return
        }

        do {
            tokenizedLines = []
            let isXcodeProj = url.pathExtension == "xcodeproj" || url.lastPathComponent == "project.pbxproj"
            let content: String
            if isXcodeProj {
                content = ""
            } else {
                content = try await TextBufferEngine.shared.load(url: url)
            }
            let doc = SourceFileDocument(url: url, content: content, lastDiskModificationDate: Date())
            openDocuments.append(doc)
            activeDocument = doc
            selectedTabID = doc.id
            await tokenize()
        } catch {
            LoggingTool.error("Failed to open file: \(error)")
        }
    }

    public func saveActiveDocument() async {
        guard let doc = activeDocument else { return }
        do {
            try await TextBufferEngine.shared.save(content: doc.content, to: doc.url)
            if let index = openDocuments.firstIndex(where: { $0.id == doc.id }) {
                openDocuments[index].isDirty = false
            }
            activeDocument?.isDirty = false
        } catch {
            LoggingTool.error("Failed to save file: \(error)")
        }
    }

    public func updateContent(_ content: String) {
        activeDocument?.content = content
        activeDocument?.isDirty = true
        Task {
            await tokenize()
        }
    }

    private func tokenize() async {
        // Highlighting is now handled asynchronously by CodeRenderEngine directly inside NativeTextView
    }

    public func updateActiveConfigurationURLs(for project: Project) async {
        let newPlist = ProjectResolutionService.shared.resolveInfoPlist(for: project)
        let newEntitlements = ProjectResolutionService.shared.resolveEntitlements(for: project)

        // We iterate and update the open documents to show the correct resolved path or unresolved dummy URL
        var updatedDocuments: [SourceFileDocument] = []
        for doc in openDocuments {
            let isPlist = doc.url.pathExtension == "plist" || doc.url.lastPathComponent == "Info.plist" || doc.url.lastPathComponent.contains("Unresolved-Info")
            let isEnt = doc.url.pathExtension == "entitlements" || doc.url.lastPathComponent.contains("Unresolved.entitlements")

            if isPlist {
                let targetURL = newPlist ?? project.directoryURL.appendingPathComponent("Unresolved-Info.plist")
                if doc.url != targetURL {
                    var newDoc = doc
                    newDoc.url = targetURL
                    if newPlist != nil {
                        if let content = try? await TextBufferEngine.shared.load(url: targetURL) {
                            newDoc.content = content
                        }
                    } else {
                        newDoc.content = ""
                    }
                    updatedDocuments.append(newDoc)
                } else {
                    updatedDocuments.append(doc)
                }
            } else if isEnt {
                let targetURL = newEntitlements ?? project.directoryURL.appendingPathComponent("Unresolved.entitlements")
                if doc.url != targetURL {
                    var newDoc = doc
                    newDoc.url = targetURL
                    if newEntitlements != nil {
                        if let content = try? await TextBufferEngine.shared.load(url: targetURL) {
                            newDoc.content = content
                        }
                    } else {
                        newDoc.content = ""
                    }
                    updatedDocuments.append(newDoc)
                } else {
                    updatedDocuments.append(doc)
                }
            } else {
                updatedDocuments.append(doc)
            }
        }

        self.openDocuments = updatedDocuments

        // Update active document reference if its URL matches plist/entitlements
        if let active = activeDocument {
            let isActivePlist = active.url.pathExtension == "plist" || active.url.lastPathComponent == "Info.plist" || active.url.lastPathComponent.contains("Unresolved-Info")
            let isActiveEnt = active.url.pathExtension == "entitlements" || active.url.lastPathComponent.contains("Unresolved.entitlements")

            if isActivePlist {
                let targetURL = newPlist ?? project.directoryURL.appendingPathComponent("Unresolved-Info.plist")
                if let updated = openDocuments.first(where: { $0.url == targetURL }) {
                    self.activeDocument = updated
                    self.selectedTabID = updated.id
                }
            } else if isActiveEnt {
                let targetURL = newEntitlements ?? project.directoryURL.appendingPathComponent("Unresolved.entitlements")
                if let updated = openDocuments.first(where: { $0.url == targetURL }) {
                    self.activeDocument = updated
                    self.selectedTabID = updated.id
                }
            }
        }
    }
}
