import SwiftUI

public struct XcodeProjViewer: View {
    public let model: XcodeProjModel
    @Environment(\.dismiss) private var dismiss

    // Use our central coordinator for navigation state
    private var coordinator = ProjectEditorCoordinator.shared

    public init(model: XcodeProjModel) {
        self.model = model
    }

    public var body: some View {
        HSplitView {
            // Left Workspace Sidebar
            VStack(alignment: .leading, spacing: 0) {
                // Project Header
                HStack(spacing: 12) {
                    Image(systemName: "hammer.circle.fill")
                        .font(.system(size: 32))
                        .foregroundStyle(.blue)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(model.projectURL.lastPathComponent)
                            .font(.headline)
                            .lineLimit(1)
                        Text("Xcode Project Workspace")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding()

                Divider()

                // Sidebar Navigation List
                List {
                    // Back/Forward buttons in Sidebar
                    HStack {
                        Button {
                            coordinator.goBack()
                        } label: {
                            Image(systemName: "chevron.left")
                        }
                        .disabled(!coordinator.canGoBack)
                        .buttonStyle(.plain)

                        Button {
                            coordinator.goForward()
                        } label: {
                            Image(systemName: "chevron.right")
                        }
                        .disabled(!coordinator.canGoForward)
                        .buttonStyle(.plain)

                        Spacer()

                        Text("History")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 4)
                    .padding(.vertical, 8)

                    Section("Project Info") {
                        SidebarButton(section: .overview, current: coordinator.selectedTab)
                        SidebarButton(section: .metadata, current: coordinator.selectedTab)
                        SidebarButton(section: .projectStatistics, current: coordinator.selectedTab)
                        SidebarButton(section: .relationships, current: coordinator.selectedTab)
                        SidebarButton(section: .warnings, current: coordinator.selectedTab)
                        SidebarButton(section: .diagnostics, current: coordinator.selectedTab)
                    }

                    Section("Targets (\(model.targets.count))") {
                        ForEach(model.targets) { target in
                            Button {
                                coordinator.selectedTargetID = target.uuid
                                coordinator.selectedTab = .general
                            } label: {
                                HStack {
                                    Image(systemName: "target")
                                        .foregroundStyle(.blue)
                                    Text(target.name)
                                        .font(.subheadline)
                                    Spacer()
                                    if coordinator.selectedTargetID == target.uuid {
                                        Image(systemName: "checkmark")
                                            .font(.caption)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                            .padding(.vertical, 4)
                        }

                        if coordinator.selectedTargetID != nil {
                            Divider()
                            SidebarButton(section: .general, current: coordinator.selectedTab)
                            SidebarButton(section: .identity, current: coordinator.selectedTab)
                            SidebarButton(section: .deployment, current: coordinator.selectedTab)
                            SidebarButton(section: .signingCapabilities, current: coordinator.selectedTab)
                            SidebarButton(section: .buildSettings, current: coordinator.selectedTab)
                            SidebarButton(section: .buildPhases, current: coordinator.selectedTab)
                            SidebarButton(section: .buildRules, current: coordinator.selectedTab)
                            SidebarButton(section: .infoPlist, current: coordinator.selectedTab)
                            SidebarButton(section: .entitlements, current: coordinator.selectedTab)
                        }
                    }

                    Section("Resources") {
                        SidebarButton(section: .assets, current: coordinator.selectedTab)
                        SidebarButton(section: .localization, current: coordinator.selectedTab)
                        SidebarButton(section: .products, current: coordinator.selectedTab)
                        SidebarButton(section: .fileReferences, current: coordinator.selectedTab)
                        SidebarButton(section: .groups, current: coordinator.selectedTab)
                    }

                    Section("Build Phases Details") {
                        SidebarButton(section: .copyFiles, current: coordinator.selectedTab)
                        SidebarButton(section: .shellScripts, current: coordinator.selectedTab)
                        SidebarButton(section: .headerPhases, current: coordinator.selectedTab)
                        SidebarButton(section: .resourcesPhase, current: coordinator.selectedTab)
                        SidebarButton(section: .frameworkPhase, current: coordinator.selectedTab)
                    }

                    Section("Packages") {
                        SidebarButton(section: .swiftPackages, current: coordinator.selectedTab)
                        SidebarButton(section: .packageDependencies, current: coordinator.selectedTab)
                        SidebarButton(section: .frameworks, current: coordinator.selectedTab)
                        SidebarButton(section: .dependencies, current: coordinator.selectedTab)
                    }
                }
                .listStyle(.sidebar)
            }
            .frame(minWidth: 220, idealWidth: 260, maxWidth: 300)

            // Right Detail Area
            VStack(spacing: 0) {
                // Detail Header
                HStack {
                    Image(systemName: coordinator.selectedTab.icon)
                        .foregroundStyle(.blue)
                    Text(coordinator.selectedTab.rawValue)
                        .font(.title2.bold())
                    Spacer()

                    if !coordinator.searchState.isEmpty {
                        Button { coordinator.searchState = "" } label: {
                            Image(systemName: "xmark.circle.fill")
                        }
                        .buttonStyle(.plain)
                    }

                    HStack(spacing: 6) {
                        Image(systemName: "magnifyingglass")
                        TextField("Filter details...", text: Binding(
                            get: { coordinator.searchState },
                            set: { coordinator.searchState = $0 }
                        ))
                        .textFieldStyle(.plain)
                        .frame(width: 150)
                    }
                    .padding(6)
                    .background(Color.white.opacity(0.06))
                    .cornerRadius(8)
                }
                .padding()
                .background(.background.opacity(0.4))

                Divider()

                // Content View dispatcher based on Selected Tab - calling modular subviews from XcodeProjTabs.swift
                detailContentView
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(minWidth: 500, idealWidth: 700)
        }
    }

    // MARK: - Subviews & Dispatcher

    @ViewBuilder
    private var detailContentView: some View {
        switch coordinator.selectedTab {
        case .overview:
            ProjectOverviewTabView(model: model)
        case .general:
            GeneralTabView(model: model, selectedTargetID: coordinator.selectedTargetID)
        case .identity:
            IdentityTabView(model: model, selectedTargetID: coordinator.selectedTargetID)
        case .deployment:
            DeploymentTabView(model: model, selectedTargetID: coordinator.selectedTargetID)
        case .buildSettings:
            BuildSettingsTabView(model: model, searchQuery: coordinator.searchState)
        case .buildRules:
            BuildRulesTabView(model: model)
        case .buildPhases:
            BuildPhasesTabView(model: model, selectedTargetID: coordinator.selectedTargetID)
        case .buildConfigurations:
            BuildConfigurationsTabView(model: model)
        case .targets:
            TargetsTabView(model: model)
        case .products:
            ProductsTabView(model: model)
        case .packages, .swiftPackages, .packageDependencies:
            PackagesTabView(model: model)
        case .frameworks:
            FrameworksTabView(model: model)
        case .dependencies:
            DependenciesTabView(model: model)
        case .signingCapabilities:
            SigningCapabilitiesTabView(model: model)
        case .entitlements:
            EntitlementsTabView(model: model)
        case .infoPlist:
            InfoPlistTabView(model: model)
        case .assets:
            AssetsTabView(model: model)
        case .localization:
            LocalizationTabView(model: model)
        case .resources:
            ResourcesTabView(model: model)
        case .sourceFiles:
            SourceFilesTabView(model: model)
        case .headers:
            HeadersTabView(model: model)
        case .warnings:
            WarningsTabView(model: model)
        case .diagnostics:
            DiagnosticsTabView(model: model)
        case .search:
            SearchTabView(model: model)
        case .relationships:
            RelationshipsTabView(model: model)
        case .projectStatistics:
            ProjectStatisticsTabView(model: model)
        case .metadata:
            MetadataTabView(model: model)
        case .projectSummary:
            ProjectSummaryTabView(model: model)
        case .targetSummary:
            TargetSummaryTabView(model: model, selectedTargetID: coordinator.selectedTargetID)
        case .fileReferences:
            FileReferencesTabView(model: model)
        case .groups:
            GroupsTabView(model: model)
        case .copyFiles:
            CopyFilesTabView(model: model)
        case .shellScripts:
            ShellScriptsTabView(model: model)
        case .headerPhases:
            HeaderPhasesTabView(model: model)
        case .resourcesPhase:
            ResourcesPhaseTabView(model: model)
        case .frameworkPhase:
            FrameworkPhaseTabView(model: model)
        case .projectInspector:
            ProjectInspectorTabView(model: model)
        case .targetInspector:
            TargetInspectorTabView(model: model, selectedTargetID: coordinator.selectedTargetID)
        case .buildLogs:
            BuildLogsTabView(model: model)
        }
    }
}

// MARK: - Helper Sidebar Button Component

struct SidebarButton: View {
    let section: ProjectEditorCoordinator.ProjectSection
    let current: ProjectEditorCoordinator.ProjectSection

    var body: some View {
        Button {
            ProjectEditorCoordinator.shared.selectedTab = section
        } label: {
            HStack {
                Image(systemName: section.icon)
                    .foregroundStyle(.blue)
                Text(section.rawValue)
                    .font(.subheadline)
                Spacer()
                if current == section {
                    Image(systemName: "checkmark")
                        .font(.caption)
                }
            }
        }
        .buttonStyle(.plain)
        .padding(.vertical, 4)
    }
}
