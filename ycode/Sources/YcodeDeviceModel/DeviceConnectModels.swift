import Foundation

/// The DeviceConnectKit model layer, ported from Legacy
/// (`SwiftCode/Views/Build/DeviceConnectKit/Models/`): the physical
/// iOS-device connect / build / deploy subsystem. Ycode's Device Hub
/// covers simulators and remote sessions; this is the missing
/// physical-device side (README "Further out": signing, distribution
/// and physical devices).
///
/// Two deliberate deviations from Legacy, both recorded here:
/// - Legacy's `BuildStatus` is renamed `DeviceBuildStatus`:
///   `YcodeBuild` already defines a `BuildStatus`, and the two
///   modules meet in `YcodeUI`.
/// - `DeviceMetrics` gains `isAvailable` (default `true`) and an
///   `.unavailable` value. Legacy's runtime monitor fabricated
///   random CPU/memory numbers when it had none; this port reports
///   real liveness only (see `RuntimeCoordinator`) and marks the
///   numbers unavailable instead of inventing them.
public enum DeviceBuildStatus: String, Codable, Sendable, CaseIterable, Hashable {
    case idle = "Idle"
    case building = "Building"
    case succeeded = "Succeeded"
    case failed = "Failed"
    case cancelled = "Cancelled"

    public var description: String {
        return self.rawValue
    }
}

public struct ConnectedDevice: Identifiable, Codable, Sendable, Hashable {
    public var id: String { udid }
    public let name: String
    public let model: String
    public let productType: String
    public let platform: String
    public let osVersion: String
    public let buildVersion: String
    public let architecture: String
    public let udid: String

    // Connection
    public let isConnected: Bool
    public let isAvailable: Bool
    public let isBusy: Bool
    public let isOffline: Bool
    public let isWireless: Bool
    public let isUSB: Bool

    // Development Mode
    public let isDeveloperModeEnabled: Bool
    public let isTrusted: Bool
    public let isDeploymentSupported: Bool
    public let isSigningCompatible: Bool

    public init(
        name: String,
        model: String,
        productType: String,
        platform: String,
        osVersion: String,
        buildVersion: String,
        architecture: String,
        udid: String,
        isConnected: Bool = true,
        isAvailable: Bool = true,
        isBusy: Bool = false,
        isOffline: Bool = false,
        isWireless: Bool = false,
        isUSB: Bool = true,
        isDeveloperModeEnabled: Bool = true,
        isTrusted: Bool = true,
        isDeploymentSupported: Bool = true,
        isSigningCompatible: Bool = true
    ) {
        self.name = name
        self.model = model
        self.productType = productType
        self.platform = platform
        self.osVersion = osVersion
        self.buildVersion = buildVersion
        self.architecture = architecture
        self.udid = udid
        self.isConnected = isConnected
        self.isAvailable = isAvailable
        self.isBusy = isBusy
        self.isOffline = isOffline
        self.isWireless = isWireless
        self.isUSB = isUSB
        self.isDeveloperModeEnabled = isDeveloperModeEnabled
        self.isTrusted = isTrusted
        self.isDeploymentSupported = isDeploymentSupported
        self.isSigningCompatible = isSigningCompatible
    }
}

public struct DeploymentHistory: Identifiable, Codable, Sendable, Hashable {
    public let id: UUID
    public let projectName: String
    public let deviceName: String
    public let deviceUDID: String
    public let timestamp: Date
    public let duration: TimeInterval
    public let buildResult: DeviceBuildStatus
    public let deployResult: DeploymentStatus
    public let runResult: RuntimeStatus

    public init(
        id: UUID = UUID(),
        projectName: String,
        deviceName: String,
        deviceUDID: String,
        timestamp: Date = Date(),
        duration: TimeInterval,
        buildResult: DeviceBuildStatus,
        deployResult: DeploymentStatus,
        runResult: RuntimeStatus
    ) {
        self.id = id
        self.projectName = projectName
        self.deviceName = deviceName
        self.deviceUDID = deviceUDID
        self.timestamp = timestamp
        self.duration = duration
        self.buildResult = buildResult
        self.deployResult = deployResult
        self.runResult = runResult
    }
}

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

public struct DeviceEnvironment: Codable, Sendable, Hashable {
    public var xcodePath: String?
    public var xcodeVersion: String?
    public var commandLineToolsVersion: String?
    public var macOSVersion: String
    public var hasiOSSDK: Bool
    public var hasSimulatorSDK: Bool
    public var isSigningSetup: Bool
    public var derivedDataPath: String?
    public var swiftVersion: String?

    public init(
        xcodePath: String? = nil,
        xcodeVersion: String? = nil,
        commandLineToolsVersion: String? = nil,
        macOSVersion: String = "macOS Unknown",
        hasiOSSDK: Bool = false,
        hasSimulatorSDK: Bool = false,
        isSigningSetup: Bool = false,
        derivedDataPath: String? = nil,
        swiftVersion: String? = nil
    ) {
        self.xcodePath = xcodePath
        self.xcodeVersion = xcodeVersion
        self.commandLineToolsVersion = commandLineToolsVersion
        self.macOSVersion = macOSVersion
        self.hasiOSSDK = hasiOSSDK
        self.hasSimulatorSDK = hasSimulatorSDK
        self.isSigningSetup = isSigningSetup
        self.derivedDataPath = derivedDataPath
        self.swiftVersion = swiftVersion
    }
}

