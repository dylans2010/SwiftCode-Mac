import Foundation

class EKStorePredicate: NSPredicate {
    #if canImport(Darwin)
    override init() { super.init() }
    #else
    init() { super.init(value: true) }
    #endif

    required init?(coder: NSCoder) { nil }
}

final class EKEventPredicate: EKStorePredicate {
    let start: Date
    let end: Date
    let calendarIDs: [String]?
    let zone: TimeZone

    init(start: Date, end: Date, calendarIDs: [String]?, zone: TimeZone) {
        self.start = start
        self.end = end
        self.calendarIDs = calendarIDs
        self.zone = zone
        super.init()
    }

    required init?(coder: NSCoder) { nil }

    override var predicateFormat: String { description }

    override var description: String {
        func local(_ d: Date) -> String {
            let l = LocalDateTime(date: d, zone: zone)
            return String(format: "%d/%d/%02d, %d:%02d", l.month, l.day, l.year % 100, l.hour, l.minute)
        }
        let cals = calendarIDs.map { "(\($0.joined(separator: ", ")))" } ?? "(null)"
        return "EKEventPredicate start:\(local(start)); end:\(local(end)); cals:\(cals)"
    }
}

final class EKReminderPredicate: EKStorePredicate {
    enum Kind {
        case all
        case incomplete(start: Date?, end: Date?)
        case completed(start: Date?, end: Date?)
    }

    let kind: Kind
    let calendarIDs: [String]?

    init(kind: Kind, calendarIDs: [String]?) {
        self.kind = kind
        self.calendarIDs = calendarIDs
        super.init()
    }

    required init?(coder: NSCoder) { nil }

    override var predicateFormat: String { description }
    override var description: String { "ReminderPredicate" }
}

final class EKReminderFetchRequest: NSObject, @unchecked Sendable {
    private let lock = NSLock()
    private var _cancelled = false
    var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return _cancelled }
    func cancel() { lock.lock(); _cancelled = true; lock.unlock() }
}
