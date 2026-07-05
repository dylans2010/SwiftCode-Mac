import SwiftUI

public struct CollaborationSidebarView: View {
    @Binding var selectedTab: CollaborationTab
    let manager: CollaborationManager

    public var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Collaboration")
                .font(.title2.bold())
                .foregroundStyle(.white)
                .padding(.horizontal)
                .padding(.top, 40)

            VStack(spacing: 4) {
                ForEach(CollaborationTab.allCases) { tab in
                    SidebarItem(tab: tab, isSelected: selectedTab == tab) {
                        selectedTab = tab
                    }
                }
            }
            .padding(.horizontal, 12)

            Spacer()

            // Active Users Mini Panel
            VStack(alignment: .leading, spacing: 12) {
                Text("Active Now")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)

                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(manager.activeUsers) { user in
                            HStack(spacing: 8) {
                                Circle()
                                    .fill(Color.green)
                                    .frame(width: 8, height: 8)
                                Text(user.id)
                                    .font(.caption)
                                    .foregroundStyle(.white)
                                Spacer()
                            }
                        }
                    }
                    .padding(.horizontal)
                }
                .frame(maxHeight: 120)
            }
            .padding(.bottom, 20)
        }
        .frame(width: 240)
        .background(Color.black.opacity(0.4))
        .background(.ultraThinMaterial)
    }
}

struct SidebarItem: View {
    let tab: CollaborationTab
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: tab.icon)
                    .font(.subheadline)
                    .foregroundStyle(isSelected ? .white : .secondary)
                    .frame(width: 24)

                Text(tab.title)
                    .font(.subheadline.weight(isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? .white : .secondary)

                Spacer()
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 12)
            .background(isSelected ? Color.blue.opacity(0.2) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }
}

public enum CollaborationTab: String, CaseIterable, Identifiable {
    case overview, branches, commits, pullRequests, reviews, chat, sync, people, activity, conflicts, files
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .pullRequests: return "Pull Requests"
        default: return rawValue.capitalized
        }
    }
    public var icon: String {
        switch self {
        case .overview: return "square.grid.2x2"
        case .branches: return "arrow.triangle.branch"
        case .commits: return "shippingbox"
        case .pullRequests: return "tray.full"
        case .reviews: return "text.badge.checkmark"
        case .chat: return "bubble.left.and.bubble.right"
        case .sync: return "arrow.up.arrow.down"
        case .people: return "person.3"
        case .activity: return "clock"
        case .conflicts: return "exclamationmark.arrow.trianglehead.2.clockwise.rotate.90"
        case .files: return "lock.doc"
        }
    }
}
