// Ported from SwiftCode-Legacy `SwiftCode/Views/Collaboration/BranchGraphView.swift`
// (Dylan's own code; direct port authorised under MIT).
//
// The branch-cards graph: a horizontal strip of branch cards (last
// commit, author, current-branch marker), the per-branch list with
// Switch / Current, last-commit and merged-from lines, and the Recent
// Merges list. `CollaborationBranchManagementView` wraps this view; it
// is staged here because the destination has no equivalent —
// `swiftcode-ide/BranchGraphView.swift` is a different, internal view
// that renders `git log --graph` as text.
//
// Adaptations for SwiftCode: Legacy's hardcoded dark paint / white text
// become system-adaptive, and `.liquidGlass` (no destination
// equivalent) becomes the system thin material, as in the sibling
// Collaboration views.

import Foundation
import SwiftUI
import SwiftCodeCollaboration

@MainActor
public struct BranchGraphView: View {
    @ObservedObject var manager: CollaborationManager

    public init(manager: CollaborationManager) {
        self.manager = manager
    }

    public var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Visualization")
                                .font(.caption.bold())
                                .foregroundStyle(.blue)
                                .textCase(.uppercase)
                            Text("Branch Graph")
                                .font(.title2.bold())
                        }
                        Spacer()
                        Image(systemName: "point.3.connected.trianglepath.dotted")
                            .font(.title)
                            .foregroundStyle(.blue.opacity(0.8))
                    }

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 16) {
                            ForEach(manager.branches.branches) { branch in
                                branchCard(branch)
                            }
                        }
                        .padding(.vertical, 4)
                    }

                    Text("Visualize the evolution of your project across multiple branches.")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                .padding(20)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 24))

                VStack(alignment: .leading, spacing: 16) {
                    Text("Branches")
                        .font(.headline)

                    VStack(spacing: 12) {
                        ForEach(manager.branches.branches) { branch in
                            VStack(alignment: .leading, spacing: 12) {
                                HStack {
                                    HStack(spacing: 8) {
                                        Image(systemName: branch.id == manager.branches.currentBranch.id ? "largecircle.fill.circle" : "arrow.triangle.branch")
                                            .foregroundStyle(branch.id == manager.branches.currentBranch.id ? .blue : .secondary)
                                        Text(branch.name)
                                            .font(.headline)
                                    }
                                    Spacer()
                                    if branch.id != manager.branches.currentBranch.id {
                                        Button("Switch") {
                                            manager.branches.switchBranch(to: branch.id, actorID: Host.current().localizedName ?? "macOS Device")
                                        }
                                        .font(.caption.bold())
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 6)
                                        .background(Color.blue.opacity(0.2))
                                        .clipShape(Capsule())
                                    } else {
                                        Text("Current")
                                            .font(.caption.bold())
                                            .padding(.horizontal, 10)
                                            .padding(.vertical, 4)
                                            .background(Color.green.opacity(0.2))
                                            .foregroundStyle(.green)
                                            .clipShape(Capsule())
                                    }
                                }

                                if let commitID = branch.lastCommitID,
                                   let commit = manager.commits.commits.first(where: { $0.id == commitID }) {
                                    HStack(spacing: 4) {
                                        Image(systemName: "shippingbox")
                                        Text(commit.message)
                                    }
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                }

                                if let merge = manager.branches.merges.first(where: { $0.targetBranchID == branch.id }),
                                   let source = manager.branches.branches.first(where: { $0.id == merge.sourceBranchID }) {
                                    HStack(spacing: 4) {
                                        Image(systemName: "arrow.triangle.merge")
                                        Text("Merged from \(source.name)")
                                    }
                                    .font(.caption)
                                    .foregroundStyle(.green.opacity(0.8))
                                }
                            }
                            .padding()
                            .background(Color.secondary.opacity(0.08))
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                        }
                    }
                }
                .padding(20)
                .background(Color.secondary.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: 24))

                VStack(alignment: .leading, spacing: 16) {
                    Text("Recent Merges")
                        .font(.headline)

                    if manager.branches.merges.isEmpty {
                        Text("No recent merge activity.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.vertical, 20)
                    } else {
                        VStack(spacing: 12) {
                            ForEach(manager.branches.merges) { merge in
                                let source = manager.branches.branches.first(where: { $0.id == merge.sourceBranchID })?.name ?? "Unknown"
                                let target = manager.branches.branches.first(where: { $0.id == merge.targetBranchID })?.name ?? "Unknown"

                                HStack {
                                    Image(systemName: "arrow.triangle.merge")
                                        .foregroundStyle(.green)
                                    Text("\(source) → \(target)")
                                        .font(.subheadline)
                                    Spacer()
                                    Text(merge.timestamp.formatted(date: .abbreviated, time: .shortened))
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                .padding()
                                .background(Color.secondary.opacity(0.08))
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                            }
                        }
                    }
                }
                .padding(20)
                .background(Color.secondary.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: 24))
            }
            .padding()
        }
        .navigationTitle("Branch Graph")
    }

    private func branchCard(_ branch: Branch) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: branch.id == manager.branches.currentBranch.id ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(branch.id == manager.branches.currentBranch.id ? .blue : .secondary)
                Text(branch.name)
                    .font(.headline)
            }

            if let commitID = branch.lastCommitID,
               let commit = manager.commits.commits.first(where: { $0.id == commitID }) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(commit.message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                    Text(commit.authorID)
                        .font(.system(size: 8))
                        .foregroundStyle(.blue.opacity(0.7))
                }
            } else {
                Text("No Commits")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            RoundedRectangle(cornerRadius: 1)
                .frame(height: 4)
                .foregroundStyle(branch.id == manager.branches.currentBranch.id ? .blue : Color.secondary.opacity(0.2))
        }
        .padding(16)
        .frame(width: 160, height: 140, alignment: .leading)
        .background(Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(branch.id == manager.branches.currentBranch.id ? Color.blue.opacity(0.3) : Color.clear, lineWidth: 1)
        )
    }
}
