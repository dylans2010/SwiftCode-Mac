import SwiftUI

@MainActor
public struct CollaborationConflictResolverView: View {
    @ObservedObject var manager: CollaborationManager
    let actorID: String
    @State private var manualContent: String = ""

    public var body: some View {
        ZStack {
            Color(red: 0.05, green: 0.05, blue: 0.07).ignoresSafeArea()

            if manager.pendingConflicts.isEmpty {
                emptyConflictsView
            } else {
                conflictListView
            }
        }
        .navigationTitle("Conflict Resolver")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var emptyConflictsView: some View {
        VStack(spacing: 20) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 80))
                .foregroundStyle(.green)
            Text("No Conflicts Detected")
                .font(.title2.bold())
                .foregroundStyle(.white)
            Text("Your branch is up to date with the remote.")
                .foregroundStyle(.secondary)
        }
    }

    private var conflictListView: some View {
        ScrollView {
            VStack(spacing: 20) {
                ForEach(self.manager.pendingConflicts, id: \.id) { conflict in
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.red)
                            Text(conflict.filePath)
                                .font(.headline)
                                .foregroundStyle(.white)
                            Spacer()
                            Text("Pending")
                                .font(.caption.bold())
                                .foregroundStyle(.red)
                        }

                        // Diff Preview
                        HStack(spacing: 12) {
                            diffCard(title: "Local", content: conflict.localChange, color: .blue)
                            diffCard(title: "Remote", content: conflict.remoteChange, color: .orange)
                        }

                        // Resolution Actions
                        VStack(spacing: 10) {
                            resolutionButton(title: "Accept Current", icon: "arrow.uturn.backward", color: .blue) {
                                self.manager.resolveConflict(conflict.id, using: .useCurrent, actorID: self.actorID)
                            }
                            resolutionButton(title: "Accept Incoming", icon: "arrow.uturn.forward", color: .orange) {
                                self.manager.resolveConflict(conflict.id, using: .useIncoming, actorID: self.actorID)
                            }
                        }
                    }
                    .padding()
                    .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 16))
                }
            }
            .padding()
        }
    }

    private func diffCard(title: String, content: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.bold())
                .foregroundStyle(color)
            Text(content)
                .font(.system(size: 10, design: .monospaced))
                .lineLimit(5)
                .foregroundStyle(.secondary)
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.black.opacity(0.3), in: RoundedRectangle(cornerRadius: 8))
        }
        .frame(maxWidth: .infinity)
    }

    private func resolutionButton(title: String, icon: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Image(systemName: icon)
                Text(title)
                    .font(.subheadline.bold())
                Spacer()
            }
            .padding()
            .background(color.opacity(0.2), in: RoundedRectangle(cornerRadius: 12))
            .foregroundStyle(color)
        }
    }
}
