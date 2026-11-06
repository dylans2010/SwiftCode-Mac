import SwiftUI

struct CollaborationBranchManagementView: View {
    @ObservedObject var manager: CollaborationManager

    var body: some View {
        BranchGraphView(manager: manager)
    }
}
