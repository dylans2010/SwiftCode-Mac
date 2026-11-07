import Foundation
import CoreLocation

public final class WeatherService: Sendable {
    public static let shared = WeatherService()

    let engine: WeatherEngine

    public convenience init() {
        self.init(backend: WeatherService.environmentBackend())
    }

    public init(backend: any WeatherBackend, configuration: Configuration = Configuration()) {
        self.engine = WeatherEngine(backend: backend, configuration: configuration)
    }

    public var attribution: WeatherAttribution {
        get async throws { try await engine.attribution() }
    }

    public func weather(for location: CLLocation) async throws -> Weather {
        let current = WeatherQuery.current
        let minute = WeatherQuery.minute
        let hourly = WeatherQuery.hourly
        let daily = WeatherQuery.daily
        let alerts = WeatherQuery.alerts
        let availability = WeatherQuery.availability
        let changes = WeatherQuery.changes
        let values = try await fetch(
            location,
            [current.request, daily.request, hourly.request, minute.request, alerts.request,
             changes.request, availability.request])
        return Weather(
            currentWeather: try value(current, values), minuteForecast: try value(minute, values),
            hourlyForecast: try value(hourly, values), dailyForecast: try value(daily, values),
            weatherAlerts: try value(alerts, values), availability: try value(availability, values),
            weatherChanges: try value(changes, values))
    }

    public func weather<T>(for location: CLLocation, including dataSet: WeatherQuery<T>) async throws -> T {
        let values = try await fetch(location, [dataSet.request])
        return try value(dataSet, values)
    }

    public func weather<T1, T2>(
        for location: CLLocation, including dataSet1: WeatherQuery<T1>, _ dataSet2: WeatherQuery<T2>
    ) async throws -> (T1, T2) {
        let values = try await fetch(location, [dataSet1.request, dataSet2.request])
        return (try value(dataSet1, values), try value(dataSet2, values))
    }

    public func weather<T1, T2, T3>(
        for location: CLLocation, including dataSet1: WeatherQuery<T1>, _ dataSet2: WeatherQuery<T2>,
        _ dataSet3: WeatherQuery<T3>
    ) async throws -> (T1, T2, T3) {
        let values = try await fetch(location, [dataSet1.request, dataSet2.request, dataSet3.request])
        return (try value(dataSet1, values), try value(dataSet2, values), try value(dataSet3, values))
    }

    public func weather<T1, T2, T3, T4>(
        for location: CLLocation, including dataSet1: WeatherQuery<T1>, _ dataSet2: WeatherQuery<T2>,
        _ dataSet3: WeatherQuery<T3>, _ dataSet4: WeatherQuery<T4>
    ) async throws -> (T1, T2, T3, T4) {
        let values = try await fetch(
            location, [dataSet1.request, dataSet2.request, dataSet3.request, dataSet4.request])
        return (
            try value(dataSet1, values), try value(dataSet2, values), try value(dataSet3, values),
            try value(dataSet4, values)
        )
    }

    public func weather<T1, T2, T3, T4, T5>(
        for location: CLLocation, including dataSet1: WeatherQuery<T1>, _ dataSet2: WeatherQuery<T2>,
        _ dataSet3: WeatherQuery<T3>, _ dataSet4: WeatherQuery<T4>, _ dataSet5: WeatherQuery<T5>
    ) async throws -> (T1, T2, T3, T4, T5) {
        let values = try await fetch(
            location,
            [dataSet1.request, dataSet2.request, dataSet3.request, dataSet4.request, dataSet5.request])
        return (
            try value(dataSet1, values), try value(dataSet2, values), try value(dataSet3, values),
            try value(dataSet4, values), try value(dataSet5, values)
        )
    }

    public func weather<T1, T2, T3, T4, T5, T6>(
        for location: CLLocation, including dataSet1: WeatherQuery<T1>, _ dataSet2: WeatherQuery<T2>,
        _ dataSet3: WeatherQuery<T3>, _ dataSet4: WeatherQuery<T4>, _ dataSet5: WeatherQuery<T5>,
        _ dataSet6: WeatherQuery<T6>
    ) async throws -> (T1, T2, T3, T4, T5, T6) {
        let values = try await fetch(
            location,
            [dataSet1.request, dataSet2.request, dataSet3.request, dataSet4.request, dataSet5.request,
             dataSet6.request])
        return (
            try value(dataSet1, values), try value(dataSet2, values), try value(dataSet3, values),
            try value(dataSet4, values), try value(dataSet5, values), try value(dataSet6, values)
        )
    }

