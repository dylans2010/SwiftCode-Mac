import SwiftUI

@MainActor
public struct CollaborationMainView: View {
    @ObservedObject var manager: CollaborationManager
    @State private var selectedTab: CollaborationTab = .overview
    private var currentUserID: String { UIDevice.current.name }
    private let allTabs = CollaborationTab.allCases

    public init(manager: CollaborationManager) {
        self.manager = manager
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                // Background Gradient
                LinearGradient(colors: [Color(red: 0.05, green: 0.05, blue: 0.1), Color(red: 0.1, green: 0.1, blue: 0.2)], startPoint: .topLeading, endPoint: .bottomTrailing)
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    contentHeader
                    tabSwitcher
                    selectedContent
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
            }
            .collaborationFeedback(message: manager.workspaces.lastSuccessMessage, icon: "checkmark.circle.fill", color: Color.green)
            .collaborationFeedback(message: manager.workspaces.lastErrorMessage, icon: "exclamationmark.triangle.fill", color: Color.red)
            .navigationTitle("")
            .navigationBarHidden(true)
        }
    }

    @ViewBuilder
    private var tabSwitcher: some View {
        VStack(spacing: 10) {
            HStack {
                Text("Workspace")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Menu {
                    Picker("Select Tab", selection: $selectedTab) {
                        ForEach(allTabs, id: \.self) { tab in
                            Label(tab.title, systemImage: tab.icon).tag(tab)
                        }
                    }
                } label: {
                    Label(selectedTab.title, systemImage: selectedTab.icon)
                        .font(.caption.weight(.semibold))
                }
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(allTabs, id: \.self) { tab in
                        Button {
                            selectedTab = tab
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: tab.icon)
                                Text(tab.title)
                            }
                            .font(.caption.weight(.medium))
                            .foregroundStyle(selectedTab == tab ? .white : .secondary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(
                                Capsule()
                                    .fill(selectedTab == tab ? Color.orange.opacity(0.85) : Color.white.opacity(0.08))
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(.horizontal)
        .padding(.top, 8)
        .padding(.bottom, 10)
        .background(.ultraThinMaterial)
    }

    @ViewBuilder
    private var contentHeader: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(selectedTab.title)
                    .font(.title3.bold())
                    .foregroundStyle(.white)
                Text(manager.project.name)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()

            HStack(spacing: 16) {
                Button {
                    // Quick Action: Sync
                    Task { await manager.syncCurrentBranch(actorID: currentUserID) }
                } label: {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .foregroundStyle(.teal)
                }

                Button {
                    // Quick Action: Notifications
                } label: {
                    Image(systemName: "bell.fill")
                        .foregroundStyle(.yellow)
                        .overlay(
                            Circle()
                                .fill(Color.red)
                                .frame(width: 8, height: 8)
                                .offset(x: 8, y: -8)
                                .opacity(manager.notifications.filter { !$0.isRead }.isEmpty ? 0 : 1)
                        )
                }
            }
        }
        .padding()
        .background(.ultraThinMaterial)
    }

    @ViewBuilder
    private var selectedContent: some View {
        switch selectedTab {
        case .overview:
            CollaborationDashboardView(manager: manager, actorID: currentUserID)
        case .branches:
            BranchWorkspaceView(manager: manager, actorID: currentUserID)
        case .commits:
            CommitManagerView(manager: manager, actorID: currentUserID)
        case .pullRequests:
            CollaborationPullRequestView(manager: manager, actorID: currentUserID)
        case .reviews:
            CollaborationCodeReviewView(manager: manager, actorID: currentUserID)
        case .chat:
            CollaborationChatView(manager: manager, actorID: currentUserID)
        case .sync:
            PushPullManagerView(manager: manager, actorID: currentUserID)
        case .people:
            MemberManagementView(manager: manager, actorID: currentUserID)
        case .activity:
            CollaborationAuditLogView(manager: manager)
        case .conflicts:
            ConflictResolverView(manager: manager, actorID: currentUserID)
        case .files:
            FilePermissionView(manager: manager, actorID: currentUserID)
        }
    }
}
