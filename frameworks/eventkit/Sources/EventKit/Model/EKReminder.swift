import Foundation

public class EKReminder: EKCalendarItem {
    var reminder = ReminderFields()

    public init(eventStore: EKEventStore) {
        super.init(store: eventStore)
    }

    override init(store: EKEventStore) {
        super.init(store: store)
    }

    public var startDateComponents: DateComponents? {
        get { reminder.start }
        set { reminder.start = newValue }
    }

    public var dueDateComponents: DateComponents? {
        get { reminder.due }
        set { reminder.due = newValue }
    }

    public var isCompleted: Bool {
        get { reminder.completed }
        set {
            reminder.completed = newValue
            reminder.completionDate = newValue ? (reminder.completionDate ?? Date()) : nil
        }
    }

    public var completionDate: Date? {
        get { reminder.completionDate }
        set {
            reminder.completionDate = newValue
            reminder.completed = newValue != nil
        }
    }

    public var priority: Int {
        get { reminder.priority }
        set { reminder.priority = newValue }
    }

    override func snapshot() -> ItemSnapshot {
        var s = super.snapshot()
        s.reminder = reminder
        return s
    }

    override func apply(_ s: ItemSnapshot) {
        super.apply(s)
        if let r = s.reminder { reminder = r }
    }

    public override var description: String {
        "EKReminder <\(objectAddress)> {title = \(common.title); dueDate = \(String(describing: reminder.due)); completed = \(reminder.completed ? 1 : 0); priority = \(reminder.priority)}"
    }
}
