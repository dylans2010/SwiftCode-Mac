import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct AppleRESTWeatherBackend: WeatherBackend {
    public struct LocationContext: Sendable, Equatable {
        public var timeZone: String
        public var countryCode: String?

        public init(timeZone: String, countryCode: String? = nil) {
            self.timeZone = timeZone
            self.countryCode = countryCode
        }
    }

    public static let defaultBaseURL = URL(string: "https://weatherkit.apple.com")!

    let baseURL: URL
    let tokenProvider: any WeatherTokenProvider
    let httpClient: any WeatherHTTPClient
    let locationContext: @Sendable (Double, Double) async -> LocationContext

    public init(
        tokenProvider: any WeatherTokenProvider, baseURL: URL = AppleRESTWeatherBackend.defaultBaseURL,
        httpClient: any WeatherHTTPClient = URLSessionWeatherHTTPClient(),
        locationContext: @escaping @Sendable (Double, Double) async -> LocationContext = { _, _ in
            LocationContext(timeZone: TimeZone.current.identifier)
        }
    ) {
        self.baseURL = baseURL
        self.tokenProvider = tokenProvider
        self.httpClient = httpClient
        self.locationContext = locationContext
    }

    public var identifier: String { "apple-rest:\(baseURL.host ?? baseURL.absoluteString)" }

    public func attribution(language: String) async throws -> WeatherAttribution {
        let url = baseURL.appendingPathComponent("attribution").appendingPathComponent(language)
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        let data = try await send(request)
        let object: REST.Attribution
        do {
            object = try REST.decoder().decode(REST.Attribution.self, from: data)
        } catch {
            throw WeatherBackendError.malformedResponse("attribution: \(error)")
        }
        func resolve(_ text: String?) -> URL? {
            guard let text else { return nil }
            return URL(string: text, relativeTo: baseURL)?.absoluteURL
        }
        guard let light = resolve(object.logoLight3x ?? object.logoLight2x ?? object.logoLight1x),
              let dark = resolve(object.logoDark3x ?? object.logoDark2x ?? object.logoDark1x),
              let square = resolve(object.logoSquare3x ?? object.logoSquare2x ?? object.logoSquare1x)
        else { throw WeatherBackendError.malformedResponse("attribution: missing logos") }
        return WeatherAttribution(
            serviceName: object.serviceName ?? "Apple Weather",
            legalPageURL: baseURL.appendingPathComponent("legal-attribution.html"),
            squareMarkURL: square, combinedMarkLightURL: light, combinedMarkDarkURL: dark)
    }

    static func dataSets(for product: WeatherProduct) -> [String] {
        switch product {
        case .currentWeather: return ["currentWeather"]
        case .forecastNextHour: return ["forecastNextHour"]
        case .forecastHourly: return ["forecastHourly"]
        case .forecastDaily: return ["forecastDaily"]
        case .weatherAlerts: return ["weatherAlerts"]
        case .availability: return ["forecastNextHour", "weatherAlerts"]
        default: return []
        }
    }

    public func weather(for request: WeatherBackendRequest) async throws -> [WeatherProductRequest: WeatherProductResult] {
        var results: [WeatherProductRequest: WeatherProductResult] = [:]
        var remaining: [WeatherProductRequest] = []
        for product in request.products {
            switch product.product {
            case .weatherChanges:
                results[product] = WeatherProductResult(
                    value: .weatherChanges(nil), expirationDate: request.requestDate.addingTimeInterval(3600))
            case .historicalComparisons:
                results[product] = WeatherProductResult(
                    value: .historicalComparisons(nil), expirationDate: request.requestDate.addingTimeInterval(3600))
            case .currentWeather, .forecastNextHour, .forecastHourly, .forecastDaily, .weatherAlerts, .availability:
                remaining.append(product)
            default:
                throw WeatherBackendError.unsupported("\(product.product.rawValue) is not in the REST API v1")
            }
        }
        guard !remaining.isEmpty else { return results }
        let context = await locationContext(request.latitude, request.longitude)

        while !remaining.isEmpty {
            var batch: [WeatherProductRequest] = []
            var leftover: [WeatherProductRequest] = []
            var hourlyRange: WeatherProductRange??
            var dailyRange: WeatherProductRange??
            for product in remaining {
                switch product.product {
                case .forecastHourly:
                    if hourlyRange == nil || hourlyRange! == product.range {
                        hourlyRange = .some(product.range)
                        batch.append(product)
                    } else {
                        leftover.append(product)
                    }
                case .forecastDaily:
                    if dailyRange == nil || dailyRange! == product.range {
                        dailyRange = .some(product.range)
                        batch.append(product)
                    } else {
                        leftover.append(product)
                    }
                default:
                    batch.append(product)
                }
            }
            let response = try await fetchWeather(
                request: request, products: batch, context: context, hourlyRange: hourlyRange ?? nil,
                dailyRange: dailyRange ?? nil)
            let mapper = RESTMapper(requestDate: request.requestDate, language: request.language, baseURL: baseURL)
            for product in batch {
                results[product] = try mapper.result(for: product.product, in: response)
            }
            remaining = leftover.filter { results[$0] == nil }
        }
        return results
    }

    func weatherRequest(
        request: WeatherBackendRequest, products: [WeatherProductRequest], context: LocationContext,
        hourlyRange: WeatherProductRange?, dailyRange: WeatherProductRange?
    ) -> URLRequest {
        var dataSets: [String] = []
        for product in products {
            for set in Self.dataSets(for: product.product) where !dataSets.contains(set) {
                dataSets.append(set)
            }
        }
        let url = baseURL.appendingPathComponent("api/v1/weather")
            .appendingPathComponent(request.language)
            .appendingPathComponent(Self.coordinate(request.latitude))
            .appendingPathComponent(Self.coordinate(request.longitude))
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        var items = [
            URLQueryItem(name: "dataSets", value: dataSets.joined(separator: ",")),
            URLQueryItem(name: "timezone", value: context.timeZone),
        ]
        if let country = context.countryCode {
            items.append(URLQueryItem(name: "countryCode", value: country))
        }
        if case .dates(let start, let end)? = dailyRange {
            items.append(URLQueryItem(name: "dailyStart", value: Self.timestamp(start)))
            items.append(URLQueryItem(name: "dailyEnd", value: Self.timestamp(end)))
        }
        if case .dates(let start, let end)? = hourlyRange {
            items.append(URLQueryItem(name: "hourlyStart", value: Self.timestamp(start)))
            items.append(URLQueryItem(name: "hourlyEnd", value: Self.timestamp(end)))
        }
        components.queryItems = items
        var urlRequest = URLRequest(url: components.url!)
        urlRequest.httpMethod = "GET"
        return urlRequest
    }

    private func fetchWeather(
        request: WeatherBackendRequest, products: [WeatherProductRequest], context: LocationContext,
        hourlyRange: WeatherProductRange?, dailyRange: WeatherProductRange?
    ) async throws -> REST.Weather {
        var urlRequest = weatherRequest(
            request: request, products: products, context: context, hourlyRange: hourlyRange, dailyRange: dailyRange)
        urlRequest.setValue("Bearer \(try await tokenProvider.token())", forHTTPHeaderField: "Authorization")
        let data = try await send(urlRequest)
        do {
            return try REST.decoder().decode(REST.Weather.self, from: data)
        } catch {
            throw WeatherBackendError.malformedResponse("weather: \(error)")
        }
    }

    private func send(_ request: URLRequest) async throws -> Data {
        try Task.checkCancellation()
        let (data, response) = try await httpClient.data(for: request)
        guard (200..<300).contains(response.statusCode) else {
            throw WeatherBackendError.httpStatus(response.statusCode)
        }
        return data
    }

    static func coordinate(_ value: Double) -> String {
        let text = "\(value)"
        return text.hasSuffix(".0") ? String(text.dropLast(2)) : text
    }

    static func timestamp(_ date: Date) -> String {
        date.formatted(Date.ISO8601FormatStyle(timeZone: TimeZone(identifier: "UTC")!))
    }
}

extension AppleRESTWeatherBackend {
    static func fromEnvironment(_ environment: [String: String]) -> AppleRESTWeatherBackend? {
        func value(_ name: String) -> String? {
            guard let text = environment[name], !text.isEmpty else { return nil }
            return text
        }
        let provider: any WeatherTokenProvider
        if let token = value("WEATHERKIT_TOKEN") {
            provider = StaticWeatherTokenProvider(token: token)
        } else if let text = value("WEATHERKIT_TOKEN_URL"), let url = URL(string: text) {
            provider = RemoteWeatherTokenProvider(url: url)
        } else if let team = value("WEATHERKIT_TEAM_ID"), let service = value("WEATHERKIT_SERVICE_ID"),
                  let key = value("WEATHERKIT_KEY_ID"), let file = value("WEATHERKIT_KEY_FILE"),
                  let signing = try? SigningWeatherTokenProvider(
                      teamID: team, serviceID: service, keyID: key, privateKeyFile: URL(fileURLWithPath: file)) {
            provider = signing
        } else {
            return nil
        }
        return AppleRESTWeatherBackend(tokenProvider: provider)
    }
}
