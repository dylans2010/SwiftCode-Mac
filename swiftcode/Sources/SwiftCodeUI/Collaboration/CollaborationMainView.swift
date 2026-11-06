// Ported from Legacy (Dylan's own SwiftCode code, MIT-authorised direct port):
//   SwiftCode/Views/Collaboration/CollaborationMainView.swift
// Adapted for SwiftCode:
// - The chat manager is an INJECTED dependency, not constructed here:
//   CollaborationChatManager declares no public init (its default init is
//   internal to SwiftCodeCollaboration), so no SwiftCodeUI code can create
//   one today. The IDE shell must pass one in; the backend gap is a missing
//   one-line `public init() {}` on CollaborationChatManager (cf.
//   PullRequestManager's public init). Until that lands, the shell cannot
//   instantiate the chat manager, but these staged files contain no
//   uncompilable construct.
// - Legacy's notification-bell button had an empty action; it now presents
//   the real CollaborationNotificationCenterView as a sheet.
// - Sync quick action calls the real CollaborationManager.syncCurrentBranch.
// - Feedback toasts read the real BranchWorkspaceManager
//   lastSuccessMessage / lastErrorMessage via the `collaborationFeedback`
//   modifier (CollaborationFeedbackView.swift).
// - Legacy's hardcoded dark gradient becomes system-adaptive.
// - Tab content references the sibling collaboration views
//   (BranchWorkspaceView, CommitManagerView, CollaborationPullRequestView,
//   CollaborationCodeReviewView, PushPullManagerView, ConflictResolverView):
//   they are staged by the sibling wave, not yet in the destination, so this
//   file compiles once those staged files land alongside it.

import Foundation
import SwiftUI
import SwiftCodeCollaboration

@MainActor
public struct CollaborationMainView: View {
    @ObservedObject var manager: CollaborationManager
    @ObservedObject var chat: CollaborationChatManager
    @State private var selectedTab: CollaborationTab = .overview
    @State private var showingNotifications = false
    private var currentUserID: String { Host.current().localizedName ?? "macOS Device" }
    private let allTabs = CollaborationTab.allCases

    public init(manager: CollaborationManager, chat: CollaborationChatManager) {
        self.manager = manager
        self.chat = chat
    }

    public var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                contentHeader
                tabSwitcher
                selectedContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .collaborationFeedback(message: manager.workspaces.lastSuccessMessage, icon: "checkmark.circle.fill", color: Color.green)
            .collaborationFeedback(message: manager.workspaces.lastErrorMessage, icon: "exclamationmark.triangle.fill", color: Color.red)
            .navigationTitle("")
            .sheet(isPresented: $showingNotifications) {
                CollaborationNotificationCenterView(manager: manager)
            }
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
                            .foregroundStyle(selectedTab == tab ? .primary : .secondary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(
                                Capsule()
                                    .fill(selectedTab == tab ? Color.orange.opacity(0.85) : Color.secondary.opacity(0.08))
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
                    showingNotifications = true
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
            CollaborationChatView(manager: manager, chat: chat, actorID: currentUserID)
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
