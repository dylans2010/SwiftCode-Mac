import Foundation

struct WorkspaceProfile: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var buildConfiguration: String
    var environmentVariables: [String: String]
    var preferences: [String: String]

    static let empty = WorkspaceProfile(
        id: UUID(),
        name: "",
        buildConfiguration: "Debug",
        environmentVariables: [:],
        preferences: [:]
    )
}

@MainActor
final class WorkspaceProfilesManager: ObservableObject {
    static let shared = WorkspaceProfilesManager()

    @Published private(set) var profiles: [WorkspaceProfile] = [] {
        didSet {
            persistProfiles()
            if !profiles.contains(where: { $0.id == activeProfileID }) {
                activeProfileID = profiles.first?.id
            } else {
                syncActiveProfileFromID()
            }
        }
    }

    @Published private(set) var activeProfileID: UUID? {
        didSet {
            persistActiveProfileID()
            syncActiveProfileFromID()
        }
    }

    @Published private(set) var activeProfile: WorkspaceProfile?

    private let profilesKey = "com.swiftcode.workspaceProfiles"
    private let activeProfileKey = "com.swiftcode.activeWorkspaceProfile"

    private init() {
        loadState()
    }

    func switchTo(_ profile: WorkspaceProfile) {
        guard profiles.contains(where: { $0.id == profile.id }) else { return }
        activeProfileID = profile.id
    }

    func add(_ profile: WorkspaceProfile) {
        profiles.append(profile)
        if activeProfileID == nil {
            activeProfileID = profile.id
        }
    }

    func update(_ profile: WorkspaceProfile) {
        guard let idx = profiles.firstIndex(where: { $0.id == profile.id }) else { return }
        profiles[idx] = profile
        if activeProfileID == profile.id {
            activeProfile = profile
        }
    }

    func delete(_ profile: WorkspaceProfile) {
        profiles.removeAll { $0.id == profile.id }
    }

    private func loadState() {
        let storedProfiles: [WorkspaceProfile]
        if let data = UserDefaults.standard.data(forKey: profilesKey),
           let decoded = try? JSONDecoder().decode([WorkspaceProfile].self, from: data) {
            storedProfiles = decoded
        } else {
            storedProfiles = []
        }

        profiles = storedProfiles

        if let idString = UserDefaults.standard.string(forKey: activeProfileKey),
           let storedID = UUID(uuidString: idString),
           storedProfiles.contains(where: { $0.id == storedID }) {
            activeProfileID = storedID
        } else {
            activeProfileID = storedProfiles.first?.id
        }

        syncActiveProfileFromID()
    }

    private func syncActiveProfileFromID() {
        activeProfile = profiles.first(where: { $0.id == activeProfileID })
    }

    private func persistProfiles() {
        guard let data = try? JSONEncoder().encode(profiles) else { return }
        UserDefaults.standard.set(data, forKey: profilesKey)
    }

    private func persistActiveProfileID() {
        UserDefaults.standard.set(activeProfileID?.uuidString, forKey: activeProfileKey)
    }
}
