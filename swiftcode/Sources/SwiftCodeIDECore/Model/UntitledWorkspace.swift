import Foundation

extension WorkspaceModel {
    public static func untitled() -> WorkspaceModel {
        WorkspaceModel(untitledAt: FileManager.default.temporaryDirectory
            .appendingPathComponent("swiftcode-untitled-\(UUID().uuidString)/Untitled.xcworkspace"))
    }

    init(untitledAt url: URL) {
        self.url = url
        kind = .workspace
        root = NavigatorNode(name: "Untitled", kind: .container, path: url.path, children: [])
        schemeNames = []
    }

    public var isUntitled: Bool { kind == .workspace && !FileManager.default.fileExists(atPath: url.path) && projects.isEmpty }
}
