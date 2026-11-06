import SwiftUI

/// Ported from SwiftCode-Legacy `SwiftCode/Views/GitHub/GitHubDiscoveryView.swift`
/// (the `DependencyGitHubDiscoveryView` search-parameters sidebar)
/// (Dylan's own code; direct port authorised under MIT).
///
/// Search filters for GitHub package discovery: topic, owner / org,
/// license, language, minimum stars, archived handling, and verified-only.
///
/// Query composition mirrors Legacy's `triggerSearch`: the keyword plus
/// `topic:` / `user:` / `org:` / `archived:` qualifiers are composed into
/// one query string. License, language, and minimum stars are NOT put in
/// the string — `PackageDiscoveryStore.executeGitHubSearch(query:language:
/// license:minStars:)` already appends the `language:`, `license:`, and
/// `stars:>=` qualifiers itself. Verified-only is a client-side filter on
/// the returned results (there is no GitHub search qualifier for it).
public struct PackageDiscoveryFilters: Equatable {
    public var topic = ""
    public var ownerOrOrg = ""
    public var ownerKind: OwnerKind = .user
    public var license = ""
    public var language = "swift"
    public var minStars = 0
    public var archived: ArchivedOption = .any
    public var verifiedOnly = false

    public enum OwnerKind: String, CaseIterable {
        case user
        case org

        var qualifier: String { rawValue }
        var displayName: String {
            switch self {
            case .user: return "User"
            case .org: return "Organization"
            }
        }
    }

    public enum ArchivedOption: String, CaseIterable {
        case any = "Any"
        case only = "Archived only"
        case exclude = "Exclude archived"
    }

    public static let commonLicenses = ["", "mit", "apache-2.0", "gpl-3.0", "bsd-3-clause", "mpl-2.0", "lgpl-3.0", "unlicense"]

    public init() {}

    /// The composed GitHub search query for `keyword` plus the filters.
    public func composedQuery(keyword: String) -> String {
        var parts: [String] = []
        let trimmedKeyword = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedKeyword.isEmpty { parts.append(trimmedKeyword) }
        let topic = topic.trimmingCharacters(in: .whitespacesAndNewlines)
        if !topic.isEmpty { parts.append("topic:\(topic)") }
        let owner = ownerOrOrg.trimmingCharacters(in: .whitespacesAndNewlines)
        if !owner.isEmpty { parts.append("\(ownerKind.qualifier):\(owner)") }
        switch archived {
        case .any: break
        case .only: parts.append("archived:true")
        case .exclude: parts.append("archived:false")
        }
        return parts.joined(separator: " ")
    }
}

/// The search-parameters sidebar panel for package discovery.
public struct PackageDiscoveryFiltersView: View {
    @Binding public var filters: PackageDiscoveryFilters

    public init(filters: Binding<PackageDiscoveryFilters>) {
        self._filters = filters
    }

    public var body: some View {
        Form {
            Section("Search Filters") {
                TextField("Topic (e.g. networking)", text: $filters.topic)
                    .textFieldStyle(.roundedBorder)

                Picker("Owner kind", selection: $filters.ownerKind) {
                    ForEach(PackageDiscoveryFilters.OwnerKind.allCases, id: \.self) { kind in
                        Text(kind.displayName).tag(kind)
                    }
                }
                .pickerStyle(.segmented)
                TextField("Owner / organization", text: $filters.ownerOrOrg)
                    .textFieldStyle(.roundedBorder)

                Picker("License", selection: $filters.license) {
                    ForEach(PackageDiscoveryFilters.commonLicenses, id: \.self) { license in
                        Text(license.isEmpty ? "Any license" : license).tag(license)
                    }
                }

                TextField("Language", text: $filters.language)
                    .textFieldStyle(.roundedBorder)

                Stepper("Minimum stars: \(filters.minStars)", value: $filters.minStars, in: 0...10000, step: 10)

                Picker("Archived", selection: $filters.archived) {
                    ForEach(PackageDiscoveryFilters.ArchivedOption.allCases, id: \.self) { option in
                        Text(option.rawValue).tag(option)
                    }
                }

                Toggle("Verified packages only", isOn: $filters.verifiedOnly)
            }
        }
        .formStyle(.grouped)
    }
}
