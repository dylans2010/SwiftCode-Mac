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
