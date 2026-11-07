import Foundation

public enum BuildAlertSound: Sendable {
    case buildSuccess
    case buildFailure
}

public enum BuildAlertSoundHook {
    public nonisolated(unsafe) static var play: @Sendable (BuildAlertSound) -> Void = { _ in }
}
