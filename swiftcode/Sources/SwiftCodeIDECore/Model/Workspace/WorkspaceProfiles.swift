import Foundation
import Observation

/// A named workspace profile: a build configuration plus environment
/// variables and preferences (Legacy `WorkspaceProfile` /
/// `WorkspaceProfilesManager`, Dylan's own code, ported under MIT).
/// Profiles persist in UserDefaults under `SwiftCode.`-prefixed keys (Legacy
/// used `com.swiftcode.` keys). A profile is a saved selection, not a
/// build-system override: switching profiles records usage and exposes the
/// active profile for the build UI to read; applying a profile's
/// environment to a build is the caller's job.
public struct WorkspaceProfile: Identifiable, Codable, Equatable, Hashable, Sendable {
    public let id: UUID
    public var name: String
    public var buildConfiguration: String
    public var environmentVariables: [String: String]
    public var preferences: [String: String]
    public var lastUsed: Date? = nil

    public init(
        id: UUID = UUID(), name: String, buildConfiguration: String = "Debug",
        environmentVariables: [String: String] = [:], preferences: [String: String] = [:],
        lastUsed: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.buildConfiguration = buildConfiguration
        self.environmentVariables = environmentVariables
        self.preferences = preferences
        self.lastUsed = lastUsed
    }

    public static let empty = WorkspaceProfile(name: "", buildConfiguration: "Debug")
}

@Observable
@MainActor
public final class WorkspaceProfilesManager {
    public static let shared = WorkspaceProfilesManager()

    public var profiles: [WorkspaceProfile] = [] {
        didSet {
            persistProfiles()
            if !profiles.contains(where: { $0.id == activeProfileID }) {
                activeProfileID = profiles.first?.id
            } else {
                syncActiveProfileFromID()
            }
        }
    }

    public var activeProfileID: UUID? {
        didSet {
            persistActiveProfileID()
            syncActiveProfileFromID()
        }
    }

    public var activeProfile: WorkspaceProfile?

    private let profilesKey = "SwiftCode.workspaceProfiles"
    private let activeProfileKey = "SwiftCode.activeWorkspaceProfile"
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        loadState()
    }

    public func switchTo(_ profile: WorkspaceProfile) {
        guard profiles.contains(where: { $0.id == profile.id }) else { return }
        activeProfileID = profile.id
        recordUsage(profile)
    }

    public func add(_ profile: WorkspaceProfile) {
        profiles.append(profile)
        if activeProfileID == nil {
            activeProfileID = profile.id
        }
    }

    public func update(_ profile: WorkspaceProfile) {
        guard let index = profiles.firstIndex(where: { $0.id == profile.id }) else { return }
        profiles[index] = profile
        if activeProfileID == profile.id {
            activeProfile = profile
        }
    }

    public func delete(_ profile: WorkspaceProfile) {
        profiles.removeAll { $0.id == profile.id }
    }

    public func recordUsage(_ profile: WorkspaceProfile) {
        var updated = profile
        updated.lastUsed = Date()
        update(updated)
    }

    private func loadState() {
        let storedProfiles: [WorkspaceProfile]
        if let data = defaults.data(forKey: profilesKey),
           let decoded = try? JSONDecoder().decode([WorkspaceProfile].self, from: data) {
            storedProfiles = decoded
        } else {
            storedProfiles = []
        }
        profiles = storedProfiles
        if let idString = defaults.string(forKey: activeProfileKey),
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
        defaults.set(data, forKey: profilesKey)
    }

    private func persistActiveProfileID() {
        defaults.set(activeProfileID?.uuidString, forKey: activeProfileKey)
    }
}