    public func weather<each T>(
        for location: CLLocation, including dataSet: repeat WeatherQuery<each T>
    ) async throws -> (repeat each T) {
        var requests: [WeatherProductRequest] = []
        for query in repeat each dataSet {
            requests.append(query.request)
        }
        let values = try await fetch(location, requests)
        return (repeat try value(each dataSet, values))
    }

    public func dailyStatistics<each T: Codable & Equatable & Sendable>(
        for location: CLLocation, including query: repeat DailyWeatherStatisticsQuery<each T>
    ) async throws -> (repeat DailyWeatherStatistics<each T>) {
        try await dailyStatistics(location, range: nil, repeat each query)
    }

    public func dailyStatistics<each T: Codable & Equatable & Sendable>(
        for location: CLLocation, forDaysIn interval: DateInterval,
        including query: repeat DailyWeatherStatisticsQuery<each T>
    ) async throws -> (repeat DailyWeatherStatistics<each T>) {
        try await dailyStatistics(location, range: .dates(start: interval.start, end: interval.end), repeat each query)
    }

    public func dailyStatistics<each T: Codable & Equatable & Sendable>(
        for location: CLLocation, startDay: Int, endDay: Int,
        including query: repeat DailyWeatherStatisticsQuery<each T>
    ) async throws -> (repeat DailyWeatherStatistics<each T>) {
        try await dailyStatistics(location, range: .indices(start: startDay, end: endDay), repeat each query)
    }

    private func dailyStatistics<each T: Codable & Equatable & Sendable>(
        _ location: CLLocation, range: WeatherProductRange?, _ query: repeat DailyWeatherStatisticsQuery<each T>
    ) async throws -> (repeat DailyWeatherStatistics<each T>) {
        var requests: [WeatherProductRequest] = []
        for query in repeat each query {
            requests.append(WeatherProductRequest(product: query.product, range: range))
        }
        let values = try await fetch(location, requests)
        return (repeat try extracted(values[WeatherProductRequest(product: (each query).product, range: range)], (each query).extract))
    }

    public func hourlyStatistics<each T: Codable & Equatable & Sendable>(
        for location: CLLocation, including query: repeat HourlyWeatherStatisticsQuery<each T>
    ) async throws -> (repeat HourlyWeatherStatistics<each T>) {
        try await hourlyStatistics(location, range: nil, repeat each query)
    }

    public func hourlyStatistics<each T: Codable & Equatable & Sendable>(
        for location: CLLocation, forHoursIn interval: DateInterval,
        including query: repeat HourlyWeatherStatisticsQuery<each T>
    ) async throws -> (repeat HourlyWeatherStatistics<each T>) {
        try await hourlyStatistics(location, range: .dates(start: interval.start, end: interval.end), repeat each query)
    }

    public func hourlyStatistics<each T: Codable & Equatable & Sendable>(
        for location: CLLocation, startHour: Int, endHour: Int,
        including query: repeat HourlyWeatherStatisticsQuery<each T>
    ) async throws -> (repeat HourlyWeatherStatistics<each T>) {
        try await hourlyStatistics(location, range: .indices(start: startHour, end: endHour), repeat each query)
    }

    private func hourlyStatistics<each T: Codable & Equatable & Sendable>(
        _ location: CLLocation, range: WeatherProductRange?, _ query: repeat HourlyWeatherStatisticsQuery<each T>
    ) async throws -> (repeat HourlyWeatherStatistics<each T>) {
        var requests: [WeatherProductRequest] = []
        for query in repeat each query {
            requests.append(WeatherProductRequest(product: query.product, range: range))
        }
        let values = try await fetch(location, requests)
        return (repeat try extracted(values[WeatherProductRequest(product: (each query).product, range: range)], (each query).extract))
    }

    public func monthlyStatistics<each T: Codable & Equatable & Sendable>(
        for location: CLLocation, including query: repeat MonthlyWeatherStatisticsQuery<each T>
    ) async throws -> (repeat MonthlyWeatherStatistics<each T>) {
        try await monthlyStatistics(location, range: nil, repeat each query)
    }

    public func monthlyStatistics<each T: Codable & Equatable & Sendable>(
        for location: CLLocation, forMonthsIn interval: DateInterval,
        including query: repeat MonthlyWeatherStatisticsQuery<each T>
    ) async throws -> (repeat MonthlyWeatherStatistics<each T>) {
        try await monthlyStatistics(location, range: .dates(start: interval.start, end: interval.end), repeat each query)
    }

    public func monthlyStatistics<each T: Codable & Equatable & Sendable>(
        for location: CLLocation, startMonth: Int, endMonth: Int,
        including query: repeat MonthlyWeatherStatisticsQuery<each T>
    ) async throws -> (repeat MonthlyWeatherStatistics<each T>) {
        try await monthlyStatistics(location, range: .indices(start: startMonth, end: endMonth), repeat each query)
    }