public struct DeviceLog: Identifiable, Codable, Sendable, Hashable {
    public enum LogType: String, Codable, Sendable {
        case build
        case runtime
        case system
        case diagnostics
    }

    public enum Severity: String, Codable, Sendable {
        case info
        case warning
        case error
        case debug
    }

    public let id: UUID
    public let timestamp: Date
    public let type: LogType
    public let severity: Severity
    public let message: String
    public let subsystem: String
    public let category: String

    public init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        type: LogType,
        severity: Severity = .info,
        message: String,
        subsystem: String = "com.swiftcode.deviceconnect",
        category: String = "General"
    ) {
        self.id = id
        self.timestamp = timestamp
        self.type = type
        self.severity = severity
        self.message = message
        self.subsystem = subsystem
        self.category = category
    }
}

public struct DeviceMetrics: Codable, Sendable, Hashable {
    public var cpuUsage: Double // percentage
    public var memoryUsage: Double // megabytes
    public var batteryLevel: Double // percentage
    public var activeThreads: Int
    public var diskAvailable: Double // gigabytes
    /// False when no live values could be read: the numbers are
    /// unknown, not zero. See `RuntimeCoordinator`.
    public var isAvailable: Bool

    public init(
        cpuUsage: Double = 0,
        memoryUsage: Double = 0,
        batteryLevel: Double = 100,
        activeThreads: Int = 1,
        diskAvailable: Double = 0,
        isAvailable: Bool = true
    ) {
        self.cpuUsage = cpuUsage
        self.memoryUsage = memoryUsage
        self.batteryLevel = batteryLevel
        self.activeThreads = activeThreads
        self.diskAvailable = diskAvailable
        self.isAvailable = isAvailable
    }

    /// The honest "no live values" reading: zeros with
    /// `isAvailable == false`, never fabricated numbers.
    public static let unavailable = DeviceMetrics(
        cpuUsage: 0, memoryUsage: 0, batteryLevel: 0,
        activeThreads: 0, diskAvailable: 0, isAvailable: false)
}

public struct DeviceSession: Identifiable, Codable, Sendable, Hashable {
    public let id: UUID
    public let deviceUDID: String
    public let deviceName: String
    public let projectName: String
    public let configuration: String // Debug, Release
    public let startTime: Date
    public var endTime: Date?

    // Statuses
    public var buildStatus: DeviceBuildStatus
    public var deploymentStatus: DeploymentStatus
    public var runtimeStatus: RuntimeStatus
    public var signingStatus: SigningStatus

    // Durations and Metrics
    public var buildDuration: TimeInterval
    public var installDuration: TimeInterval
    public var launchDuration: TimeInterval
    public var totalDuration: TimeInterval {
        if let end = endTime {
            return end.timeIntervalSince(startTime)
        }
        return Date().timeIntervalSince(startTime)
    }

    // Logs and Diagnostics
    public var buildLogs: String
    public var runtimeLogs: String
    public var errors: [String]
    public var warnings: [String]
    public var suggestions: [String]

    public init(
        id: UUID = UUID(),
        deviceUDID: String,
        deviceName: String,
        projectName: String,
        configuration: String = "Debug",
        startTime: Date = Date(),
        endTime: Date? = nil,
        buildStatus: DeviceBuildStatus = .idle,
        deploymentStatus: DeploymentStatus = .idle,
        runtimeStatus: RuntimeStatus = .idle,
        signingStatus: SigningStatus = .idle,
        buildDuration: TimeInterval = 0,
        installDuration: TimeInterval = 0,
        launchDuration: TimeInterval = 0,
        buildLogs: String = "",
        runtimeLogs: String = "",
        errors: [String] = [],
        warnings: [String] = [],
        suggestions: [String] = []
    ) {
        self.id = id
        self.deviceUDID = deviceUDID
        self.deviceName = deviceName
        self.projectName = projectName
        self.configuration = configuration
        self.startTime = startTime
        self.endTime = endTime
        self.buildStatus = buildStatus
        self.deploymentStatus = deploymentStatus
        self.runtimeStatus = runtimeStatus
        self.signingStatus = signingStatus
        self.buildDuration = buildDuration
        self.installDuration = installDuration
        self.launchDuration = launchDuration
        self.buildLogs = buildLogs
        self.runtimeLogs = runtimeLogs
        self.errors = errors
        self.warnings = warnings
        self.suggestions = suggestions
    }
}

public enum RuntimeStatus: String, Codable, Sendable, CaseIterable, Hashable {
    case idle = "Not Running"
    case launching = "Launching"
    case running = "Running"
    case terminated = "Terminated"
    case crashed = "Crashed"
    case disconnected = "Disconnected"

    public var description: String {
        return self.rawValue
    }
}

public enum SigningStatus: String, Codable, Sendable, CaseIterable, Hashable {
    case idle = "Unverified"
    case verifying = "Verifying"
    case valid = "Valid Signing"
    case invalid = "Invalid Profile/Certificate"
    case expired = "Expired Provisioning"

    public var description: String {
        return self.rawValue
    }
}
