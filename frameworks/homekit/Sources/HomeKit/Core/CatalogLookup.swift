import Foundation

public struct SwiftCodeHomeCatalogEntry: Hashable, Sendable {
    public let constantName: String
    public let name: String
    public let identifier: String
    public let shortID: UInt32?
    public let introduced: String
    public let deprecated: String?

    public init(constantName: String, name: String, identifier: String, shortID: UInt32?,
                introduced: String, deprecated: String?) {
        self.constantName = constantName
        self.name = name
        self.identifier = identifier
        self.shortID = shortID
        self.introduced = introduced
        self.deprecated = deprecated
    }
}

public struct SwiftCodeValueEnumerationEntry: Hashable, Sendable {
    public let name: String
    public let introduced: String
    public let cases: [Case]

    public struct Case: Hashable, Sendable {
        public let value: Int
        public let name: String
    }

    public init(name: String, introduced: String, cases: [(Int, String)]) {
        self.name = name
        self.introduced = introduced
        self.cases = cases.map { Case(value: $0.0, name: $0.1) }
    }
}

public enum SwiftCodeHomeCatalog {
    public static let hapBaseSuffix = "-0000-1000-8000-0026BB765291"

    public static var allConstants: [SwiftCodeHomeCatalogEntry] {
        serviceTypes + characteristicTypes + accessoryCategoryTypes + metadataFormats + metadataUnits
            + characteristicProperties + actionSetTypes + significantEvents + keyPaths + otherConstants
    }

    private static let servicesByID: [String: SwiftCodeHomeCatalogEntry] =
        Dictionary(uniqueKeysWithValues: serviceTypes.map { ($0.identifier, $0) })
    private static let characteristicsByID: [String: SwiftCodeHomeCatalogEntry] =
        Dictionary(uniqueKeysWithValues: characteristicTypes.map { ($0.identifier, $0) })
    private static let categoriesByID: [String: SwiftCodeHomeCatalogEntry] =
        Dictionary(uniqueKeysWithValues: accessoryCategoryTypes.map { ($0.identifier, $0) })

    public static func serviceType(_ identifier: String) -> SwiftCodeHomeCatalogEntry? {
        servicesByID[normalizedTypeUUID(identifier) ?? identifier]
    }

    public static func characteristicType(_ identifier: String) -> SwiftCodeHomeCatalogEntry? {
        characteristicsByID[normalizedTypeUUID(identifier) ?? identifier]
    }

    public static func accessoryCategoryType(_ identifier: String) -> SwiftCodeHomeCatalogEntry? {
        categoriesByID[identifier.uppercased()]
    }

    public static func normalizedTypeUUID(_ text: String) -> String? {
        var t = text.trimmingCharacters(in: .whitespaces)
        if t.lowercased().hasPrefix("0x") { t = String(t.dropFirst(2)) }
        if t.count <= 8, !t.isEmpty, t.allSatisfy(\.isHexDigit) {
            return String(repeating: "0", count: 8 - t.count) + t.uppercased() + hapBaseSuffix
        }
        if let u = UUID(uuidString: t) { return u.uuidString.uppercased() }
        return nil
    }

    public static func wireTypeString(_ identifier: String) -> String {
        let full = normalizedTypeUUID(identifier) ?? identifier
        if full.hasSuffix(hapBaseSuffix) {
            let head = full.prefix(8)
            let trimmed = head.drop(while: { $0 == "0" })
            return trimmed.isEmpty ? "0" : String(trimmed)
        }
        return full
    }

    public static func localizedDescription(forType identifier: String) -> String? {
        guard let entry = serviceType(identifier) ?? characteristicType(identifier) else { return nil }
        return words(entry.name)
    }

    public static func localizedDescription(forCategory identifier: String) -> String {
        guard let entry = accessoryCategoryType(identifier) else { return "Other" }
        return words(entry.name)
    }

    static func words(_ name: String) -> String {
        let special: [String: String] = [
            "PM2_5Density": "PM2.5 Density", "PM10Density": "PM10 Density",
            "WiFiRouter": "Wi-Fi Router", "WiFiSatellite": "Wi-Fi Satellite",
            "WiFiSatelliteStatus": "Wi-Fi Satellite Status", "WANStatusList": "WAN Status List",
            "IPCamera": "IP Camera", "CameraRTPStreamManagement": "Camera RTP Stream Management",
            "SupportedRTPConfiguration": "Supported RTP Configuration", "AirPort": "AirPort",
        ]
        if let s = special[name] { return s }
        var out = ""
        let chars = Array(name)
        for (i, ch) in chars.enumerated() {
            if i > 0, ch.isUppercase {
                let prevLower = chars[i - 1].isLowercase || chars[i - 1].isNumber
                let nextLower = i + 1 < chars.count && chars[i + 1].isLowercase
                if prevLower || (chars[i - 1].isUppercase && nextLower) { out.append(" ") }
            }
            out.append(ch)
        }
        return out
    }

    public static let hapCategories: [Int: String] = [
        0: HMAccessoryCategoryTypeOther,
        1: HMAccessoryCategoryTypeOther,
        2: HMAccessoryCategoryTypeBridge,
        3: HMAccessoryCategoryTypeFan,
        4: HMAccessoryCategoryTypeGarageDoorOpener,
        5: HMAccessoryCategoryTypeLightbulb,
        6: HMAccessoryCategoryTypeDoorLock,
        7: HMAccessoryCategoryTypeOutlet,
        8: HMAccessoryCategoryTypeSwitch,
        9: HMAccessoryCategoryTypeThermostat,
        10: HMAccessoryCategoryTypeSensor,
        11: HMAccessoryCategoryTypeSecuritySystem,
        12: HMAccessoryCategoryTypeDoor,
        13: HMAccessoryCategoryTypeWindow,
        14: HMAccessoryCategoryTypeWindowCovering,
        15: HMAccessoryCategoryTypeProgrammableSwitch,
        16: HMAccessoryCategoryTypeRangeExtender,
        17: HMAccessoryCategoryTypeIPCamera,
        19: HMAccessoryCategoryTypeAirPurifier,
        20: HMAccessoryCategoryTypeAirHeater,
        21: HMAccessoryCategoryTypeAirConditioner,
        22: HMAccessoryCategoryTypeAirHumidifier,
        23: HMAccessoryCategoryTypeAirDehumidifier,
        28: HMAccessoryCategoryTypeSprinkler,
        29: HMAccessoryCategoryTypeFaucet,
        30: HMAccessoryCategoryTypeShowerHead,
    ]

    public static func categoryType(forHAPCategory number: Int) -> String {
        hapCategories[number] ?? HMAccessoryCategoryTypeOther
    }
}
