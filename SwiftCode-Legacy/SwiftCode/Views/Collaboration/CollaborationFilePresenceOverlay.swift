import SwiftUI

@MainActor
public struct CollaborationFilePresenceOverlay: View {
    @ObservedObject var manager: CollaborationManager
    let filePath: String

    public var body: some View {
        let viewers = manager.activeUsers.filter { $0.currentFile == filePath }

        if viewers.isEmpty {
            EmptyView()
        } else {
            HStack(spacing: 8) {
                ForEach(viewers) { viewer in
                    CollaboratorAvatar(userID: viewer.id)
                }
            }
            .padding(6)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(Capsule().stroke(Color.white.opacity(0.1), lineWidth: 1))
            .shadow(radius: 4)
        }
    }
}

struct CollaboratorAvatar: View {
    let userID: String

    var body: some View {
        ZStack {
            Circle()
                .fill(avatarColor(for: userID))
                .frame(width: 24, height: 24)
            Text(String(userID.prefix(1)).uppercased())
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.white)
        }
        .overlay(Circle().stroke(Color.white.opacity(0.5), lineWidth: 1))
    }

    private func avatarColor(for id: String) -> Color {
        let colors: [Color] = [.blue, .green, .orange, .purple, .pink, .teal, .indigo, .cyan]
        let hash = abs(id.hashValue)
        return colors[hash % colors.count]
    }
}
