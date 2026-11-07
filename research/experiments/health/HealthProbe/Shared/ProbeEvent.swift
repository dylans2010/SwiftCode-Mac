import Foundation
import HealthKit

struct ProbeEvent: Codable {
    var v = 1
    var session = ""
    var seq = 0
    var origin = "watch"
    var kind: String
    var type: String?
    var startOffset: Double?
    var endOffset: Double?
    var deliveredOffset: Double?
    var phoneReceivedOffset: Double?
    var value: Double?
    var sum: Double?
    var unit: String?
    var seriesCount: Int?
    var metadataKeys: [String]?
    var note: String?
    var activity: UInt?
    var location: Int?
    var transport: String?
    var startEpoch: Double?

    init(kind: String) { self.kind = kind }
}

enum ProbeTypes {
    static let quantities: [HKQuantityTypeIdentifier] = [
        .heartRate, .activeEnergyBurned, .basalEnergyBurned, .distanceWalkingRunning, .stepCount,
    ]

    static func unit(for id: HKQuantityTypeIdentifier) -> HKUnit {
        switch id {
        case .heartRate: return HKUnit.count().unitDivided(by: .minute())
        case .activeEnergyBurned, .basalEnergyBurned: return .kilocalorie()
        case .distanceWalkingRunning: return .meter()
        default: return .count()
        }
    }

    static var readTypes: Set<HKObjectType> {
        var s = Set<HKObjectType>(quantities.map { HKQuantityType($0) })
        s.insert(HKObjectType.workoutType())
        return s
    }

    static var shareTypes: Set<HKSampleType> { [HKObjectType.workoutType()] }

    static func event(for sample: HKQuantitySample, start: Date, kind: String, origin: String) -> ProbeEvent {
        let id = HKQuantityTypeIdentifier(rawValue: sample.quantityType.identifier)
        let unit = unit(for: id)
        var e = ProbeEvent(kind: kind)
        e.origin = origin
        e.type = sample.quantityType.identifier
        e.startOffset = sample.startDate.timeIntervalSince(start)
        e.endOffset = sample.endDate.timeIntervalSince(start)
        e.deliveredOffset = Date().timeIntervalSince(start)
        if sample.quantity.is(compatibleWith: unit) {
            e.value = sample.quantity.doubleValue(for: unit)
            e.unit = unit.unitString
        }
        e.seriesCount = sample.count
        e.metadataKeys = sample.metadata.map { Array($0.keys).sorted() } ?? []
        return e
    }
}
