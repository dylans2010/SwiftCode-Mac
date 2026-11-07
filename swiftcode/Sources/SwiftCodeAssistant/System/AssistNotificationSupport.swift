import Foundation

#if canImport(AppKit)
import AppKit
#endif

public enum AssistAlertSound: Sendable {
    case agentThinking
    case agentResponseReady
    case agentNeedsAttention
}

public final class AlertSoundPlayer: @unchecked Sendable {
    public static let shared = AlertSoundPlayer()

    public var isEnabled = true

    private init() {}

    public func play(_ sound: AssistAlertSound) {
        guard isEnabled else { return }
        #if canImport(AppKit)
        let name: String
        switch sound {
        case .agentThinking: name = "Pop"
        case .agentResponseReady: name = "Glass"
        case .agentNeedsAttention: name = "Basso"
        }
        NSSound(named: NSSound.Name(name))?.play()
        #else
        _ = sound
        #endif
    }
}

public final class NotificationManager: @unchecked Sendable {
    public static let shared = NotificationManager()

    public var isEnabled = true

    private init() {}

    public func sendAgentTaskFinishedNotification(title: String = "Assist", body: String = "The task finished.") {
        guard isEnabled else { return }
        #if canImport(AppKit)
        let notification = NSUserNotification()
        notification.title = title
        notification.informativeText = body
        NSUserNotificationCenter.default.deliver(notification)
        #else
        _ = (title, body)
        #endif
    }
}

public struct AssistPendingQuestion: Sendable {
    public let id: UUID
    public let prompt: String
    public var options: [String]

    public init(id: UUID = UUID(), prompt: String, options: [String] = []) {
        self.id = id
        self.prompt = prompt
        self.options = options
    }
}

@MainActor
public final class PlanQuestionManager {
    public static let shared = PlanQuestionManager()

    public private(set) var pendingQuestions: [AssistPendingQuestion] = []
    private var resolvers: [UUID: (String?) -> Void] = [:]

    private init() {}

    public func register(_ question: AssistPendingQuestion, resolver: @escaping (String?) -> Void) {
        pendingQuestions.append(question)
        resolvers[question.id] = resolver
    }

    public func resolve(questionID: UUID, answer: String?) {
        guard let resolver = resolvers.removeValue(forKey: questionID) else { return }
        pendingQuestions.removeAll { $0.id == questionID }
        resolver(answer)
    }

    public func cancelPendingQuestions() {
        let pending = resolvers
        resolvers.removeAll()
        pendingQuestions.removeAll()
        for (_, resolver) in pending { resolver(nil) }
    }
}
