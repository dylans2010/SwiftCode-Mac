import Foundation
import WebKit

@MainActor
public final class LivePreviewService: ObservableObject {
    public static let shared = LivePreviewService()

    @Published public var previewURL: URL?
    private var serverProcess: Process?

    private init() {}

    public func startPreview(for projectURL: URL) {
        // In a real implementation, we might start a local HTTP server.
        // For this architecture migration, we'll point to the local file.
        // If it's an HTML project, find the index.html or the first html file.

        let indexURL = projectURL.appendingPathComponent("index.html")
        if FileManager.default.fileExists(atPath: indexURL.path) {
            previewURL = indexURL
        } else {
            // Find first html file
            let enumerator = FileManager.default.enumerator(at: projectURL, includingPropertiesForKeys: nil)
            while let fileURL = enumerator?.nextObject() as? URL {
                if fileURL.pathExtension.lowercased() == "html" {
                    previewURL = fileURL
                    return
                }
            }
        }
    }

    public func stopPreview() {
        previewURL = nil
    }
}
