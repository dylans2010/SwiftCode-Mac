import Foundation

public enum SigningPlatform: Equatable, Sendable {
    case macOS
    case macCatalyst
    case simulator(String)
    case device(String)

    public init(sdk: String, variant: String?) {
        let base = String(sdk.prefix { $0.isLetter })
        if base == "macosx" { self = variant == "iosmac" ? .macCatalyst : .macOS }
        else if base.hasSuffix("simulator") { self = .simulator(base) }
        else { self = .device(base) }
    }

    public var isMac: Bool { self == .macOS || self == .macCatalyst }
    public var isSimulator: Bool { if case .simulator = self { true } else { false } }

    public var applicationIdentifierKey: String { isMac ? "com.apple.application-identifier" : "application-identifier" }
    public var getTaskAllowKey: String { isMac ? "com.apple.security.get-task-allow" : "get-task-allow" }

    public var profilePlatforms: [String] {
        switch self {
        case .macOS, .macCatalyst: ["OSX"]
        case .simulator(let s), .device(let s):
            switch s.replacingOccurrences(of: "simulator", with: "os") {
            case "iphoneos": ["iOS"]
            case "xros": ["xrOS", "visionOS"]
            case "appletvos": ["tvOS"]
            case "watchos": ["watchOS", "iOS"]
            case "driverkit": ["DriverKit", "OSX", "iOS"]
            default: [s]
            }
        }
    }
}

public struct ProvisioningProfile: Equatable, Sendable {
    public var uuid: String
    public var name: String
    public var teamIdentifiers: [String]
    public var teamName: String?
    public var appIDName: String?
    public var applicationIdentifierPrefixes: [String]
    public var platforms: [String]
    public var creationDate: Date?
    public var expirationDate: Date?
    public var entitlements: Entitlements
    public var provisionedDevices: [String]
    public var provisionsAllDevices: Bool
    public var certificateHashes: [String]
    public var isXcodeManaged: Bool
    public var path: String?

    public init(uuid: String, name: String, teamIdentifiers: [String], teamName: String? = nil, appIDName: String? = nil,
                applicationIdentifierPrefixes: [String] = [], platforms: [String], creationDate: Date? = nil, expirationDate: Date? = nil,
                entitlements: Entitlements, provisionedDevices: [String] = [], provisionsAllDevices: Bool = false,
                certificateHashes: [String], isXcodeManaged: Bool = false, path: String? = nil) {
        self.uuid = uuid
        self.name = name
        self.teamIdentifiers = teamIdentifiers
        self.teamName = teamName
        self.appIDName = appIDName
        self.applicationIdentifierPrefixes = applicationIdentifierPrefixes
        self.platforms = platforms
        self.creationDate = creationDate
        self.expirationDate = expirationDate
        self.entitlements = entitlements
        self.provisionedDevices = provisionedDevices
        self.provisionsAllDevices = provisionsAllDevices
        self.certificateHashes = certificateHashes.map { $0.uppercased() }
        self.isXcodeManaged = isXcodeManaged
        self.path = path
    }

    public enum DecodingError: Error, Equatable, CustomStringConvertible {
        case missingKey(String)
        public var description: String {
            switch self {
            case .missingKey(let k): "the profile has no \(k)"
            }
        }
    }

    public init(propertyList data: Data, path: String? = nil) throws {
        let d = try Entitlements.fromPropertyList(data)
        guard let uuid = d["UUID"]?.stringValue else { throw DecodingError.missingKey("UUID") }
        guard let name = d["Name"]?.stringValue else { throw DecodingError.missingKey("Name") }
        self.init(uuid: uuid, name: name,
                  teamIdentifiers: d["TeamIdentifier"]?.strings ?? [],
                  teamName: d["TeamName"]?.stringValue,
                  appIDName: d["AppIDName"]?.stringValue,
                  applicationIdentifierPrefixes: d["ApplicationIdentifierPrefix"]?.strings ?? [],
                  platforms: d["Platform"]?.strings ?? [],
                  creationDate: d["CreationDate"]?.dateValue,
                  expirationDate: d["ExpirationDate"]?.dateValue,
                  entitlements: d["Entitlements"]?.dictionaryValue ?? [:],
                  provisionedDevices: d["ProvisionedDevices"]?.strings ?? [],
                  provisionsAllDevices: d["ProvisionsAllDevices"]?.boolValue ?? false,
                  certificateHashes: (d["DeveloperCertificates"]?.arrayValue ?? []).compactMap(\.dataValue).map { SHA1.hex([UInt8]($0)) },
                  isXcodeManaged: d["IsXcodeManaged"]?.boolValue ?? false,
                  path: path)
    }

    public var applicationIdentifier: String? {
        (entitlements["application-identifier"] ?? entitlements["com.apple.application-identifier"])?.stringValue
    }

    public var applicationIdentifierPrefix: String? {
        applicationIdentifier.flatMap { id in id.firstIndex(of: ".").map { String(id[..<$0]) } } ?? applicationIdentifierPrefixes.first
    }

    public var bundleIdentifierPattern: String? {
        applicationIdentifier.flatMap { id in id.firstIndex(of: ".").map { String(id[id.index(after: $0)...]) } }
    }

    public var isWildcard: Bool { bundleIdentifierPattern?.hasSuffix("*") ?? false }

    public enum Kind: String, Sendable {
        case development, adHoc = "ad-hoc", enterprise, distribution
    }

    public var kind: Kind {
        if entitlements["get-task-allow"]?.boolValue == true || entitlements["com.apple.security.get-task-allow"]?.boolValue == true { return .development }
        if provisionsAllDevices { return .enterprise }
        if !provisionedDevices.isEmpty { return .adHoc }
        return .distribution
    }

    public func isExpired(at now: Date) -> Bool { expirationDate.map { $0 <= now } ?? false }

    public func covers(bundleIdentifier: String) -> Bool {
        guard let pattern = bundleIdentifierPattern else { return false }
        return EntitlementPolicy.pattern(pattern, matches: bundleIdentifier)
    }
}

public enum ProfileStore {
    public static func directories(environment: [String: String] = ProcessInfo.processInfo.environment) -> [String] {
        if let list = environment["SWIFTCODE_PROVISIONING_PROFILES"] {
            return list.split(separator: ":").map(String.init)
        }
        let home = environment["HOME"] ?? NSHomeDirectory()
        return [home + "/Library/Developer/Xcode/UserData/Provisioning Profiles",
                home + "/Library/MobileDevice/Provisioning Profiles"]
    }

    public static func contents(ofFile path: String, runner: CommandRunner = .system) -> Data? {
        guard let data = FileManager.default.contents(atPath: path) else { return nil }
        if data.starts(with: Array("<?xml".utf8)) || data.starts(with: Array("bplist".utf8)) { return data }
        guard FileManager.default.isExecutableFile(atPath: Keychain.security) else { return nil }
        let r = runner.run(Keychain.security, ["cms", "-D", "-i", path])
        return r.status == 0 ? r.output : nil
    }

    public static func load(directories: [String], runner: CommandRunner = .system) -> [ProvisioningProfile] {
        var out: [ProvisioningProfile] = []
        var seen = Set<String>()
        for dir in directories {
            let names = ((try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? []).sorted()
            for n in names where n.hasSuffix(".mobileprovision") || n.hasSuffix(".provisionprofile") {
                let path = dir + "/" + n
                guard let data = contents(ofFile: path, runner: runner),
                      let p = try? ProvisioningProfile(propertyList: data, path: path),
                      seen.insert(p.uuid).inserted else { continue }
                out.append(p)
            }
        }
        return out
    }
}
