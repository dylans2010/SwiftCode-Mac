import SwiftUI

@MainActor
struct PushPullView: View {
    @ObservedObject var manager: CollaborationManager

    var body: some View {
        PushPullManagerView(manager: manager, actorID: Host.current().localizedName ?? "macOS Device")
    }
}
