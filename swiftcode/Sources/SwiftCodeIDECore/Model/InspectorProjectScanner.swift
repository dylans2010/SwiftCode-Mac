// Ported from Legacy `SwiftCode/Views/Utilities/ProjectInspector/InspectorProjectScanner.swift` (Audit E §5 partial entry; H-E5).
// Types ported here: CacheEntry.

import Foundation
import Observation
import SwiftUI
import os

public struct CacheEntry: Codable, Sendable {
    public let fileSize: Int64
    public let modificationDate: Date
    public let lineCount: Int
    public let swiftUI: Bool
    public let uikit: Bool
    public let appkit: Bool
    public let observation: Bool
    public let asyncAwait: Bool
    public let actorDefined: Bool
}
