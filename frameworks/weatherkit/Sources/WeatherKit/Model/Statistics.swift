import Foundation

public struct DailyWeatherStatistics<T: Codable & Equatable & Sendable>: Codable, Equatable, Sendable, RandomAccessCollection {
    public internal(set) var days: [T]
    public internal(set) var baselineStartDate: Date
    public internal(set) var metadata: WeatherMetadata

    public var startIndex: Int { days.startIndex }
    public var endIndex: Int { days.endIndex }
    public subscript(position: Int) -> T { days[position] }
}

public struct HourlyWeatherStatistics<T: Codable & Equatable & Sendable>: Codable, Equatable, Sendable, RandomAccessCollection {
    public internal(set) var hours: [T]
    public internal(set) var baselineStartDate: Date
    public internal(set) var metadata: WeatherMetadata

    public var startIndex: Int { hours.startIndex }
    public var endIndex: Int { hours.endIndex }
    public subscript(position: Int) -> T { hours[position] }
}

public struct MonthlyWeatherStatistics<T: Codable & Equatable & Sendable>: Codable, Equatable, Sendable, RandomAccessCollection {
    public internal(set) var months: [T]
    public internal(set) var baselineStartDate: Date
    public internal(set) var metadata: WeatherMetadata

    public var startIndex: Int { months.startIndex }
    public var endIndex: Int { months.endIndex }
    public subscript(position: Int) -> T { months[position] }
}

public struct DailyWeatherSummary<T: Codable & Equatable & Sendable>: Codable, Equatable, Sendable, RandomAccessCollection {
    public internal(set) var days: [T]
    public internal(set) var metadata: WeatherMetadata

    public var startIndex: Int { days.startIndex }
    public var endIndex: Int { days.endIndex }
    public subscript(position: Int) -> T { days[position] }
}

public struct DayTemperatureStatistics: Codable, Equatable, Sendable {
    public internal(set) var day: Int
    public internal(set) var averageLowTemperature: Measurement<UnitTemperature>
    public internal(set) var averageHighTemperature: Measurement<UnitTemperature>
}

public struct DayPrecipitationStatistics: Codable, Equatable, Sendable {
    public internal(set) var day: Int
    public internal(set) var averagePrecipitationProbability: Double
    public internal(set) var averagePrecipitationAmount: Measurement<UnitLength>
    public internal(set) var averageSnowfallAmount: Measurement<UnitLength>
}

public struct HourTemperatureStatistics: Codable, Equatable, Sendable {
    public internal(set) var hour: Int
    public internal(set) var percentiles: Percentiles<UnitTemperature>
}

public struct Percentiles<Dimension: Unit>: Codable, Equatable, Sendable {
    public internal(set) var p10: Measurement<Dimension>
    public internal(set) var p50: Measurement<Dimension>
    public internal(set) var p90: Measurement<Dimension>
}

public struct MonthTemperatureStatistics: Codable, Equatable, Sendable {
    public internal(set) var month: Int
    public internal(set) var averageLowTemperature: Measurement<UnitTemperature>
    public internal(set) var averageHighTemperature: Measurement<UnitTemperature>
}

public struct MonthPrecipitationStatistics: Codable, Equatable, Sendable {
    public internal(set) var month: Int
    public internal(set) var averagePrecipitationProbability: Double
    public internal(set) var averagePrecipitationAmount: Measurement<UnitLength>
    public internal(set) var averageSnowfallAmount: Measurement<UnitLength>
}

public struct DayTemperatureSummary: Codable, Equatable, Sendable {
    public internal(set) var date: Date
    public internal(set) var lowTemperature: Measurement<UnitTemperature>
    public internal(set) var highTemperature: Measurement<UnitTemperature>
}

public struct DayPrecipitationSummary: Codable, Equatable, Sendable {
    public internal(set) var date: Date
    public internal(set) var precipitationAmount: Measurement<UnitLength>
    public internal(set) var snowfallAmount: Measurement<UnitLength>
}
