import SwiftUI

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
