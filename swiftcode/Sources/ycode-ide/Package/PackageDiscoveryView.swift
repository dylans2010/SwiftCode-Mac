import SwiftUI
import YcodeIDEShell

public struct PackageDiscoveryView: View {
    @State private var store = PackageDiscoveryStore()
    @State private var selectedCategory: String = "All"
    @State private var searchQuery: String = ""
    @State private var filters = PackageDiscoveryFilters()
    @State private var showFilters = false
    @State private var selectedPackage: PackageMetadata?
    @State private var installMessage: String?
    @State private var installRequirement: DependencyRequirementType = .from
    @State private var installValue: String = "1.0.0"
    @State private var securityReport: PackageCompatibilityReport?
    @State private var scanDependencies: [ParsedDependency] = []

    private let categories = ["All", "Networking", "Database", "UI", "Utility", "Analytics", "Cryptography"]

    public init() {}

    private var displayedSearchResults: [PackageMetadata] {
        filters.verifiedOnly ? store.searchResults.filter(\.isVerified) : store.searchResults
    }

    public var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                if showFilters {
                    PackageDiscoveryFiltersView(filters: $filters)
                    Divider()
                }
            List(selection: $selectedPackage) {
                Section("Starter catalog (curated)") {
                    ForEach(filtered(store.featuredPackages)) { pkg in packageRow(pkg) }
                }
                Section("Trending starter picks") {
                    ForEach(filtered(store.trendingPackages)) { pkg in packageRow(pkg) }
                }
                if !displayedSearchResults.isEmpty {
                    Section("Search results (live)") {
                        ForEach(displayedSearchResults) { pkg in packageRow(pkg) }
                    }
                }
                Section("Collections") {
                    ForEach(store.collections) { collection in
                        Label("\(collection.name) (\(collection.packageURLs.count))", systemImage: "folder")
                    }
                }
            }
            .listStyle(.sidebar)
            }
            .navigationTitle("Package Discovery")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button(showFilters ? "Hide Filters" : "Filters") { showFilters.toggle() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Refresh catalog") { Task { await store.refreshCatalog() } }
                }
            }
        } detail: {
            detail
        }
        .searchable(text: $searchQuery, prompt: "Search GitHub packages")
        .onSubmit(of: .search) {
            Task {
                await store.executeGitHubSearch(
                    query: filters.composedQuery(keyword: searchQuery),
                    language: filters.language,
                    license: filters.license,
                    minStars: filters.minStars
                )
            }
        }
    }

    private func filtered(_ packages: [PackageMetadata]) -> [PackageMetadata] {
        guard selectedCategory != "All" else { return packages }
        return packages.filter { $0.topics.contains(selectedCategory.lowercased()) }
    }

    private func packageRow(_ pkg: PackageMetadata) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(pkg.name).font(.headline)
            Text(pkg.description ?? "").font(.caption).foregroundStyle(.secondary).lineLimit(2)
            HStack(spacing: 8) {
                Label("\(pkg.stars)", systemImage: "star.fill").font(.caption2)
                Text(pkg.license ?? "No license").font(.caption2)
                if pkg.isVerified { Text("Verified").font(.caption2) }
            }
            .foregroundStyle(.secondary)
        }
        .tag(pkg as PackageMetadata?)
    }

    private var detail: some View {
        Group {
            if let pkg = selectedPackage {
                packageDetail(pkg)
            } else {
                ContentUnavailableView("Select a package", systemImage: "puzzlepiece", description: Text("Browse the starter catalog or search GitHub for Swift packages."))
            }
        }
    }

    private func packageDetail(_ pkg: PackageMetadata) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(pkg.name).font(.title2.bold())
                    Text(pkg.fullName).font(.caption).foregroundStyle(.secondary)
                    Text(pkg.description ?? "").font(.body)
                }
                HStack(spacing: 16) {
                    Label("\(pkg.stars) stars", systemImage: "star.fill")
                    Label("\(pkg.forks) forks", systemImage: "tuningfork")
                    Label("\(pkg.openIssues) open issues", systemImage: "exclamationmark.circle")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 4) {
                    LabeledContent("License", value: pkg.license ?? "Not declared")
                    LabeledContent("Swift tools", value: pkg.swiftToolsVersion)
                    LabeledContent("Platforms", value: pkg.platforms.joined(separator: ", "))
                    LabeledContent("Latest release", value: pkg.lastReleasedVersion)
                    LabeledContent("Clone URL", value: pkg.cloneUrl)
                }
                .font(.caption)

                Divider()
                Text("Install").font(.headline)
                Picker("Requirement", selection: $installRequirement) {
                    ForEach(DependencyRequirementType.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                TextField("Version / branch / revision", text: $installValue)
                    .textFieldStyle(.roundedBorder)
                HStack {
                    Button("Install package") {
                        Task {
                            let ok = await store.installPackage(pkg, requirementType: installRequirement, requirementValue: installValue)
                            installMessage = ok ? "Installed \(pkg.name)." : "Install failed — see the operation log. No project handler is configured."
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    Button(store.favoritePackages.contains(pkg.cloneUrl) ? "Remove from favorites" : "Add to favorites") {
                        store.toggleFavorite(url: pkg.cloneUrl)
                    }
                    .buttonStyle(.bordered)
                    Button(store.watchlistPackages.contains(pkg.cloneUrl) ? "Unwatch" : "Watch") {
                        store.toggleWatchlist(url: pkg.cloneUrl)
                    }
                    .buttonStyle(.bordered)
                }
                if let installMessage {
                    Text(installMessage).font(.caption).foregroundStyle(.secondary)
                }

                Divider()
                Text("Compatibility").font(.headline)
                let report = store.analyzeCompatibility(packageUrl: pkg.cloneUrl)
                LabeledContent("Health score", value: "\(report.healthScore)/100")
                ForEach(report.existingConflicts, id: \.self) { Text($0).font(.caption).foregroundStyle(.red) }
                ForEach(report.recommendations, id: \.self) { Text($0).font(.caption).foregroundStyle(.secondary) }

                Divider()
                Text("Security").font(.headline)
                let advisories = store.knownAdvisories.filter { $0.packageName.lowercased() == pkg.name.lowercased() }
                if advisories.isEmpty {
                    Text("No known advisories for this package in the local advisory list.").font(.caption).foregroundStyle(.secondary)
                } else {
                    ForEach(advisories) { advisory in
                        VStack(alignment: .leading) {
                            Text(advisory.title).font(.headline)
                            Text("\(advisory.severity) · affects \(advisory.affectedVersions) · fixed in \(advisory.fixedVersion)").font(.caption).foregroundStyle(.secondary)
                            Text(advisory.details).font(.caption)
                        }
                    }
                }
                Button("Run security scan on installed dependencies") {
                    Task { await store.executeSecurityScan(dependencies: scanDependencies) }
                }
                .disabled(store.securityScanRunning)
                Text("Security score: \(store.securityScore)/100").font(.caption)

                Divider()
                Text("Operation log").font(.headline)
                ForEach(store.operationLogs.suffix(10), id: \.self) { Text($0).font(.caption).foregroundStyle(.secondary) }
            }
            .padding()
        }
    }
}
