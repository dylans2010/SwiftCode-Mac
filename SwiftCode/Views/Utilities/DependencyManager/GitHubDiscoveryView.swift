import SwiftUI

struct DependencyGitHubDiscoveryView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(ProjectSessionStore.self) private var sessionStore
    @State private var platformManager = DependencyPlatformManager.shared

    // Filters and query state
    @State private var keyword: String = ""
    @State private var topic: String = ""
    @State private var owner: String = ""
    @State private var organization: String = ""
    @State private var selectedLicense: String = "All"
    @State private var selectedLanguage: String = "Swift"
    @State private var minStars: Double = 0
    @State private var includeArchived: Bool = false
    @State private var onlyVerified: Bool = false
    @State private var sortCriteria: String = "stars"

    let licenses = ["All", "MIT", "Apache-2.0", "GPL-3.0", "BSD-3-Clause"]
    let languages = ["Swift", "Objective-C", "C++", "C"]

    var body: some View {
        VStack(spacing: 0) {
            // Header Bar
            HStack {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.title3)
                }
                .buttonStyle(.plain)
                .keyboardShortcut("[", modifiers: .command)

                Text("GitHub Package Discovery Engine")
                    .font(.title2.bold())

                Spacer()

                if platformManager.isOperationRunning {
                    ProgressView()
                        .scaleEffect(0.6)
                        .padding(.trailing, 8)
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            HSplitView {
                searchParametersSidebarPanel

                // Content Results View
                VStack(spacing: 0) {
                    if platformManager.searchResults.isEmpty {
                        VStack(spacing: 16) {
                            Spacer()
                            Image(systemName: "magnifyingglass.circle")
                                .font(.system(size: 48))
                                .foregroundStyle(.secondary)
                            Text("Start discovering packages containing 'Package.swift' manifest on GitHub.")
                                .font(.headline)
                                .foregroundStyle(.secondary)
                            Text("Refine filters in the sidebar and trigger a secure search query.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                        }
                    } else {
                        List {
                            ForEach(platformManager.searchResults) { pkg in
                                NavigationLink(destination: PackageDetailsView(package: pkg)) {
                                    HStack(spacing: 16) {
                                        VStack(alignment: .leading, spacing: 6) {
                                            HStack {
                                                Text(pkg.fullName)
                                                    .font(.headline)
                                                    .foregroundStyle(.blue)

                                                if pkg.isVerified || onlyVerified {
                                                    Image(systemName: "checkmark.seal.fill")
                                                        .foregroundStyle(.blue)
                                                }
                                            }

                                            if let desc = pkg.description {
                                                Text(desc)
                                                    .font(.caption)
                                                    .foregroundStyle(.secondary)
                                                    .lineLimit(2)
                                            }

                                            HStack(spacing: 16) {
                                                Label("\(pkg.stars) stars", systemImage: "star.fill")
                                                    .foregroundStyle(.yellow)
                                                Label("\(pkg.forks) forks", systemImage: "arrow.branch")
                                                Label(pkg.license ?? "MIT", systemImage: "doc.text")
                                                Label(selectedLanguage, systemImage: "chevron.left.forwardslash.chevron.right")
                                            }
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                        }
                                        .padding(.vertical, 8)

                                        Spacer()

                                        Button {
                                            platformManager.toggleFavorite(url: pkg.cloneUrl)
                                        } label: {
                                            Image(systemName: platformManager.favoritePackages.contains(pkg.cloneUrl) ? "star.fill" : "star")
                                                .foregroundStyle(.yellow)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(NSColor.controlBackgroundColor))
            }
        }
        .background(Color(NSColor.windowBackgroundColor))
    }

    private func triggerSearch() {
        var queryParts: [String] = []
        if !keyword.isEmpty {
            queryParts.append(keyword)
        }
        if !topic.isEmpty {
            queryParts.append("topic:\(topic)")
        }
        if !owner.isEmpty {
            queryParts.append("user:\(owner)")
        }
        if !organization.isEmpty {
            queryParts.append("org:\(organization)")
        }
        if selectedLicense != "All" {
            queryParts.append("license:\(selectedLicense.lowercased())")
        }

        let queryStr = queryParts.isEmpty ? "swift" : queryParts.joined(separator: " ")

        Task {
            await platformManager.executeGitHubSearch(
                query: queryStr,
                language: selectedLanguage,
                license: selectedLicense,
                minStars: Int(minStars)
            )
        }
    }

    @ViewBuilder
    private var searchParametersSidebarPanel: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Search Parameters")
                .font(.headline)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 6) {
                Text("Keywords")
                    .font(.caption.bold())
                TextField("e.g. Alamofire, GRDB", text: $keyword)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Topic tag")
                    .font(.caption.bold())
                TextField("e.g. swiftui, caching", text: $topic)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Owner / User")
                    .font(.caption.bold())
                TextField("e.g. apple, pointfreeco", text: $owner)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Organization")
                    .font(.caption.bold())
                TextField("e.g. github, stripe", text: $organization)
                    .textFieldStyle(.roundedBorder)
            }

            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    Text("License")
                        .font(.caption.bold())
                    Picker("", selection: $selectedLicense) {
                        ForEach(licenses, id: \.self) { lic in
                            Text(lic).tag(lic)
                        }
                    }
                    .pickerStyle(.menu)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Language")
                        .font(.caption.bold())
                    Picker("", selection: $selectedLanguage) {
                        ForEach(languages, id: \.self) { lang in
                            Text(lang).tag(lang)
                        }
                    }
                    .pickerStyle(.menu)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Min Stars:")
                    Spacer()
                    Text("\(Int(minStars))")
                        .font(.system(.caption, design: .monospaced))
                }
                .font(.caption.bold())
                Slider(value: $minStars, in: 0...5000, step: 50)
            }

            Divider()

            Toggle("Include Archived Repos", isOn: $includeArchived)
            Toggle("Verified Maintainers Only", isOn: $onlyVerified)

            Spacer()

            Button {
                triggerSearch()
            } label: {
                Label("Search GitHub API", systemImage: "magnifyingglass")
                    .fontWeight(.bold)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(platformManager.isOperationRunning)
        }
        .padding(20)
        .frame(width: 280, maxHeight: .infinity)
        .background(Color(NSColor.windowBackgroundColor))
    }
}
