import Foundation

public enum DeploymentStatus: String, Codable, Sendable, CaseIterable, Hashable {
    case idle = "Idle"
    case savingProject = "Saving Project"
    case validatingEnvironment = "Validating Environment"
    case resolvingBuildTarget = "Resolving Build Target"
    case resolvingSigning = "Resolving Signing"
    case buildingProject = "Building Project"
    case validatingBuild = "Validating Build"
    case installingApplication = "Installing Application"
    case launchingApplication = "Launching Application"
    case running = "Running"
    case completed = "Completed"
    case failed = "Failed"
    case cancelled = "Cancelled"

    public var description: String {
        return self.rawValue
    }
}
