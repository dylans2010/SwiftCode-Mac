import Foundation
import CoreLocation
@testable import WeatherKit

let fixtureAnchor = Date(timeIntervalSince1970: 1_768_478_400)

let fixtureLocation = CLLocation(latitude: 41.50049, longitude: -81.49951)

final class TestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var current: Date

    init(_ start: Date = fixtureAnchor) { current = start }

    var now: Date {
        get { lock.withLock { current } }
        set { lock.withLock { current = newValue } }
    }

    func advance(_ seconds: TimeInterval) { now = now.addingTimeInterval(seconds) }
}

final class RecordingBackend: WeatherBackend, @unchecked Sendable {
    let base: any WeatherBackend
    private let lock = NSLock()
    private var recorded: [WeatherBackendRequest] = []
    private var _delay: Duration?
    private var _failure: (any Error)?
    private var _rewrite: (@Sendable ([WeatherProductRequest: WeatherProductResult]) -> [WeatherProductRequest: WeatherProductResult])?
    private var _attributionCalls = 0
    private var _cancelledCalls = 0

    init(_ base: any WeatherBackend) { self.base = base }

    var identifier: String { base.identifier }
    var requests: [WeatherBackendRequest] { lock.withLock { recorded } }
    var attributionCalls: Int { lock.withLock { _attributionCalls } }
    var cancelledCalls: Int { lock.withLock { _cancelledCalls } }

    var delay: Duration? {
        get { lock.withLock { _delay } }
        set { lock.withLock { _delay = newValue } }
    }

    var failure: (any Error)? {
        get { lock.withLock { _failure } }
        set { lock.withLock { _failure = newValue } }
    }

    var rewrite: (@Sendable ([WeatherProductRequest: WeatherProductResult]) -> [WeatherProductRequest: WeatherProductResult])? {
        get { lock.withLock { _rewrite } }
        set { lock.withLock { _rewrite = newValue } }
    }

    func weather(for request: WeatherBackendRequest) async throws -> [WeatherProductRequest: WeatherProductResult] {
        lock.withLock { recorded.append(request) }
        if let delay {
            do {
                try await Task.sleep(for: delay)
            } catch {
                lock.withLock { _cancelledCalls += 1 }
                throw error
            }
        }
        if let failure { throw failure }
        let response = try await base.weather(for: request)
        return rewrite?(response) ?? response
    }

    func attribution(language: String) async throws -> WeatherAttribution {
        lock.withLock { _attributionCalls += 1 }
        if let failure { throw failure }
        return try await base.attribution(language: language)
    }
}

func makeService(clock: TestClock = TestClock(), language: String = "en-US", cacheDirectory: URL? = nil)
    throws -> (WeatherService, RecordingBackend)
{
    let backend = RecordingBackend(try FixtureWeatherBackend.bundled())
    let service = WeatherService(
        backend: backend,
        configuration: .init(language: language, cacheDirectory: cacheDirectory, clock: { clock.now }))
    return (service, backend)
}

func products(_ backend: RecordingBackend) -> [WeatherProductRequest] {
    backend.requests.last?.products ?? []
}

func fixtureWeather() throws -> Weather {
    let backend = try FixtureWeatherBackend.bundled(rebase: WeatherKit.FixtureWeatherBackend.Rebase.none)
    return try backend.decode(Weather.self, file: "weather.json", offset: 0)
}

func fixtureFile<T: Decodable>(_ type: T.Type, _ file: String) throws -> T {
    let backend = try FixtureWeatherBackend.bundled(rebase: WeatherKit.FixtureWeatherBackend.Rebase.none)
    return try backend.decode(type, file: file, offset: 0)
}

func encode<T: Encodable>(_ value: T) throws -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    return try encoder.encode(value)
}

func decode<T: Decodable>(_ type: T.Type, _ data: Data) throws -> T {
    try JSONDecoder().decode(type, from: data)
}

func jsonObject<T: Encodable>(_ value: T) throws -> [String: Any] {
    try JSONSerialization.jsonObject(with: try encode(value)) as! [String: Any]
}

func data(_ object: Any) throws -> Data {
    try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
}

struct TestFailure: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}
