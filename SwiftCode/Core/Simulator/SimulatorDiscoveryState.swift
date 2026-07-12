import Foundation

public enum DiscoveryStage: String, Sendable, Codable, Hashable, CaseIterable {
    case initializing = "Initializing discovery..."
    case detectingDeveloperDirectory = "Detecting active developer directory..."
    case verifyingXcode = "Verifying Xcode installation..."
    case verifyingXcrun = "Verifying xcrun tool..."
    case verifyingSimctl = "Verifying simctl tool..."
    case discoveringRuntimes = "Discovering installed runtimes..."
    case discoveringDevices = "Discovering configured devices..."
    case discoveringDeviceTypes = "Discovering available device templates..."
    case mergingAndPublishing = "Merging and resolving catalog mapping..."
    case complete = "Discovery complete"
}

public enum EmptyReason: String, Sendable, Codable, Hashable {
    case noRuntimesInstalled = "No simulator runtimes are installed."
    case cltOnlyInstall = "Command Line Tools-only active toolchain (missing full Xcode)."
}

public enum SimulatorDiscoveryState: Sendable {
    case idle
    case discovering(stage: DiscoveryStage)
    case loaded(SimulatorSnapshot)
    case empty(reason: EmptyReason)
    case failed(error: SimulatorDiscoveryError)
}
