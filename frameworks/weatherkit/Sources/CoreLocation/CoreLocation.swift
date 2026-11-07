#if !canImport(Darwin)
import Foundation

public typealias CLLocationDegrees = Double
public typealias CLLocationDistance = Double
public typealias CLLocationAccuracy = Double
public typealias CLLocationSpeed = Double
public typealias CLLocationSpeedAccuracy = Double
public typealias CLLocationDirection = Double
public typealias CLLocationDirectionAccuracy = Double

public struct CLLocationCoordinate2D: Sendable {
    public var latitude: CLLocationDegrees
    public var longitude: CLLocationDegrees

    public init() {
        self.latitude = 0
        self.longitude = 0
    }

    public init(latitude: CLLocationDegrees, longitude: CLLocationDegrees) {
        self.latitude = latitude
        self.longitude = longitude
    }
}

public func CLLocationCoordinate2DMake(_ latitude: CLLocationDegrees, _ longitude: CLLocationDegrees) -> CLLocationCoordinate2D {
    CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
}

public func CLLocationCoordinate2DIsValid(_ coordinate: CLLocationCoordinate2D) -> Bool {
    (-90.0...90.0).contains(coordinate.latitude) && (-180.0...180.0).contains(coordinate.longitude)
}

public let kCLLocationCoordinate2DInvalid = CLLocationCoordinate2D(latitude: -180, longitude: -180)

public let kCLDistanceFilterNone: CLLocationDistance = -1

public let kCLLocationAccuracyBest: CLLocationAccuracy = -1

open class CLFloor: NSObject, @unchecked Sendable {
    public let level: Int

    init(level: Int) {
        self.level = level
        super.init()
    }
}

open class CLLocationSourceInformation: NSObject, @unchecked Sendable {
    public let isSimulatedBySoftware: Bool
    public let isProducedByAccessory: Bool

    public init(softwareSimulationState isSoftware: Bool, hardwareAccessoryState isAccessory: Bool) {
        self.isSimulatedBySoftware = isSoftware
        self.isProducedByAccessory = isAccessory
        super.init()
    }
}

open class CLLocation: NSObject, @unchecked Sendable {
    public let coordinate: CLLocationCoordinate2D
    public let altitude: CLLocationDistance
    public let ellipsoidalAltitude: CLLocationDistance
    public let horizontalAccuracy: CLLocationAccuracy
    public let verticalAccuracy: CLLocationAccuracy
    public let course: CLLocationDirection
    public let courseAccuracy: CLLocationDirectionAccuracy
    public let speed: CLLocationSpeed
    public let speedAccuracy: CLLocationSpeedAccuracy
    public let timestamp: Date
    public let floor: CLFloor?
    public let sourceInformation: CLLocationSourceInformation?

    public convenience init(latitude: CLLocationDegrees, longitude: CLLocationDegrees) {
        self.init(
            coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
            altitude: 0, horizontalAccuracy: 0, verticalAccuracy: -1,
            course: -1, courseAccuracy: -1, speed: -1, speedAccuracy: -1,
            timestamp: Date(), sourceInfo: nil)
    }

    public convenience init(
        coordinate: CLLocationCoordinate2D, altitude: CLLocationDistance,
        horizontalAccuracy hAccuracy: CLLocationAccuracy, verticalAccuracy vAccuracy: CLLocationAccuracy,
        timestamp: Date
    ) {
        self.init(
            coordinate: coordinate, altitude: altitude, horizontalAccuracy: hAccuracy,
            verticalAccuracy: vAccuracy, course: -1, courseAccuracy: -1, speed: -1,
            speedAccuracy: -1, timestamp: timestamp, sourceInfo: nil)
    }

    public convenience init(
        coordinate: CLLocationCoordinate2D, altitude: CLLocationDistance,
        horizontalAccuracy hAccuracy: CLLocationAccuracy, verticalAccuracy vAccuracy: CLLocationAccuracy,
        course: CLLocationDirection, speed: CLLocationSpeed, timestamp: Date
    ) {
        self.init(
            coordinate: coordinate, altitude: altitude, horizontalAccuracy: hAccuracy,
            verticalAccuracy: vAccuracy, course: course, courseAccuracy: -1, speed: speed,
            speedAccuracy: -1, timestamp: timestamp, sourceInfo: nil)
    }

    public convenience init(
        coordinate: CLLocationCoordinate2D, altitude: CLLocationDistance,
        horizontalAccuracy hAccuracy: CLLocationAccuracy, verticalAccuracy vAccuracy: CLLocationAccuracy,
        course: CLLocationDirection, courseAccuracy: CLLocationDirectionAccuracy,
        speed: CLLocationSpeed, speedAccuracy: CLLocationSpeedAccuracy, timestamp: Date
    ) {
        self.init(
            coordinate: coordinate, altitude: altitude, horizontalAccuracy: hAccuracy,
            verticalAccuracy: vAccuracy, course: course, courseAccuracy: courseAccuracy, speed: speed,
            speedAccuracy: speedAccuracy, timestamp: timestamp, sourceInfo: nil)
    }

    public init(
        coordinate: CLLocationCoordinate2D, altitude: CLLocationDistance,
        horizontalAccuracy hAccuracy: CLLocationAccuracy, verticalAccuracy vAccuracy: CLLocationAccuracy,
        course: CLLocationDirection, courseAccuracy: CLLocationDirectionAccuracy,
        speed: CLLocationSpeed, speedAccuracy: CLLocationSpeedAccuracy, timestamp: Date,
        sourceInfo: CLLocationSourceInformation?
    ) {
        self.coordinate = coordinate
        self.altitude = altitude
        self.ellipsoidalAltitude = altitude
        self.horizontalAccuracy = hAccuracy
        self.verticalAccuracy = vAccuracy
        self.course = course
        self.courseAccuracy = courseAccuracy
        self.speed = speed
        self.speedAccuracy = speedAccuracy
        self.timestamp = timestamp
        self.floor = nil
        self.sourceInformation = sourceInfo
        super.init()
    }

    open func distance(from location: CLLocation) -> CLLocationDistance {
        let radius = 6_371_008.8
        let toRadians = Double.pi / 180
        let phi1 = coordinate.latitude * toRadians
        let phi2 = location.coordinate.latitude * toRadians
        let dPhi = phi2 - phi1
        let dLambda = (location.coordinate.longitude - coordinate.longitude) * toRadians
        let a = sin(dPhi / 2) * sin(dPhi / 2) + cos(phi1) * cos(phi2) * sin(dLambda / 2) * sin(dLambda / 2)
        return 2 * radius * atan2(a.squareRoot(), (1 - a).squareRoot())
    }

    open override var description: String {
        "<\(coordinate.latitude),\(coordinate.longitude)> +/- \(horizontalAccuracy)m @ \(timestamp)"
    }
}
#endif
