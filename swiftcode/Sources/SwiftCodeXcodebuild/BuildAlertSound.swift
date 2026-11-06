import Foundation

// MARK: - BuildAlertSound
//
// A build outcome that the UI may choose to announce with an alert
// sound. The sound itself is a UI concern: this lower layer only reports
// the outcome, and `SwiftCodeUI` installs `BuildAlertSoundHook.play` at
// launch (Legacy played the tone from its build service, which sat in
// the app layer; SwiftCode keeps the layering one-way). The default is a
// no-op, so headless builds — CI, `swiftcodebuild` — stay silent.

/// The build outcome the UI may announce.
public enum BuildAlertSound: Sendable {
    case buildSuccess
    case buildFailure
}

/// The installable sink for `BuildAlertSound`. Set once by the UI at
/// launch; `nonisolated(unsafe)` because it is written before any build
/// runs and only read from the build queue thereafter.
public enum BuildAlertSoundHook {
    public nonisolated(unsafe) static var play: @Sendable (BuildAlertSound) -> Void = { _ in }
}
