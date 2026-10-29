import SwiftUI

// MARK: - Available updates, computed against the registry

public struct ExtensionUpdatesView: View {
    @ObservedObject private var manager = ExtV2Manager.shared
    @State private var isChecking = false
    @State private var errorMessage: String?

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button("Check for updates") { Task { await check() } }
                    .buttonStyle(.borderedProminent)
                    .disabled(isChecking)
                if isChecking { ProgressView().controlSize(.small) }
                Spacer()
            }
            .padding()
            Divider()
            if manager.updates.isEmpty {
                ContentUnavailableView(
                    "No updates available",
                    systemImage: "arrow.down.circle",
                    description: Text(isChecking ? "Checking the registry…" : "All installed extensions are up to date, or update checks have not run yet."))
            } else {
                List(manager.updates) { update in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(update.installed.metadata.displayName).font(.subheadline.bold())
                            Text("\(update.installed.metadata.version) → \(update.latest.version)")
                                .font(.callout).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Update") {
                            Task {
                                do { try await manager.install(metadata: update.latest) }
                                catch { errorMessage = error.localizedDescription }
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .disabled(manager.installingIDs.contains(update.id))
                    }
                }
                .listStyle(.plain)
            }
        }
        .task { await check() }
        .alert(
            "Update failed",
            isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
        ) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func check() async {
        isChecking = true
        await manager.checkUpdates()
        isChecking = false
    }
}
