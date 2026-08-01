import SwiftUI
import AppKit

struct DependencyManagerView: View {
    @Environment(ProjectSessionStore.self) private var sessionStore
    @Environment(\.dismiss) private var dismiss

    @State private var platformManager = DependencyPlatformManager.shared
    @State private var activeDependencies: [ParsedDependency] = []

    // Quick Actions
    @State private var activeQuickMessage: String?
    @State private var showQuickMessage = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 28) {
                    // Central Banner
                    GroupBox {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Label("Ecosystem Dependency Platform", systemImage: "puzzlepiece.extension.fill")
                                    .font(.title2.bold())
                                    .foregroundStyle(.blue)
                                Spacer()

                                Button {
                                    refreshActiveManifest()
                                } label: {
                                    Label("Refresh Manifest", systemImage: "arrow.clockwise")
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }

                            Text("Manage packages, discover repositories on GitHub, analyze dependencies, run security audits, and consult with the AI Co-Designer.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .padding(12)
                    }
                    .groupBoxStyle(ModernGroupBoxStyle())

                    // Main Dashboard Grid of Feature Cards
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 340, maximum: .infinity))], spacing: 20) {

                        // Card 1: Package Explorer
                        NavigationLink(destination: PackageExplorerView()) {
                            renderDashboardCard(
                                title: "Package Explorer",
                                systemImage: "safari.fill",
                                color: .orange,
                                description: "Discover featured libraries, trending releases, and recommended toolkits.",
                                status: "Synced with Registry",
                                stats: "\(platformManager.featuredPackages.count + platformManager.trendingPackages.count) Packages available",
                                activity: "Last update: Today",
                                quickActionLabel: "Browse Featured",
                                quickAction: {
                                    // Quick action
                                }
                            )
                        }
                        .buttonStyle(.plain)

                        // Card 2: GitHub Discovery
                        NavigationLink(destination: DependencyGitHubDiscoveryView()) {
                            renderDashboardCard(
                                title: "GitHub Discovery Engine",
                                systemImage: "magnifyingglass.circle.fill",
                                color: .blue,
                                description: "Scan GitHub for third-party Swift Package Manager packages with advanced filters.",
                                status: "API Online",
                                stats: "\(platformManager.searchHistory.count) past searches saved",
                                activity: "Latest search: '\(platformManager.searchHistory.first ?? "None")'",
                                quickActionLabel: "Search API",
                                quickAction: {}
                            )
                        }
                        .buttonStyle(.plain)

                        // Card 3: AI Assistant Co-Designer
                        NavigationLink(destination: PackageAIView()) {
                            renderDashboardCard(
                                title: "AI Assistant Co-Designer",
                                systemImage: "sparkles",
                                color: .purple,
                                description: "Explain dependencies, clear cyclic target paths, and request architectural suggestions.",
                                status: "Copilot Ready",
                                stats: "\(platformManager.chatHistory.count) conversations recorded",
                                activity: "Last query: '\(platformManager.chatHistory.last?.prompt.prefix(20) ?? "None")'",
                                quickActionLabel: "Ask Copilot",
                                quickAction: {}
                            )
                        }
                        .buttonStyle(.plain)

                        // Card 4: Collections & Presets
                        NavigationLink(destination: PackageCollectionsView()) {
                            renderDashboardCard(
                                title: "Custom Workspaces & Presets",
                                systemImage: "folder.fill",
                                color: .yellow,
                                description: "Organize libraries into reusable development templates and project presets.",
                                status: "Local Storage Saved",
                                stats: "\(platformManager.collections.count) collections, \(platformManager.favoritePackages.count) favorites",
                                activity: "Active Category: \(platformManager.collections.first?.category ?? "General")",
                                quickActionLabel: "Manage Presets",
                                quickAction: {}
                            )
                        }
                        .buttonStyle(.plain)

                        // Card 5: Dependency Graph Visualizer
                        NavigationLink(destination: DependencyVisualizerView()) {
                            renderDashboardCard(
                                title: "Dependency Graph Visualizer",
                                systemImage: "network",
                                color: .cyan,
                                description: "Interactive structural map showing direct, nested, and conflicting targets.",
                                status: "Graph Analyzed",
                                stats: "\(activeDependencies.count) active targets mapped",
                                activity: "Conflict check: Passed",
                                quickActionLabel: "View Relations",
                                quickAction: {}
                            )
                        }
                        .buttonStyle(.plain)

                        // Card 6: Security Center
                        NavigationLink(destination: DependencySecurityCenterView()) {
                            renderDashboardCard(
                                title: "Ecosystem Security & Audit",
                                systemImage: "shield.checkerboard",
                                color: .green,
                                description: "Vulnerability CVE checking, deprecated repository analyzer, and license compliance audits.",
                                status: "Protected",
                                stats: "Risk score: \(platformManager.securityScore)/100",
                                activity: "Vulnerability count: \(platformManager.knownAdvisories.count) loaded",
                                quickActionLabel: "Trigger Scan",
                                quickAction: {
                                    triggerFastSecurityScan()
                                }
                            )
                        }
                        .buttonStyle(.plain)
                    }

                    // Active Manifest Panel
                    GroupBox {
                        VStack(alignment: .leading, spacing: 14) {
                            HStack {
                                Label("Active Project Manifest dependencies", systemImage: "checklist")
                                    .font(.headline)
                                    .foregroundStyle(.blue)
                                Spacer()
                            }

                            if activeDependencies.isEmpty {
                                Text("No external packages found in active Package.swift.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .padding(.vertical, 8)
                            } else {
                                VStack(spacing: 12) {
                                    ForEach(activeDependencies, id: \.id) { dep in
                                        HStack {
                                            Image(systemName: dep.isLocal ? "folder.fill" : "puzzlepiece.extension.fill")
                                                .foregroundStyle(dep.isLocal ? .orange : .blue)

                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(dep.url.split(separator: "/").last?.replacingOccurrences(of: ".git", with: "") ?? dep.url)
                                                    .font(.subheadline.bold())
                                                Text("\(dep.requirementType.rawValue): \(dep.value)")
                                                    .font(.system(size: 10, design: .monospaced))
                                                    .foregroundStyle(.secondary)
                                            }

                                            Spacer()

                                            Button {
                                                uninstallPackageDirect(dep)
                                            } label: {
                                                Image(systemName: "trash")
                                                    .foregroundStyle(.red)
                                            }
                                            .buttonStyle(.plain)
                                        }
                                        .padding(10)
                                        .background(Color.secondary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
                                    }
                                }
                            }
                        }
                        .padding(12)
                    }
                    .groupBoxStyle(ModernGroupBoxStyle())
                }
                .padding(24)
            }
            .background(Color(NSColor.windowBackgroundColor))
            .navigationTitle("Package Dependency Suite")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .alert("Operation Result", isPresented: $showQuickMessage, presenting: activeQuickMessage) { _ in
                Button("OK") {}
            } message: { msg in
                Text(msg)
            }
            .onAppear {
                refreshActiveManifest()
            }
        }
    }

    // MARK: - Dashboard Card Builder
    @ViewBuilder
    private func renderDashboardCard(
        title: String,
        systemImage: String,
        color: Color,
        description: String,
        status: String,
        stats: String,
        activity: String,
        quickActionLabel: String,
        quickAction: @escaping () -> Void
    ) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    Image(systemName: systemImage)
                        .font(.title2)
                        .foregroundStyle(color)
                        .frame(width: 36, height: 36)
                        .background(color.opacity(0.12), in: Circle())

                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .font(.headline)
                            .foregroundStyle(.primary)
                        Text(status)
                            .font(.caption2.bold())
                            .foregroundStyle(color)
                    }
                    Spacer()
                }

                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .frame(height: 36, alignment: .topLeading)

                Divider()

                VStack(alignment: .leading, spacing: 4) {
                    Text(stats)
                        .font(.caption2.bold())
                    Text(activity)
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Spacer()
                    Button {
                        quickAction()
                    } label: {
                        Text(quickActionLabel)
                            .font(.caption2.bold())
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
            .padding(8)
        }
        .groupBoxStyle(ModernGroupBoxStyle())
    }

    // MARK: - Local Manifest Sync Helper
    private func refreshActiveManifest() {
        guard let project = sessionStore.activeProject else { return }
        let packageURL = project.directoryURL.appendingPathComponent("Package.swift")
        guard let content = try? String(contentsOf: packageURL, encoding: .utf8) else { return }

        let pathPattern = #"\.package\(path:\s*"([^"]+)"\)"#
        let urlPattern = #"\.package\(url:\s*"([^"]+)",\s*(from|branch|revision|exact):\s*"([^"]+)"\)"#

        var parsedList: [ParsedDependency] = []
        let nsContent = content as NSString

        if let pathRegex = try? NSRegularExpression(pattern: pathPattern) {
            let matches = pathRegex.matches(in: content, range: NSRange(location: 0, length: nsContent.length))
            for match in matches {
                let path = nsContent.substring(with: match.range(at: 1))
                parsedList.append(ParsedDependency(url: path, requirementType: .exact, value: "local", isLocal: true))
            }
        }

        if let urlRegex = try? NSRegularExpression(pattern: urlPattern) {
            let matches = urlRegex.matches(in: content, range: NSRange(location: 0, length: nsContent.length))
            for match in matches {
                let url = nsContent.substring(with: match.range(at: 1))
                let reqTypeRaw = nsContent.substring(with: match.range(at: 2))
                let val = nsContent.substring(with: match.range(at: 3))

                let reqType = DependencyRequirementType(rawValue: reqTypeRaw) ?? .from
                parsedList.append(ParsedDependency(url: url, requirementType: reqType, value: val, isLocal: false))
            }
        }

        self.activeDependencies = parsedList
    }

    private func uninstallPackageDirect(_ dep: ParsedDependency) {
        Task {
            let success = await platformManager.removePackage(url: dep.url, activeProject: sessionStore.activeProject)
            if success {
                activeQuickMessage = "Successfully uninstalled package \(dep.url.split(separator: "/").last?.replacingOccurrences(of: ".git", with: "") ?? dep.url)."
                refreshActiveManifest()
            } else {
                activeQuickMessage = "Uninstall failed."
            }
            showQuickMessage = true
        }
    }

    private func triggerFastSecurityScan() {
        Task {
            await platformManager.executeSecurityScan(dependencies: activeDependencies)
            activeQuickMessage = "Security Scan Finished. Global risk score: \(platformManager.securityScore)/100."
            showQuickMessage = true
        }
    }
}
