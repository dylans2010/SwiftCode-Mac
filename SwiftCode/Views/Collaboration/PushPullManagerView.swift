import SwiftUI

struct PushPullManagerView: View {
    @ObservedObject var manager: CollaborationManager
    let actorID: String
    @State private var selectedBranchID: UUID?
    @State private var statusMessage: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Synchronization")
                                .font(.caption.bold())
                                .foregroundStyle(.blue)
                                .textCase(.uppercase)
                            Text("Branch Sync")
                                .font(.title2.bold())
                                .foregroundStyle(.white)
                        }
                        Spacer()
                        Image(systemName: "arrow.up.arrow.down.circle")
                            .font(.title)
                            .foregroundStyle(.blue.opacity(0.8))
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        Text("Select Branch")
                            .font(.subheadline.bold())
                            .foregroundStyle(.secondary)

                        Picker("Branch", selection: Binding(get: {
                            selectedBranchID ?? manager.branches.currentBranch.id
                        }, set: { newValue in
                            selectedBranchID = newValue
                            manager.branches.switchBranch(to: newValue, actorID: actorID)
                        })) {
                            ForEach(manager.branches.branches) { branch in
                                Text(branch.name).tag(branch.id)
                            }
                        }
                        .pickerStyle(.menu)
                        .padding(8)
                        .background(Color.white.opacity(0.05))
                        .clipShape(RoundedRectangle(cornerRadius: 12))

                        Button {
                            statusMessage = "Sync In Progress..."
                            Task {
                                await manager.syncCurrentBranch(actorID: actorID)
                                statusMessage = "Sync Complete."
                            }
                        } label: {
                            Label("Sync Across Peers", systemImage: "arrow.triangle.2.circlepath")
                                .font(.subheadline.bold())
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.blue.opacity(0.2))
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                    }

                    Text("Live conflict detection and routing.")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                .padding(20)
                .background(Color.white.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: 24))
                .overlay(RoundedRectangle(cornerRadius: 24).stroke(Color.white.opacity(0.1), lineWidth: 1))

                VStack(alignment: .leading, spacing: 16) {
                    Text("Active Transfers")
                        .font(.headline)
                        .foregroundStyle(.white)

                    if manager.pushes.activePushes.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "arrow.up.and.down.and.sparkles")
                                .font(.largeTitle)
                                .foregroundStyle(.secondary)
                            Text("No active transfers")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 30)
                    } else {
                        VStack(spacing: 12) {
                            ForEach(manager.pushes.activePushes) { transfer in
                                VStack(alignment: .leading, spacing: 12) {
                                    HStack {
                                        Label("\(transfer.direction) \(transfer.branchName)", systemImage: transfer.direction == "Push" ? "arrow.up.circle" : "arrow.down.circle")
                                            .foregroundStyle(.white)
                                        Spacer()
                                        Text("\(Int(transfer.progress * 100))%")
                                            .font(.caption2.bold())
                                            .foregroundStyle(.blue)
                                    }
                                    ProgressView(value: transfer.progress)
                                        .tint(.blue)
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

                if !manager.pendingConflicts.isEmpty {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Conflicts")
                            .font(.headline)
                            .foregroundStyle(.red)

                        VStack(spacing: 12) {
                            ForEach(manager.pendingConflicts) { conflict in
                                NavigationLink {
                                    ConflictResolverView(manager: manager, actorID: actorID)
                                } label: {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(conflict.filePath).font(.headline).foregroundStyle(.white)
                                            Text("Local: \(conflict.localChange)")
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                        Image(systemName: "exclamationmark.triangle")
                                            .foregroundStyle(.red)
                                    }
                                    .padding()
                                    .background(Color.red.opacity(0.1))
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                                }
                            }
                        }
                    }
                    .padding(20)
                    .background(Color.white.opacity(0.03))
                    .clipShape(RoundedRectangle(cornerRadius: 24))
                }

                if let statusMessage {
                    Label(statusMessage, systemImage: "info.circle")
                        .font(.caption.bold())
                        .foregroundStyle(.blue)
                        .padding()
                        .background(Color.blue.opacity(0.1))
                        .clipShape(Capsule())
                }
            }
            .padding()
        }
        .background(Color.clear)
        .navigationTitle("Push / Pull")
        .onAppear {
            selectedBranchID = manager.branches.currentBranch.id
        }
    }
}
