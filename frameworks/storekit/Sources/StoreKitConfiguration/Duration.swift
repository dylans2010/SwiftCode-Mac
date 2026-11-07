public enum PeriodUnit: String, Hashable, Sendable, CaseIterable, Codable {
    case day, week, month, year

    var designator: Character {
        switch self {
        case .day: return "D"
        case .week: return "W"
        case .month: return "M"
        case .year: return "Y"
        }
    }
}

public struct SubscriptionDuration: Hashable, Sendable, Codable, CustomStringConvertible {
    public var value: Int
    public var unit: PeriodUnit

    public init(value: Int, unit: PeriodUnit) {
        self.value = value
        self.unit = unit
    }

    public init?(iso8601 text: String) {
        guard text.count >= 3, text.first == "P", let last = text.last else { return nil }
        let digits = text.dropFirst().dropLast()
        guard !digits.isEmpty, digits.allSatisfy({ $0.isASCII && $0.isNumber }), let n = Int(digits), n >= 1 else { return nil }
        guard let unit = PeriodUnit.allCases.first(where: { $0.designator == last }) else { return nil }
        self.init(value: n, unit: unit)
    }

    public var iso8601: String { "P\(value)\(unit.designator)" }
    public var description: String { iso8601 }

    public func times(_ count: Int) -> SubscriptionDuration { SubscriptionDuration(value: value * count, unit: unit) }

    public static let editorSubscriptionPeriods: Set<String> = ["P3D", "P1W", "P1M", "P2M", "P3M", "P6M", "P1Y"]

    public static let documentedOfferPeriods: Set<String> = [
        "P3D", "P1W", "P2W", "P1M", "P2M", "P3M", "P6M", "P1Y",
    ]
}
