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
