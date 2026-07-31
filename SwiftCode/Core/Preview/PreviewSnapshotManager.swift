import AppKit
import SwiftUI

public actor PreviewSnapshotManager {
    public static let shared = PreviewSnapshotManager()

    private init() {}

    /// Captures a high-fidelity image snapshot of any NSView on the MainActor.
    @MainActor
    public func captureSnapshot(of view: NSView) -> NSImage? {
        let bounds = view.bounds
        guard bounds.width > 0, bounds.height > 0 else { return nil }

        guard let imageRep = view.bitmapImageRepForCachingDisplay(in: bounds) else { return nil }
        view.cacheDisplay(in: bounds, to: imageRep)

        let image = NSImage(size: bounds.size)
        image.addRepresentation(imageRep)
        return image
    }
}
