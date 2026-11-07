import Foundation
#if canImport(CoreLocation)
import CoreLocation
#endif

public struct WeatherAttribution: Codable, Equatable, Sendable {
    struct Storage: Codable, Equatable, Sendable {
        var serviceName: String
        var legalPageURL: URL
        var squareMarkURL: URL
        var combinedMarkLightURL: URL
        var combinedMarkDarkURL: URL
        var logoURL: URL?
        var sourceURL: URL?
    }

    var storage: Storage
    var legalText: String?

    enum CodingKeys: String, CodingKey {
        case storage
    }

    package init(
        serviceName: String, legalPageURL: URL, squareMarkURL: URL, combinedMarkLightURL: URL,
        combinedMarkDarkURL: URL, legalAttributionText: String? = nil, logoURL: URL? = nil, sourceURL: URL? = nil
    ) {
        self.storage = Storage(
            serviceName: serviceName, legalPageURL: legalPageURL, squareMarkURL: squareMarkURL,
            combinedMarkLightURL: combinedMarkLightURL, combinedMarkDarkURL: combinedMarkDarkURL,
            logoURL: logoURL, sourceURL: sourceURL)
        self.legalText = legalAttributionText
    }

    public var serviceName: String { storage.serviceName }
    public var legalPageURL: URL { storage.legalPageURL }
    public var squareMarkURL: URL { storage.squareMarkURL }
    public var combinedMarkLightURL: URL { storage.combinedMarkLightURL }
    public var combinedMarkDarkURL: URL { storage.combinedMarkDarkURL }

    public var legalAttributionText: String {
        if let legalText, !legalText.isEmpty { return legalText }
        return "\(storage.serviceName)\n\(storage.legalPageURL.absoluteString)"
    }

    public static func == (lhs: WeatherAttribution, rhs: WeatherAttribution) -> Bool {
        lhs.storage == rhs.storage
    }
}

public struct WeatherMetadata: Codable, Equatable, Sendable {
    public internal(set) var date: Date
    public internal(set) var expirationDate: Date
    var latitude: Double
    var longitude: Double
    var attribution: WeatherAttribution?

    package init(date: Date, expirationDate: Date, latitude: Double, longitude: Double, attribution: WeatherAttribution? = nil) {
        self.date = date
        self.expirationDate = expirationDate
        self.latitude = latitude
        self.longitude = longitude
        self.attribution = attribution
    }

    public var location: CLLocation {
        CLLocation(latitude: latitude, longitude: longitude)
    }
}
