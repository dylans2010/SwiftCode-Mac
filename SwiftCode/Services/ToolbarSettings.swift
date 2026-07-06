import SwiftUI
import Combine

@MainActor
class ToolbarSettings: ObservableObject, Sendable {
    static let shared = ToolbarSettings()

    @Published var wordWrap: Bool = false
    @Published var showSearchBar: Bool = false
    @AppStorage("com.swiftcode.toolbar.showToolNames") var showToolNames: Bool = true

    private init() {}
}
