import Foundation
import os

private let logger = Logger(subsystem: "com.swiftcode.FileAgentHelper", category: "FileAgentHelper")

public struct AgentFileContext: Codable, Sendable, Identifiable, Equatable {
    public var id: UUID
    public let filename: String
    public let `extension`: String
    public let mimeType: String
    public let size: Int64
    public let base64Content: String

    public init(id: UUID = UUID(), filename: String, `extension`: String, mimeType: String, size: Int64, base64Content: String) {
        self.id = id
        self.filename = filename
        self.extension = `extension`
        self.mimeType = mimeType
        self.size = size
        self.base64Content = base64Content
    }
}

public final class FileAgentHelper {

    // Prevent initialization
    private init() {}

    /// Converts a local file URL into an AI-readable structured file context.
    /// Performs operations in a background thread to ensure no UI freeze.
    public static func processFile(at url: URL) async throws -> AgentFileContext {
        logger.log("[processFile] Initiating background processing for file: \(url.lastPathComponent)")

        return try await Task.detached(priority: .userInitiated) {
            let fm = FileManager.default
            let path = url.path

            // 1. Safe existence check
            guard fm.fileExists(atPath: path) else {
                throw NSError(domain: "FileAgentHelper", code: 404, userInfo: [NSLocalizedDescriptionKey: "File not found at: \(path)"])
            }

            // 2. Reject video formats
            let ext = url.pathExtension.lowercased()
            let videoExtensions = ["mp4", "mkv", "mov", "avi", "webm", "flv", "m4v", "wmv"]
            if videoExtensions.contains(ext) {
                throw NSError(domain: "FileAgentHelper", code: 415, userInfo: [NSLocalizedDescriptionKey: "Video formats are not supported for AI context insertion."])
            }

            // 3. Memory protection size checking (limit to 10MB to prevent out-of-memory or pipeline crashes)
            let attributes = try fm.attributesOfItem(atPath: path)
            let size = (attributes[.size] as? Int64) ?? 0
            let sizeLimit: Int64 = 10 * 1024 * 1024 // 10MB
            guard size <= sizeLimit else {
                throw NSError(domain: "FileAgentHelper", code: 413, userInfo: [NSLocalizedDescriptionKey: "File '\(url.lastPathComponent)' size (\(size) bytes) exceeds the memory safety limit of 10MB."])
            }

            // 4. Handle security scoped bookmarks for native file dialog URLs
            let isSecurityScoped = url.startAccessingSecurityScopedResource()
            defer {
                if isSecurityScoped {
                    url.stopAccessingSecurityScopedResource()
                }
            }

            // 5. Binary content reading and Base64 conversion
            let data = try Data(contentsOf: url, options: .mappedIfSafe)
            let base64 = data.base64EncodedString()
            let mime = detectMimeType(for: url)

            logger.log("[processFile] Successfully processed \(url.lastPathComponent) (Size: \(size) bytes, MIME: \(mime))")

            return AgentFileContext(
                filename: url.lastPathComponent,
                extension: url.pathExtension,
                mimeType: mime,
                size: size,
                base64Content: base64
            )
        }.value
    }

    /// Maps a URL to its matching MIME type cleanly and robustly.
    private static func detectMimeType(for url: URL) -> String {
        let ext = url.pathExtension.lowercased()
        switch ext {
        case "swift": return "text/x-swift"
        case "h", "m": return "text/x-objc"
        case "json": return "application/json"
        case "xml": return "application/xml"
        case "plist": return "application/xml"
        case "txt", "md": return "text/plain"
        case "pdf": return "application/pdf"
        case "png": return "image/png"
        case "jpg", "jpeg": return "image/jpeg"
        case "gif": return "image/gif"
        case "zip": return "application/zip"
        case "tar": return "application/x-tar"
        case "gz": return "application/gzip"
        case "html", "htm": return "text/html"
        case "css": return "text/css"
        case "js": return "application/javascript"
        default: return "application/octet-stream"
        }
    }
}
