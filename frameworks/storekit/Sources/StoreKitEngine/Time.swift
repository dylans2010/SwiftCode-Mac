import Foundation
import StoreKitConfiguration

public typealias StoreMilliseconds = Int64

extension Date {
    public var storeMilliseconds: StoreMilliseconds { StoreMilliseconds((timeIntervalSince1970 * 1000).rounded()) }

    public init(storeMilliseconds ms: StoreMilliseconds) { self.init(timeIntervalSince1970: TimeInterval(ms) / 1000) }
}

public protocol StoreClock: Sendable {
    func now() -> Date
}

public struct SystemClock: StoreClock {
    public init() {}
    public func now() -> Date { Date() }
}

public final class ManualClock: StoreClock, @unchecked Sendable {
    private let lock = NSLock()
    private var current: Date

    public init(_ start: Date) { current = start }

    public func now() -> Date { lock.withLock { current } }

    public func set(_ date: Date) { lock.withLock { current = date } }

    public func advance(by seconds: TimeInterval) { lock.withLock { current = current.addingTimeInterval(seconds) } }

    public func advance(milliseconds: StoreMilliseconds) {
        lock.withLock { current = Date(storeMilliseconds: current.storeMilliseconds + milliseconds) }
    }
}

public enum TimeRate: Int, Codable, Sendable, CaseIterable {
    case realTime = 0
    case oneHourIsOneDay = 1
    case thirtyMinutesIsOneDay = 2
    case fiveMinutesIsOneDay = 3
    case oneMinuteIsOneDay = 4
    case thirtySecondsIsOneDay = 5
    case oneSecondIsOneDay = 6
    case monthlyRenewalEveryHour = 10
    case monthlyRenewalEveryThirtyMinutes = 11
    case monthlyRenewalEveryFifteenMinutes = 12
    case monthlyRenewalEveryFiveMinutes = 13
    case monthlyRenewalEveryThirtySeconds = 15
    case oneRenewalEveryFifteenMinutes = 1000
    case oneRenewalEveryFiveMinutes = 1001
    case oneRenewalEveryMinute = 1002
    case oneRenewalEveryThirtySeconds = 1003
    case oneRenewalEveryTenSeconds = 1004
    case oneRenewalEveryTwoSeconds = 1005

    var fixedPeriodMilliseconds: StoreMilliseconds? {
        switch self {
        case .oneRenewalEveryFifteenMinutes: return 900_000
        case .oneRenewalEveryFiveMinutes: return 300_000
        case .oneRenewalEveryMinute: return 60_000
        case .oneRenewalEveryThirtySeconds: return 30_000
        case .oneRenewalEveryTenSeconds: return 10_000
        case .oneRenewalEveryTwoSeconds: return 2_000
        default: return nil
        }
    }

    var monthMilliseconds: StoreMilliseconds? {
        switch self {
        case .monthlyRenewalEveryHour: return 3_600_000
        case .monthlyRenewalEveryThirtyMinutes: return 1_800_000
        case .monthlyRenewalEveryFifteenMinutes: return 900_000
        case .monthlyRenewalEveryFiveMinutes: return 300_000
        case .monthlyRenewalEveryThirtySeconds: return 30_000
        default: return nil
        }
    }

    var dayMilliseconds: StoreMilliseconds? {
        switch self {
        case .oneHourIsOneDay: return 3_600_000
        case .thirtyMinutesIsOneDay: return 1_800_000
        case .fiveMinutesIsOneDay: return 300_000
        case .oneMinuteIsOneDay: return 60_000
        case .thirtySecondsIsOneDay: return 30_000
        case .oneSecondIsOneDay: return 1_000
        default: return nil
        }
    }

    public func end(of duration: SubscriptionDuration, count: Int = 1, from start: StoreMilliseconds, calendar: Calendar)
        -> StoreMilliseconds
    {
        let n = max(1, count)
        if let fixed = fixedPeriodMilliseconds { return start + fixed * StoreMilliseconds(n) }
        if let month = monthMilliseconds {
            let v = StoreMilliseconds(duration.value * n)
            switch duration.unit {
            case .year: return start + month * 12 * v
            case .month: return start + month * v
            case .week: return start + month * 7 * v / 30
            case .day: return start + month * v / 30
            }
        }
        if let day = dayMilliseconds {
            let v = StoreMilliseconds(duration.value * n)
            switch duration.unit {
            case .year: return start + day * 365 * v
            case .month: return start + day * 30 * v
            case .week: return start + day * 7 * v
            case .day: return start + day * v
            }
        }
        let component: Calendar.Component
        var value = duration.value * n
        switch duration.unit {
        case .day: component = .day
        case .week: component = .day; value *= 7
        case .month: component = .month
        case .year: component = .year
        }
        let date = calendar.date(byAdding: component, value: value, to: Date(storeMilliseconds: start))!
        return max(start + 1, date.storeMilliseconds)
    }
}
