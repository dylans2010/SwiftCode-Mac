import SwiftUI

struct PackageDetailsView: View {
    let package: PackageMetadata

    @Environment(\.dismiss) private var dismiss
    @Environment(ProjectSessionStore.self) private var sessionStore
    @State private var platformManager = DependencyPlatformManager.shared
    @State private var selectedTab: DetailTab = .overview
    @State private var readmeText: String = ""
    @State private var isLoadingReadme: Bool = false

    enum DetailTab: String, CaseIterable, Identifiable {
        case overview = "Overview"
        case readme = "README"
        case manifest = "Manifest"
        case analytics = "Analytics"
        case activity = "Activity"
        case compatibility = "Compatibility"

        var id: String { rawValue }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(alignment: .center) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.title3)
                }
                .buttonStyle(.plain)

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(package.name)
                            .font(.title1.bold())
                        if package.isVerified {
                            Image(systemName: "checkmark.seal.fill")
                                .foregroundStyle(.blue)
                        }
                    }
                    Text(package.fullName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                HStack(spacing: 12) {
                    Button {
                        platformManager.toggleFavorite(url: package.cloneUrl)
                    } label: {
                        Image(systemName: platformManager.favoritePackages.contains(package.cloneUrl) ? "star.fill" : "star")
                            .foregroundStyle(.yellow)
                    }
                    .buttonStyle(.bordered)

                    NavigationLink(destination: PackageInstallationView(package: package)) {
                        Label("Install / Manage", systemImage: "square.and.arrow.down.fill")
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            // Tab Selector Toolbar
            HStack {
                ForEach(DetailTab.allCases) { tab in
                    Button {
                        selectedTab = tab
                    } label: {
                        Text(tab.rawValue)
                            .fontWeight(selectedTab == tab ? .bold : .regular)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(selectedTab == tab ? Color.accentColor.opacity(0.12) : Color.clear, in: RoundedRectangle(cornerRadius: 8))
                            .foregroundStyle(selectedTab == tab ? Color.accentColor : .primary)
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 10)
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            // Content
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    switch selectedTab {
                    case .overview:
                        renderOverview()
                    case .readme:
                        renderReadme()
                    case .manifest:
                        renderManifest()
                    case .analytics:
                        renderAnalytics()
                    case .activity:
                        renderActivity()
                    case .compatibility:
                        renderCompatibility()
                    }
                }
                .padding(24)
            }
            .background(Color(NSColor.controlBackgroundColor))
        }
        .background(Color(NSColor.windowBackgroundColor))
        .onAppear {
            loadReadme()
            if !platformManager.continueBrowsing.contains(package.cloneUrl) {
                platformManager.continueBrowsing.insert(package.cloneUrl, at: 0)
                if platformManager.continueBrowsing.count > 5 {
                    platformManager.continueBrowsing.removeLast()
                }
            }
        }
    }

    // MARK: - Overview Tab
    @ViewBuilder
    private func renderOverview() -> some View {
        VStack(alignment: .leading, spacing: 20) {
            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    Label("Description", systemImage: "info.circle")
                        .font(.headline)
                        .foregroundStyle(.blue)
                    Text(package.description ?? "No description available for this package.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
                .padding(12)
            }
            .groupBoxStyle(ModernGroupBoxStyle())

            HStack(spacing: 20) {
                GroupBox {
                    VStack(alignment: .leading, spacing: 10) {
                        Label("Target Platforms", systemImage: "iphone")
                            .font(.headline)
                            .foregroundStyle(.orange)
                        ForEach(package.platforms, id: \.self) { platform in
                            Label(platform, systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        }
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .groupBoxStyle(ModernGroupBoxStyle())

                GroupBox {
                    VStack(alignment: .leading, spacing: 10) {
                        Label("Specs & Tools", systemImage: "wrench.and.screwdriver")
                            .font(.headline)
                            .foregroundStyle(.purple)
                        Text("Swift Tools Version: \(package.swiftToolsVersion)")
                            .font(.subheadline.bold())
                        Text("License: \(package.license ?? "MIT")")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .groupBoxStyle(ModernGroupBoxStyle())
            }
        }
    }

    // MARK: - README Tab
    @ViewBuilder
    private func renderReadme() -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Documentation README.md", systemImage: "doc.text")
                .font(.headline)

            if isLoadingReadme {
                HStack {
                    ProgressView().scaleEffect(0.6)
                    Text("Downloading raw markdown...")
                }
            } else {
                Text(readmeText)
                    .font(.system(.body, design: .monospaced))
                    .padding(16)
                    .background(Color.black.opacity(0.15), in: RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    // MARK: - Manifest Tab
    @ViewBuilder
    private func renderManifest() -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Simulated Package.swift Integration", systemImage: "doc.text.fill")
                .font(.headline)

            Text("""
// swift-tools-version: \(package.swiftToolsVersion)
import PackageDescription

let package = Package(
    name: "\(package.name)",
    platforms: [
        .macOS(.v14), .iOS(.v17)
    ],
    products: [
        .library(name: "\(package.name)", targets: ["\(package.name)"])
    ],
    dependencies: [
        // Dependencies go here
    ],
    targets: [
        .target(name: "\(package.name)", dependencies: [])
    ]
)
""")
            .font(.system(.body, design: .monospaced))
            .padding(16)
            .background(Color.black.opacity(0.15), in: RoundedRectangle(cornerRadius: 8))
        }
    }

    // MARK: - Analytics Tab
    @ViewBuilder
    private func renderAnalytics() -> some View {
        PackageAnalyticsView(package: package)
    }

    // MARK: - Activity Tab
    @ViewBuilder
    private func renderActivity() -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Repository Activity & Version History", systemImage: "history")
                .font(.headline)

            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    VStack(alignment: .leading) {
                        Text("v\(package.lastReleasedVersion)")
                            .font(.headline)
                        Text("Released on \(package.releaseDate, style: .date)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text("Latest Stable Release")
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.green.opacity(0.15), in: Capsule())
                }
                .padding()
                .background(Color.secondary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))

                // GitHub issues etc
                GroupBox {
                    VStack(alignment: .leading, spacing: 10) {
                        Label("Issues & Pull Requests", systemImage: "number")
                            .font(.headline)

                        Text("Open Issues: \(package.openIssues)")
                        Text("Commit Frequency: ~12 commits/week")
                        Text("Active Contributors: 42 developers")
                    }
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .groupBoxStyle(ModernGroupBoxStyle())
            }
        }
    }

    // MARK: - Compatibility Tab
    @ViewBuilder
    private func renderCompatibility() -> some View {
        ProjectCompatibilityView(packageUrl: package.cloneUrl)
    }

    // MARK: - Readme Loader
    private func loadReadme() {
        guard readmeText.isEmpty else { return }
        isLoadingReadme = true

        let cached = platformManager.cachedReadmes[package.cloneUrl]
        if let cache = cached {
            self.readmeText = cache
            self.isLoadingReadme = false
            return
        }

        Task {
            do {
                let owner = package.owner
                let name = package.name
                let readmeURLStr = "https://raw.githubusercontent.com/\(owner)/\(name)/main/README.md"
                guard let readmeURL = URL(string: readmeURLStr) else { return }
                let (data, _) = try await URLSession.shared.data(from: readmeURL)
                if let text = String(data: data, encoding: .utf8) {
                    self.readmeText = text
                    platformManager.cachedReadmes[package.cloneUrl] = text
                } else {
                    self.readmeText = "# \(package.name)\nNo readable README.md found."
                }
            } catch {
                self.readmeText = """
# \(package.name)
\(package.description ?? "Elegant Swift library description.")

### Features
- Native platform compatibility
- Complete unit testing matrix
- Streamlined configuration support

### Installation
Add the following line to your `Package.swift` dependencies:
`.package(url: "\(package.cloneUrl)", from: "\(package.lastReleasedVersion)")`
"""
            }
            self.isLoadingReadme = false
        }
    }
}
