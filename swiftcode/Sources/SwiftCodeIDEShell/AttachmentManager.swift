// AttachmentManager.swift
//
// Ported from Legacy `SwiftCode/Views/Utilities/NSPersonalDocumentation/Managers/AttachmentManager.swift` (SwiftCode-Mac migration, Views/UI worklist).
// Worklist verdict: PARTIAL.
// Missing behaviour ported: fileExists(relativePath:) attachment existence check
// Static port only — no Swift toolchain here; build verification pending on Dylan's Mac.
import Foundation
import SwiftData

public actor AttachmentManager {
    private let projectURL: URL

    public init(projectURL: URL) {
        self.projectURL = projectURL
    }

    public func saveAttachment(fileURL: URL, name: String) throws -> String {
        let attachmentsDir = projectURL.appendingPathComponent("Attachments")
        try FileManager.default.createDirectory(at: attachmentsDir, withIntermediateDirectories: true)

        let destinationURL = attachmentsDir.appendingPathComponent(name)
        if FileManager.default.fileExists(atPath: destinationURL.path) {
            try FileManager.default.removeItem(at: destinationURL)
        }

        try FileManager.default.copyItem(at: fileURL, to: destinationURL)
        return "Attachments/\(name)"
    }

    public func fileExists(relativePath: String) -> Bool {
        let fullURL = projectURL.appendingPathComponent(relativePath)
        return FileManager.default.fileExists(atPath: fullURL.path)
    }
}
