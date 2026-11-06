import Foundation

public enum WorkerEventType: String, Codable, Sendable, CaseIterable {
    case workerCreated = "WorkerCreated"
    case workerQueued = "WorkerQueued"
    case workerStarted = "WorkerStarted"
    case workerProgressUpdated = "WorkerProgressUpdated"
    case workerRecapUpdated = "WorkerRecapUpdated"
    case workerFileChanged = "WorkerFileChanged"
    case workerTestStarted = "WorkerTestStarted"
    case workerTestCompleted = "WorkerTestCompleted"
    case workerReviewStarted = "WorkerReviewStarted"
    case workerReviewCompleted = "WorkerReviewCompleted"
    case workerCompleted = "WorkerCompleted"
    case workerFailed = "WorkerFailed"
    case workerCancelled = "WorkerCancelled"
    case workerHandoffStarted = "WorkerHandoffStarted"
    case workerHandoffCompleted = "WorkerHandoffCompleted"
    case workerStandby = "WorkerStandby"
    case workerRecovered = "WorkerRecovered"
    case workerBlocked = "WorkerBlocked"

    public var sfSymbolName: String {
        switch self {
        case .workerCreated: return "plus.circle"
        case .workerQueued: return "hourglass"
        case .workerStarted: return "play.circle.fill"
        case .workerProgressUpdated: return "waveform.path.ecg"
        case .workerRecapUpdated: return "note.text"
        case .workerFileChanged: return "doc.badge.gearshape"
        case .workerTestStarted: return "testtube.2"
        case .workerTestCompleted: return "checkmark.diamond"
        case .workerReviewStarted: return "eye.circle"
        case .workerReviewCompleted: return "checkmark.shield"
        case .workerCompleted: return "checkmark.circle.fill"
        case .workerFailed: return "exclamationmark.triangle.fill"
        case .workerCancelled: return "xmark.circle"
        case .workerHandoffStarted: return "arrow.right.arrow.left"
        case .workerHandoffCompleted: return "person.line.dotted.person.fill"
        case .workerStandby: return "pause.circle"
        case .workerRecovered: return "bandage.fill"
        case .workerBlocked: return "hand.raised.fill"
        }
    }

    public var icon: String {
        sfSymbolName
    }
}

public struct WorkerEvent: Identifiable, Codable, Sendable {
    public let id: UUID
    public let workerID: UUID
    public let timestamp: Date
    public let type: WorkerEventType
    public let title: String
    public let details: String
    public let metadata: [String: String]?

    public init(
        id: UUID = UUID(),
        workerID: UUID,
        timestamp: Date = Date(),
        type: WorkerEventType,
        title: String,
        details: String = "",
        metadata: [String: String]? = nil
    ) {
        self.id = id
        self.workerID = workerID
        self.timestamp = timestamp
        self.type = type
        self.title = title
        self.details = details
        self.metadata = metadata
    }

    /// Clean human-readable presentation for event timeline
    public var formattedTimestamp: String {
        let formatter = DateFormatter()
        formatter.timeStyle = .medium
        formatter.dateStyle = .none
        return formatter.string(from: timestamp)
    }

    public var eventType: WorkerEventType {
        type
    }

    public var message: String {
        details.isEmpty ? title : "\(title): \(details)"
    }

    public var filePath: String? {
        metadata?["filePath"]
    }
}
