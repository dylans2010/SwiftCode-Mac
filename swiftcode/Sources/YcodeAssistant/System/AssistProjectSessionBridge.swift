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

    public struct AssistFileDiff: Identifiable, Sendable {
        public let id: UUID
        public let filePath: String
        public let beforeContent: String
        public let afterContent: String
        public let addedLines: Int
        public let deletedLines: Int
        public let timestamp: Date

        public init(
            id: UUID = UUID(),
            filePath: String,
            beforeContent: String,
            afterContent: String,
            addedLines: Int,
            deletedLines: Int,
            timestamp: Date = Date()
        ) {
            self.id = id
            self.filePath = filePath
            self.beforeContent = beforeContent
            self.afterContent = afterContent
            self.addedLines = addedLines
            self.deletedLines = deletedLines
            self.timestamp = timestamp
        }
    }

    public var activeProject: AssistProject?
    public var activeFileNode: FileNodeInfo?
    public var activeFileContent: String = ""
    public var openFileTabs: [FileNodeInfo] = []
    public var modifiedFilePaths: Set<String> = []
    public var activeFileDiff: AssistFileDiff?
    public var showDiffBanner: Bool = false

    public init() {}

    public func recordAssistFileMutation(
        path: String,
        beforeContent: String,
        afterContent: String,
        addedLines: Int,
        deletedLines: Int
    ) {
        let diff = AssistFileDiff(
            filePath: path,
            beforeContent: beforeContent,
            afterContent: afterContent,
            addedLines: addedLines,
            deletedLines: deletedLines
        )
        self.activeFileDiff = diff
        self.showDiffBanner = (addedLines > 0 || deletedLines > 0)
        self.modifiedFilePaths.insert(path)
    }

    public func openProject(_ project: AssistProject) async {
        self.activeProject = project
    }

    public func createFile(named name: String, inDirectory directoryPath: String?, project: AssistProject, initialContent: String? = nil) throws {
        var targetDir = project.directoryURL
        if let dir = directoryPath, !dir.isEmpty {
            targetDir = targetDir.appendingPathComponent(dir)
        }
        try FileManager.default.createDirectory(at: targetDir, withIntermediateDirectories: true)
        let fileURL = targetDir.appendingPathComponent(name)
        try (initialContent ?? "").write(to: fileURL, atomically: true, encoding: .utf8)
    }

    public func createFolder(named name: String, inDirectory directoryPath: String?, project: AssistProject) throws {
        var targetDir = project.directoryURL
        if let dir = directoryPath, !dir.isEmpty {
            targetDir = targetDir.appendingPathComponent(dir)
        }
        let folderURL = targetDir.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
    }
}

public typealias ProjectSessionStore = AssistProjectSessionBridge
