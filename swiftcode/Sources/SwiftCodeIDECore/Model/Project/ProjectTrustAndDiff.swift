import Foundation

/// `.scproj` trust, assist diff banners, and the Swift file template
/// (Legacy `SwiftCode/Services/ProjectSessionStore.swift`, Dylan's
/// own code, ported under MIT).
///
/// Legacy's `ProjectSessionStore` is a whole session store that does
/// not exist in the destination (sessions are `WorkspaceSession`s);
/// these are the portable pieces of it: the diff banner state and
/// the new-file template. (The trust store is NOT duplicated here:
/// `SwiftCodeIDEShell.ScprojTrustStore` is the single definition —
/// a second copy in this module would make every unqualified
/// `ScprojTrustStore` reference ambiguous in files importing both
/// modules, e.g. `SwiftCodeIDEApp`. Same UserDefaults key, same API.)
/// `openScprojPackage` keeps Legacy's in-place semantics — the
/// package's project opens as-is and is never copied or re-identified
/// (unlike `SCProjectCoordinator.importProject`, which mints a copy
/// under a projects root).
///
/// Wiring: the `.scproj` open flow uses
/// `SwiftCodeIDEShell.ScprojTrustStore` (trust alert → `markTrusted`
/// → `openScprojPackage`); the diff banner state belongs on the
/// editor's session object, which calls `recordAssistFileMutation`
/// after an assist file edit and `dismissDiffBanner` from the
/// banner's dismiss action.

/// One assist file mutation, for the diff banner (Legacy
/// `ProjectSessionStore.AssistFileDiff`, renamed here because
/// `SwiftCodeAssistant` already has a different `AssistFileDiff`
/// snapshot type — same name, different shape).
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

/// The diff banner state Legacy kept on its session store. The
/// editor's session object owns one of these; it calls
/// `recordAssistFileMutation` after an assist file edit and
/// `dismissDiffBanner` from the banner's dismiss action. Legacy also
/// opened the mutated file from `recordAssistFileMutation`; the
/// caller does that here (this state has no session to open it in).
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

    /// Opens a `.scproj` package directory in place, after the trust
    /// alert has approved it. The package must be a directory holding
    /// `project.json` (at its root, or inside `SwiftCode/` for the
    /// new layout); the package's project is the project that opens.
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

    /// The new-Swift-file template (Legacy
    /// `ProjectSessionStore.generateSwiftTemplate`, verbatim text).
    /// `author` / `customComment` are the settings values Legacy
    /// read from `AppSettings` (`fileHeaderAuthor` /
    /// `fileHeaderCustomComment`); pass them in because the
    /// destination has no `AppSettings` singleton. An empty author
    /// renders as `"User"` and an empty custom comment as
    /// `"Made with SwiftCode"`, exactly as Legacy did.
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
