import SwiftUI

@MainActor
struct PushPullView: View {
    @ObservedObject var manager: CollaborationManager

    var body: some View {
        PushPullManagerView(manager: manager, actorID: UIDevice.current.name)
    }
}
