import SwiftUI

public struct StatusBarState: Equatable, Sendable {
    public var branchName: String?
    public var ahead: Int
    public var behind: Int
    public var isBuilding: Bool

    public init(branchName: String? = nil, ahead: Int = 0, behind: Int = 0, isBuilding: Bool = false) {
        self.branchName = branchName
        self.ahead = ahead
        self.behind = behind
        self.isBuilding = isBuilding
    }
}

public struct StatusBarView: View {
    public var state: StatusBarState

    public init(state: StatusBarState) {
        self.state = state
    }

    public var body: some View {
        HStack {
            if let branch = state.branchName {
                Label(branch, systemImage: "branch")
                Text("↑\(state.ahead) ↓\(state.behind)")
            }
            Spacer()
            if state.isBuilding {
                ProgressView().controlSize(.small)
                Text("Building…")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .font(.caption)
        .background(Color.secondary.opacity(0.08))
        .overlay(Divider(), alignment: .top)
    }
}
