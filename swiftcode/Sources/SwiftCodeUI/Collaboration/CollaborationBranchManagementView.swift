// Ported from SwiftCode-Legacy `SwiftCode/Views/Collaboration/CollaborationBranchManagementView.swift`
// (Dylan's own code; direct port authorised under MIT).
//
// Thin wrapper around `BranchGraphView` (branch cards + commits), the
// same visual graph `CollaborationBranchGraphView` renders as columns.
// The destination's text `git log --graph` view
// (`swiftcode-ide/BranchGraphView.swift`) does not cover either visual
// form, so both visual views are staged alongside this wrapper.

import Foundation
import SwiftUI
import SwiftCodeCollaboration

@MainActor
public struct CollaborationBranchManagementView: View {
    @ObservedObject var manager: CollaborationManager

    public init(manager: CollaborationManager) {
        self.manager = manager
    }

    public var body: some View {
        BranchGraphView(manager: manager)
    }
}
