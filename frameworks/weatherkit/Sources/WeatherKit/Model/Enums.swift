import Foundation

public enum WeatherCondition: String, CaseIterable, Codable, Hashable, Sendable, CustomStringConvertible {
    case blizzard
    case blowingDust
    case blowingSnow
    case breezy
    case clear
    case cloudy
    case drizzle
    case flurries
    case foggy
    case freezingDrizzle
    case freezingRain
    case frigid
    case hail
    case haze
    case heavyRain
    case heavySnow
    case hot
    case hurricane
    case isolatedThunderstorms
    case mostlyClear
    case mostlyCloudy
    case partlyCloudy
    case rain
    case scatteredThunderstorms
    case sleet
    case smoky
    case snow
    case strongStorms
    case sunFlurries
    case sunShowers
    case thunderstorms
    case tropicalStorm
    case windy
    case wintryMix

    public var description: String {
        switch self {
        case .blowingDust: return "Dust"
        case .foggy: return "Fog"
        case .frigid: return "Cold"
        case .smoky: return "Smoke"
        case .strongStorms: return "Severe Thunderstorm"
        case .thunderstorms: return "Thunderstorm"
        default: return CaseName.words(rawValue).map(CaseName.capitalized).joined(separator: " ")
        }
    }

    public var accessibilityDescription: String { description.lowercased() }
}

public enum Precipitation: String, CaseIterable, Codable, Hashable, Sendable, CustomStringConvertible {
    case none
    case hail
    case mixed
    case rain
    case sleet
    case snow

    public var description: String {
        switch self {
        case .none: return ""
        case .mixed: return "wintry mix"
        default: return rawValue
        }
    }

    public var accessibilityDescription: String { description }
}

public enum PressureTrend: String, CaseIterable, Codable, Hashable, Sendable, CustomStringConvertible {
    case rising
    case falling
    case steady

    public var description: String {
        switch self {
        case .rising: return "Rising"
        case .falling: return "Falling"
        case .steady: return "Steady"
        }
    }

    public var accessibilityDescription: String { description }
}

public enum WeatherSeverity: String, CaseIterable, Codable, Hashable, Sendable, CustomStringConvertible {
    case minor
    case moderate
    case severe
    case extreme
    case unknown

    public var description: String { rawValue }

    public var accessibilityDescription: String { description }
}

public enum MoonPhase: String, CaseIterable, Codable, Hashable, Sendable, CustomStringConvertible {
    case new
    case waxingCrescent
    case firstQuarter
    case waxingGibbous
    case full
    case waningGibbous
    case lastQuarter
    case waningCrescent

    public var description: String {
        switch self {
        case .new: return "New Moon"
        case .waxingCrescent: return "Waxing Crescent"
        case .firstQuarter: return "First Quarter"
        case .waxingGibbous: return "Waxing Gibbous"
        case .full: return "Full Moon"
        case .waningGibbous: return "Waning Gibbous"
        case .lastQuarter: return "Last Quarter"
        case .waningCrescent: return "Waning Crescent"
        }
    }

    public var accessibilityDescription: String { description }

    public var symbolName: String {
        "moonphase." + description.lowercased().split(separator: " ").joined(separator: ".")
    }
}

enum CaseName {
    static func words(_ name: String) -> [String] {
        var result: [String] = []
        var current = ""
        for character in name {
            if character.isUppercase, !current.isEmpty {
                result.append(current)
                current = ""
            }
            current.append(character)
        }
        if !current.isEmpty { result.append(current) }
        return result.map { $0.lowercased() }
    }

    static func capitalized(_ word: String) -> String {
        guard let first = word.first else { return word }
        return first.uppercased() + word.dropFirst()
    }
}
