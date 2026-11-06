import Foundation

public struct RuntimeDTO: Decodable, Sendable {
    public let identifier: String
    public let name: String
    public let version: String
    public let buildversion: String?
    public let platform: String?
    public let isAvailable: Bool
    public let supportedArchitectures: [String]?

    enum CodingKeys: String, CodingKey {
        case identifier, name, version, buildversion, platform
        case isAvailable, availability, supportedArchitectures
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        identifier = try c.decode(String.self, forKey: .identifier)
        name = try c.decode(String.self, forKey: .name)
        version = try c.decode(String.self, forKey: .version)
        buildversion = try c.decodeIfPresent(String.self, forKey: .buildversion)
        platform = try c.decodeIfPresent(String.self, forKey: .platform)
        supportedArchitectures = try c.decodeIfPresent([String].self, forKey: .supportedArchitectures)

        if let flag = try? c.decodeIfPresent(Bool.self, forKey: .isAvailable) {
            isAvailable = flag ?? true
        } else if let legacy = try? c.decodeIfPresent(String.self, forKey: .isAvailable) {
            isAvailable = legacy.lowercased() == "true" || legacy == "1"
        } else if let legacyAvailability = try? c.decodeIfPresent(String.self, forKey: .availability) {
            isAvailable = !legacyAvailability.lowercased().contains("unavailable")
        } else {
            isAvailable = true
        }
    }
}

public struct DeviceDTO: Decodable, Sendable {
    public let udid: String
    public let name: String
    public let state: String
    public let deviceTypeIdentifier: String?
    public let isAvailable: Bool
    public let availabilityError: String?

    enum CodingKeys: String, CodingKey {
        case udid, name, state, deviceTypeIdentifier
        case isAvailable, availability, availabilityError
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        udid = try c.decode(String.self, forKey: .udid)
        name = try c.decode(String.self, forKey: .name)
        state = try c.decode(String.self, forKey: .state)
        deviceTypeIdentifier = try c.decodeIfPresent(String.self, forKey: .deviceTypeIdentifier)
        availabilityError = try c.decodeIfPresent(String.self, forKey: .availabilityError)

        if let flag = try? c.decodeIfPresent(Bool.self, forKey: .isAvailable) {
            isAvailable = flag ?? true
        } else if let legacy = try? c.decodeIfPresent(String.self, forKey: .isAvailable) {
            isAvailable = legacy.lowercased() == "true" || legacy == "1"
        } else if let legacyAvailability = try? c.decodeIfPresent(String.self, forKey: .availability) {
            isAvailable = !legacyAvailability.lowercased().contains("unavailable")
        } else {
            isAvailable = true
        }
    }
}

public struct DeviceTypeDTO: Decodable, Sendable {
    public let identifier: String
    public let name: String
    public let productFamily: String?
    public let bundlePath: String?
}

public struct PairedDeviceRef: Decodable, Sendable {
    public let udid: String
    public let name: String
    public let state: String
}

public struct PairDTO: Decodable, Sendable {
    public let watch: PairedDeviceRef
    public let phone: PairedDeviceRef
}

public struct SimctlListResponse: Decodable, Sendable {
    public let runtimes: [RuntimeDTO]?
    public let devices: [String: [DeviceDTO]]?
    public let devicetypes: [DeviceTypeDTO]?
    public let pairs: [String: PairDTO]?
}
