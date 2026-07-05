import SwiftUI
import Combine

class ToolbarSettings: ObservableObject {
    static let shared = ToolbarSettings()

    @Published var wordWrap: Bool = false
    @Published var showSearchBar: Bool = false
    @AppStorage("com.swiftcode.toolbar.showToolNames") var showToolNames: Bool = true

    private init() {}
}
