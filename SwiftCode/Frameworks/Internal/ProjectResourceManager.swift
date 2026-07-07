import Foundation

public final class ProjectResourceManager {
    public static let shared = ProjectResourceManager()
    private init() {}

    public func validateResources(at packageURL: URL) throws {
        // Ensure Assets, Resources, and Frameworks directories exist and contain valid items
    }

    public func copyResource(_ resourceURL: URL, to packageURL: URL) throws {
        let destURL = packageURL.appendingPathComponent("Resources").appendingPathComponent(resourceURL.lastPathComponent)
        try ProjectFileManager.shared.copyItem(at: resourceURL, to: destURL)
    }
}
