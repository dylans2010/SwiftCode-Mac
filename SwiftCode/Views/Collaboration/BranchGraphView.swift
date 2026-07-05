import SwiftUI

@MainActor
struct BranchGraphView: View {
    @ObservedObject var manager: CollaborationManager

    var body: some View {
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
                                .foregroundStyle(.white)
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
                .background(Color.white.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: 24))
                .overlay(RoundedRectangle(cornerRadius: 24).stroke(Color.white.opacity(0.1), lineWidth: 1))

                VStack(alignment: .leading, spacing: 16) {
                    Text("Branches")
                        .font(.headline)
                        .foregroundStyle(.white)

                    VStack(spacing: 12) {
                        ForEach(manager.branches.branches) { branch in
                            VStack(alignment: .leading, spacing: 12) {
                                HStack {
                                    HStack(spacing: 8) {
                                        Image(systemName: branch.id == manager.branches.currentBranch.id ? "largecircle.fill.circle" : "arrow.triangle.branch")
                                            .foregroundStyle(branch.id == manager.branches.currentBranch.id ? .blue : .secondary)
                                        Text(branch.name)
                                            .font(.headline)
                                            .foregroundStyle(.white)
                                    }
                                    Spacer()
                                    if branch.id != manager.branches.currentBranch.id {
                                        Button("Switch") {
                                            manager.branches.switchBranch(to: branch.id, actorID: UIDevice.current.name)
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
                            .background(Color.white.opacity(0.05))
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                        }
                    }
                }
                .padding(20)
                .background(Color.white.opacity(0.03))
                .clipShape(RoundedRectangle(cornerRadius: 24))

                VStack(alignment: .leading, spacing: 16) {
                    Text("Recent Merges")
                        .font(.headline)
                        .foregroundStyle(.white)

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
                                        .foregroundStyle(.white)
                                    Spacer()
                                    Text(merge.timestamp.formatted(date: .abbreviated, time: .shortened))
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                .padding()
                                .background(Color.white.opacity(0.05))
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                            }
                        }
                    }
                }
                .padding(20)
                .background(Color.white.opacity(0.03))
                .clipShape(RoundedRectangle(cornerRadius: 24))
            }
            .padding()
        }
        .background(Color.clear)
        .navigationTitle("Branch Graph")
    }

    private func branchCard(_ branch: Branch) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: branch.id == manager.branches.currentBranch.id ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(branch.id == manager.branches.currentBranch.id ? .blue : .secondary)
                Text(branch.name)
                    .font(.headline)
                    .foregroundStyle(.white)
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
                .foregroundStyle(branch.id == manager.branches.currentBranch.id ? .blue : Color.white.opacity(0.1))
        }
        .padding(16)
        .frame(width: 160, height: 140, alignment: .leading)
        .background(Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(branch.id == manager.branches.currentBranch.id ? Color.blue.opacity(0.3) : Color.clear, lineWidth: 1)
        )
    }
}
