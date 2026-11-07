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
