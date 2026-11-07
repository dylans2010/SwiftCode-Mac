import Foundation

public enum WeatherProduct: String, Codable, Hashable, Sendable, CaseIterable {
    case currentWeather
    case forecastNextHour
    case forecastHourly
    case forecastDaily
    case weatherAlerts
    case availability
    case weatherChanges
    case historicalComparisons
    case dailyTemperatureStatistics
    case dailyPrecipitationStatistics
    case hourlyTemperatureStatistics
    case monthlyTemperatureStatistics
    case monthlyPrecipitationStatistics
    case dailyTemperatureSummary
    case dailyPrecipitationSummary
}

public enum WeatherProductRange: Codable, Hashable, Sendable {
    case dates(start: Date, end: Date)
    case indices(start: Int, end: Int)
}

public struct WeatherProductRequest: Codable, Hashable, Sendable, CustomStringConvertible {
    public let product: WeatherProduct
    public let range: WeatherProductRange?

    public init(product: WeatherProduct, range: WeatherProductRange? = nil) {
        self.product = product
        self.range = range
    }

    public var description: String {
        switch range {
        case nil: return product.rawValue
        case .dates(let start, let end)?:
            return "\(product.rawValue)[\(start.timeIntervalSinceReferenceDate),\(end.timeIntervalSinceReferenceDate))"
        case .indices(let start, let end)?:
            return "\(product.rawValue)[#\(start),#\(end))"
        }
    }
}

public struct WeatherBackendRequest: Sendable, Equatable {
    public let latitude: Double
    public let longitude: Double
    public let language: String
    public let products: [WeatherProductRequest]
    public let requestDate: Date

    public init(latitude: Double, longitude: Double, language: String, products: [WeatherProductRequest], requestDate: Date) {
        self.latitude = latitude
        self.longitude = longitude
        self.language = language
        self.products = products
        self.requestDate = requestDate
    }
}

public enum WeatherProductValue: Codable, Equatable, Sendable {
    case currentWeather(CurrentWeather)
    case forecastNextHour(Forecast<MinuteWeather>?)
    case forecastHourly(Forecast<HourWeather>)
    case forecastDaily(Forecast<DayWeather>)
    case weatherAlerts([WeatherAlert]?)
    case availability(WeatherAvailability)
    case weatherChanges(WeatherChanges?)
    case historicalComparisons(HistoricalComparisons?)
    case dailyTemperatureStatistics(DailyWeatherStatistics<DayTemperatureStatistics>)
    case dailyPrecipitationStatistics(DailyWeatherStatistics<DayPrecipitationStatistics>)
    case hourlyTemperatureStatistics(HourlyWeatherStatistics<HourTemperatureStatistics>)
    case monthlyTemperatureStatistics(MonthlyWeatherStatistics<MonthTemperatureStatistics>)
    case monthlyPrecipitationStatistics(MonthlyWeatherStatistics<MonthPrecipitationStatistics>)
    case dailyTemperatureSummary(DailyWeatherSummary<DayTemperatureSummary>)
    case dailyPrecipitationSummary(DailyWeatherSummary<DayPrecipitationSummary>)

    public var product: WeatherProduct {
        switch self {
        case .currentWeather: return .currentWeather
        case .forecastNextHour: return .forecastNextHour
        case .forecastHourly: return .forecastHourly
        case .forecastDaily: return .forecastDaily
        case .weatherAlerts: return .weatherAlerts
        case .availability: return .availability
        case .weatherChanges: return .weatherChanges
        case .historicalComparisons: return .historicalComparisons
        case .dailyTemperatureStatistics: return .dailyTemperatureStatistics
        case .dailyPrecipitationStatistics: return .dailyPrecipitationStatistics
        case .hourlyTemperatureStatistics: return .hourlyTemperatureStatistics
        case .monthlyTemperatureStatistics: return .monthlyTemperatureStatistics
        case .monthlyPrecipitationStatistics: return .monthlyPrecipitationStatistics
        case .dailyTemperatureSummary: return .dailyTemperatureSummary
        case .dailyPrecipitationSummary: return .dailyPrecipitationSummary
        }
    }
}

public struct WeatherProductResult: Codable, Equatable, Sendable {
    public let value: WeatherProductValue
    public let expirationDate: Date

    public init(value: WeatherProductValue, expirationDate: Date) {
        self.value = value
        self.expirationDate = expirationDate
    }
}

public protocol WeatherBackend: Sendable {
    var identifier: String { get }

    func weather(for request: WeatherBackendRequest) async throws -> [WeatherProductRequest: WeatherProductResult]

    func attribution(language: String) async throws -> WeatherAttribution
}

public enum WeatherBackendError: Error, Sendable, Equatable {
    case notAuthorized
    case httpStatus(Int)
    case malformedResponse(String)
    case unsupported(String)
}

public struct UnconfiguredWeatherBackend: WeatherBackend {
    public init() {}

    public var identifier: String { "unconfigured" }

    public func weather(for request: WeatherBackendRequest) async throws -> [WeatherProductRequest: WeatherProductResult] {
        throw WeatherBackendError.notAuthorized
    }

    public func attribution(language: String) async throws -> WeatherAttribution {
        throw WeatherBackendError.notAuthorized
    }
}
