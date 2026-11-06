// Ported from Legacy (Dylan's own SwiftCode code, MIT-authorised direct port):
//   SwiftCode/Services/ToolbarSettings.swift
//
// Destination adaptations (behaviour preserved unless noted):
// * ObservableObject / @Published / Combine -> @Observable, the
//   destination's convention for ported state singletons (see
//   `SkillDiscoveryService` and the `MetaAssistLifecycleManager`
//   header: "No ObservableObject / @Published / Combine").
// * `@AppStorage` is a view-layer property wrapper and does not
//   reliably publish from an @Observable class, so `showToolNames`
//   is a stored property instead: it is initialised from the same
//   UserDefaults key Legacy's @AppStorage used
//   (`com.swiftcode.toolbar.showToolNames`, default `true`) and
//   persisted in `didSet`. The persisted key is unchanged, so the
//   setting survives the port.

import Foundation
import Observation

/// Shared editor-toolbar state: word wrap, the search bar, and
/// whether tool names are shown alongside their icons.
@MainActor
@Observable
public final class ToolbarSettings: Sendable {
    public static let shared = ToolbarSettings()

    public var wordWrap: Bool = false
    public var showSearchBar: Bool = false

    /// Whether toolbar tool names are shown. Persisted in UserDefaults
    /// under the same key Legacy used, so the preference carries over.
    public var showToolNames: Bool {
        didSet {
            UserDefaults.standard.set(showToolNames, forKey: Self.showToolNamesKey)
        }
    }

    private static let showToolNamesKey = "com.swiftcode.toolbar.showToolNames"

    private init() {
        self.showToolNames = UserDefaults.standard.object(forKey: Self.showToolNamesKey) as? Bool ?? true
    }
}
