import Foundation
import Observation

@Observable
class SceneModel {
    public var windowID: UUID = UUID()
    public var isMainSidebarVisible: Bool = true

    public init() {}
}