    private func monthlyStatistics<each T: Codable & Equatable & Sendable>(
        _ location: CLLocation, range: WeatherProductRange?, _ query: repeat MonthlyWeatherStatisticsQuery<each T>
    ) async throws -> (repeat MonthlyWeatherStatistics<each T>) {
        var requests: [WeatherProductRequest] = []
        for query in repeat each query {
            requests.append(WeatherProductRequest(product: query.product, range: range))
        }
        let values = try await fetch(location, requests)
        return (repeat try extracted(values[WeatherProductRequest(product: (each query).product, range: range)], (each query).extract))
    }

    public func dailySummary<each T: Codable & Equatable & Sendable>(
        for location: CLLocation, including query: repeat DailyWeatherSummaryQuery<each T>
    ) async throws -> (repeat DailyWeatherSummary<each T>) {
        try await dailySummary(location, range: nil, repeat each query)
    }

    public func dailySummary<each T: Codable & Equatable & Sendable>(
        for location: CLLocation, forDaysIn interval: DateInterval,
        including query: repeat DailyWeatherSummaryQuery<each T>
    ) async throws -> (repeat DailyWeatherSummary<each T>) {
        try await dailySummary(location, range: .dates(start: interval.start, end: interval.end), repeat each query)
    }

    private func dailySummary<each T: Codable & Equatable & Sendable>(
        _ location: CLLocation, range: WeatherProductRange?, _ query: repeat DailyWeatherSummaryQuery<each T>
    ) async throws -> (repeat DailyWeatherSummary<each T>) {
        var requests: [WeatherProductRequest] = []
        for query in repeat each query {
            requests.append(WeatherProductRequest(product: query.product, range: range))
        }
        let values = try await fetch(location, requests)
        return (repeat try extracted(values[WeatherProductRequest(product: (each query).product, range: range)], (each query).extract))
    }

    private func fetch(_ location: CLLocation, _ requests: [WeatherProductRequest]) async throws
        -> [WeatherProductRequest: WeatherProductValue]
    {
        try await engine.fetch(
            latitude: location.coordinate.latitude, longitude: location.coordinate.longitude, requests: requests)
    }

    private func value<T>(_ query: WeatherQuery<T>, _ values: [WeatherProductRequest: WeatherProductValue]) throws -> T {
        try extracted(values[query.request], query.extract)
    }

    private func extracted<T>(_ value: WeatherProductValue?, _ extract: (WeatherProductValue) -> T?) throws -> T {
        guard let value, let result = extract(value) else { throw WeatherError.unknown }
        return result
    }

    public func removeCachedData() async {
        await engine.removeAll()
    }
}

extension WeatherService {
    public struct Configuration: Sendable {
        public var language: String?
        public var cacheDirectory: URL?
        public var clock: @Sendable () -> Date

        public init(language: String? = nil, cacheDirectory: URL? = nil, clock: @escaping @Sendable () -> Date = { Date() }) {
            self.language = language
            self.cacheDirectory = cacheDirectory
            self.clock = clock
        }

        static func normalizedLanguage(_ raw: String) -> String {
            var tag = raw
            if let dot = tag.firstIndex(of: ".") { tag = String(tag[..<dot]) }
            if let at = tag.firstIndex(of: "@") { tag = String(tag[..<at]) }
            tag = tag.replacingOccurrences(of: "_", with: "-")
            if tag.isEmpty || tag == "C" || tag == "POSIX" { return "en-US" }
            return tag
        }

        static func preferredLanguage() -> String {
            normalizedLanguage(Locale.preferredLanguages.first ?? "en-US")
        }
    }

    static func environmentBackend(
        _ environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> any WeatherBackend {
        switch environment["WEATHERKIT_BACKEND"] {
        case "fixtures":
            do {
                if let path = environment["WEATHERKIT_FIXTURES"], !path.isEmpty {
                    return try FixtureWeatherBackend(directory: URL(fileURLWithPath: path))
                }
                return try FixtureWeatherBackend.bundled()
            } catch {
                return FailingWeatherBackend(error: WeatherBackendError.malformedResponse("fixtures: \(error)"))
            }
        case "apple-rest":
            return AppleRESTWeatherBackend.fromEnvironment(environment) ?? UnconfiguredWeatherBackend()
        default:
            return UnconfiguredWeatherBackend()
        }
    }
}

struct FailingWeatherBackend: WeatherBackend {
    let error: WeatherBackendError

    var identifier: String { "failing" }

    func weather(for request: WeatherBackendRequest) async throws -> [WeatherProductRequest: WeatherProductResult] {
        throw error
    }

    func attribution(language: String) async throws -> WeatherAttribution {
        throw error
    }
}
