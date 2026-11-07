import Foundation
import OVPlatform
#if OPENVIEWS_RENAMED
import OpenViewsCore
#else
import SwiftUICore
#endif

public struct Settings<Content: View>: Scene {
    let content: @MainActor () -> Content

    public init(@ViewBuilder content: @escaping @MainActor () -> Content) {
        self.content = content
    }

    public typealias Body = Never
}

extension Settings: PrimitiveScene {
    package func _collect(into scenes: inout [SceneDescription]) {
        let content = content
        scenes.append(SceneDescription(kind: .settings, id: "openviews.settings", title: "Settings", content: { content() }))
    }
}

public struct OpenSettingsAction: Sendable {
    package let action: @MainActor @Sendable () -> Void
    package init(action: @escaping @MainActor @Sendable () -> Void) { self.action = action }
    @MainActor public func callAsFunction() { action() }
}

private enum OpenSettingsKey: EnvironmentKey {
    static let defaultValue = OpenSettingsAction(action: {})
}

extension EnvironmentValues {
    public var openSettings: OpenSettingsAction {
        get { self[OpenSettingsKey.self] }
        set { self[OpenSettingsKey.self] = newValue }
    }
}

public struct SettingsLink<Label: View>: View {
    let label: Label
    @Environment(\.openSettings) private var openSettings

    public init(@ViewBuilder label: () -> Label) { self.label = label() }

    public var body: some View {
        let open = openSettings
        Button(action: { open() }) { label }
    }
}

extension SettingsLink where Label == Text {
    public init() { self.init { Text("Settings…") } }
}
