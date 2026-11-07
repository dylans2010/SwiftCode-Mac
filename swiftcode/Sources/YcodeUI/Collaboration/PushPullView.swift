import Foundation
import SwiftUI
import SwiftCodeCollaboration

@MainActor
public struct PushPullView: View {
    @ObservedObject var manager: CollaborationManager

    public init(manager: CollaborationManager) {
        self.manager = manager
    }

    public var body: some View {
        PushPullManagerView(manager: manager, actorID: Host.current().localizedName ?? "macOS Device")
    }
}
