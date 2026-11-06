import SwiftUI

// MARK: - One extension row, used by search, installed, and updates lists
//
// The row shows only real state: the record's state (never a guessed
// one), the registry metadata, and the install action appropriate to
// that state. Installing shows progress and disables the button so a
// duplicate install cannot start.

public struct ExtensionSidebarRow: View {
    public let metadata: ExtV2ExtensionMetadata
    public let state: ExtV2State?
    public let isInstalling: Bool
    public let onInstall: (() -> Void)?
    public let onOpen: (() -> Void)?

    public init(
        metadata: ExtV2ExtensionMetadata, state: ExtV2State? = nil,
        isInstalling: Bool = false, onInstall: (() -> Void)? = nil,
        onOpen: (() -> Void)? = nil
    ) {
        self.metadata = metadata
        self.state = state
        self.isInstalling = isInstalling
        self.onInstall = onInstall
        self.onOpen = onOpen
    }

    public var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: metadata.kind == .native ? "swift" : "puzzlepiece")
                .font(.title3)
                .foregroundStyle(.secondary)
                .frame(width: 32, height: 32)
                .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 2) {
                Text(metadata.displayName)
                    .font(.subheadline.bold())
                    .lineLimit(1)
                Text("\(metadata.publisher) · v\(metadata.version)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(metadata.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                if let state {
                    Text(state.displayName)
                        .font(.caption2.bold())
                        .foregroundStyle(stateColor(state))
                }
                if !metadata.categories.isEmpty {
                    Text(metadata.categories.joined(separator: ", "))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
            Spacer()
            if isInstalling {
                ProgressView()
                    .controlSize(.small)
            } else if state == .notInstalled || state == nil {
                if let onInstall {
                    Button("Install", action: onInstall)
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                }
            } else if state == .enabled || state == .running {
                if let onOpen {
                    Button("Open", action: onOpen)
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func stateColor(_ state: ExtV2State) -> Color {
        switch state {
        case .enabled, .running: return .green
        case .disabled: return .secondary
        case .incompatible, .activationFailed, .crashed, .unavailable: return .red
        case .missingDependencies: return .orange
        case .installed, .notInstalled: return .secondary
        }
    }
}
