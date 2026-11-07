import Foundation

public struct AssistSessionFileDiff: Identifiable, Sendable {
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

@MainActor
public final class AssistDiffBannerState: ObservableObject {
    public static let shared = AssistDiffBannerState()

    @Published public var activeFileDiff: AssistSessionFileDiff?
    @Published public var showDiffBanner = false

    public init() {}

    public func recordAssistFileMutation(
        path: String,
        beforeContent: String,
        afterContent: String,
        addedLines: Int,
        deletedLines: Int
    ) {
        activeFileDiff = AssistSessionFileDiff(
            filePath: path,
            beforeContent: beforeContent,
            afterContent: afterContent,
            addedLines: addedLines,
            deletedLines: deletedLines
        )
        showDiffBanner = (addedLines > 0 || deletedLines > 0)
    }

    public func dismissDiffBanner() {
        showDiffBanner = false
        activeFileDiff = nil
    }
}

public enum ProjectTrustAndDiff {
    public enum ScprojOpenError: Error, LocalizedError {
        case notAPackage(URL)
        case noMetadata(URL)

        public var errorDescription: String? {
            switch self {
            case .notAPackage(let url):
                return "\(url.lastPathComponent) is not a package directory."
            case .noMetadata(let url):
                return "\(url.lastPathComponent) has no project.json metadata."
            }
        }
    }

    public static func openScprojPackage(at url: URL) async throws -> WorkspaceSession {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue else {
            throw ScprojOpenError.notAPackage(url)
        }
        let candidates = [
            url.appendingPathComponent("project.json"),
            url.appendingPathComponent("SwiftCode/project.json"),
        ]
        guard candidates.contains(where: { FileManager.default.fileExists(atPath: $0.path) }) else {
            throw ScprojOpenError.noMetadata(url)
        }
        return try await ProjectOpeningCoordinator.shared.open(url)
    }

    public static func generateSwiftTemplate(
        for name: String,
        in projectName: String,
        author: String = "",
        customComment: String = ""
    ) -> String {
        let rawName = (name as NSString).deletingPathExtension
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .joined()
        let structName = (rawName.isEmpty || rawName.first?.isLetter == false) ? "UntitledView" : rawName
        let authorDisplay = author.trimmingCharacters(in: .whitespacesAndNewlines)
        let authorShown = authorDisplay.isEmpty ? "User" : authorDisplay
        let comment = customComment.trimmingCharacters(in: .whitespacesAndNewlines)

        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .short
        dateFormatter.timeStyle = .none
        let dateStr = dateFormatter.string(from: Date())

        return """
        //  \(name)
        //  \(projectName)
        //
        //  Created by \(authorShown) on \(dateStr).
        //  \(comment.isEmpty ? "Made with SwiftCode" : comment)
        //

        import SwiftUI

        struct \(structName): View {
            var body: some View {
                VStack {
                    Text("Hello, World!")
                }
                .padding()
            }
        }

        #Preview {
            \(structName)()
        }
        """
    }
}
