import Foundation

// Bridging session store for Assist subsystem
public final class AssistProjectSessionBridge: @unchecked Sendable {
    public static let shared = AssistProjectSessionBridge()

    public struct FileNodeInfo: Sendable {
        public var name: String
        public var path: String
        public init(name: String, path: String) {
            self.name = name
            self.path = path
        }
    }

    public var activeProject: AssistProject?
    public var activeFileNode: FileNodeInfo?
    public var activeFileContent: String = ""
    public var openFileTabs: [FileNodeInfo] = []
    public var modifiedFilePaths: Set<String> = []

    public init() {}
}

typealias ProjectSessionStore = AssistProjectSessionBridge
