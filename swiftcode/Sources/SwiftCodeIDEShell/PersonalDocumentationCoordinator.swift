// Ported from Legacy `SwiftCode/Views/Utilities/NSPersonalDocumentation/Coordinators/PersonalDocumentationCoordinator.swift` (Audit E §5 partial entry; H-E5).
// Types ported here: WorkspaceState.

import AppKit
import Foundation
import Observation
import SwiftUI

@Observable
@MainActor
public final class WorkspaceState {
    public var selectedDocumentID: UUID? = nil
    public var searchActive: Bool = false
    public var searchQuery: String = ""
    public var showBrowserSheet: Bool = false
    public var showLivePreview: Bool = true
    public var showLeftSidebar: Bool = true
    public var showRightInspector: Bool = true

    public init() {}
}
