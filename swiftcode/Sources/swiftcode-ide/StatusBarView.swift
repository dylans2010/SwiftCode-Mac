import SwiftUI

/// The workspace status bar — Legacy's `StatusBarView`, ported onto SwiftCode.
///
/// SwiftCode has no status bar today (the workspace window shows git state in
/// the toolbar area and build state in the build bezel), so this is a new
/// SwiftUI bar for the `swiftcode-ide` shell: current branch with ahead/behind
/// counts, and a building indicator. It takes a plain `StatusBarState`
/// value; feeding it from the workspace's source-control and build models
/// is a wiring item (see the bulk Views-A wiring list).
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
