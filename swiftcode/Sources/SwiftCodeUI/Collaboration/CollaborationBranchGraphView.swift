import Foundation
import SwiftUI
import SwiftCodeCollaboration

@MainActor
public struct CollaborationBranchGraphView: View {
    @ObservedObject var manager: CollaborationManager

    public init(manager: CollaborationManager) {
        self.manager = manager
    }

    public var body: some View {
        ScrollView([.horizontal, .vertical]) {
            ZStack {
                HStack(alignment: .top, spacing: 60) {
                    ForEach(manager.branches.branches) { branch in
                        BranchLine(branch: branch, manager: manager)
                    }
                }
                .padding(40)
            }
        }
        .navigationTitle("Branch Visualizer")
    }
}

struct BranchLine: View {
    let branch: Branch
    let manager: CollaborationManager

    var body: some View {
        VStack(spacing: 20) {
            VStack(spacing: 4) {
                Image(systemName: "arrow.triangle.branch")
                    .font(.headline)
                    .foregroundStyle(.blue)
                Text(branch.name)
                    .font(.caption.bold())
            }
            .padding(10)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))

            VStack(spacing: 12) {
                let commits = manager.commits.commits(for: branch.id)
                ForEach(commits.prefix(10)) { commit in
                    CommitNode(commit: commit)
                }

                if commits.count > 10 {
                    Text("+ \(commits.count - 10) more")
                        .font(.system(size: 8))
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }
}

struct CommitNode: View {
    let commit: Commit

    var body: some View {
        VStack(spacing: 4) {
            Circle()
                .fill(Color.green)
                .frame(width: 10, height: 10)

            Text(commit.message)
                .font(.system(size: 8))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(width: 80)
        }
    }
}
