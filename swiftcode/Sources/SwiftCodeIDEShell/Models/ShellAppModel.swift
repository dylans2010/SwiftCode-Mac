import Foundation
import Observation
import SwiftCodeBuild
import SwiftCodeIDECore

@MainActor
@Observable
public final class ShellAppModel {
    public private(set) var workspace: WorkspaceShellModel?
    public var isOpenSheetShown = false
    public var openPath = ""
    public private(set) var openError: String?
    public private(set) var recent: [URL] = []
    public var newProject: NewProjectShellModel?
    public var clone: CloneShellModel?
    public var isAboutShown = false
    public var runtimeSetup: RuntimeSetupSession?
    @ObservationIgnored public var runtimeDefaults: UserDefaults = .standard
    public var notice: ShellNotice?
    @ObservationIgnored public var openExternally: (URL) -> Void = { _ in }
    @ObservationIgnored public let organizer = OrganizerShellModel()
    @ObservationIgnored public var openWindow: (String) -> Void = { _ in }
    @ObservationIgnored public var newProjectDefaults: UserDefaults = .standard

    public enum PendingClose: Equatable, Sendable {
        case closeWorkspace, quit
        case open(String)
    }
    public private(set) var pendingClose: PendingClose?
    @ObservationIgnored public var startsLanguageService = false
    @ObservationIgnored public var terminateApp: () -> Void = {}

    @ObservationIgnored let recentProjects: RecentProjects
    @ObservationIgnored let makeEngine: () -> BuildEngine

    public init(recentProjects: RecentProjects = .shared, engine: @escaping () -> BuildEngine = { ShellBuildSetup.engine() }) {
        self.recentProjects = recentProjects
        makeEngine = engine
        recent = recentProjects.urls
    }

    public static func launchPath(_ arguments: [String] = CommandLine.arguments,
                                  workingDirectory: String = FileManager.default.currentDirectoryPath) -> String? {
        var i = 1
        while i < arguments.count {
            let a = arguments[i]
            i += 1
            if a.hasPrefix("-") {
                if a.dropFirst().first?.isUppercase == true { i += 1 }
                continue
            }
            return a.hasPrefix("/") ? a : (workingDirectory as NSString).appendingPathComponent(a)
        }
        return nil
    }

    @discardableResult
    public func open(path: String) -> Bool {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        let expanded = (trimmed as NSString).expandingTildeInPath
        guard !expanded.isEmpty else {
            openError = "Enter the path of a project, workspace or package."
            return false
        }
        let url = URL(fileURLWithPath: expanded)
        if workspace?.hasUnsavedChanges == true {
            pendingClose = .open(expanded)
            isOpenSheetShown = false
            return true
        }
        do {
            workspace = try WorkspaceShellModel(url: url, engine: makeEngine())
            workspace?.debug.restoreBreakpoints()
            if startsLanguageService { workspace?.startLanguageService() }
            openError = nil
            isOpenSheetShown = false
            recentProjects.note(url)
            recent = recentProjects.urls
            return true
        } catch {
            openError = "\(url.lastPathComponent) is not a project, workspace or package folder."
            return false
        }
    }

    public func closeWorkspace() {
        guard workspace?.hasUnsavedChanges != true else {
            pendingClose = .closeWorkspace
            return
        }
        discardWorkspace()
    }

    private func discardWorkspace() {
        workspace?.stopLanguageService()
        workspace?.previewCanvas.stop()
        workspace?.stop()
        workspace = nil
        recent = recentProjects.urls
    }

    public func shouldQuit() -> Bool {
        guard workspace?.hasUnsavedChanges == true else { return true }
        pendingClose = .quit
        return false
    }

    public enum CloseAnswer: Sendable { case saveAll, discard, cancel }

    public func answerClose(_ answer: CloseAnswer) {
        guard let pending = pendingClose else { return }
        pendingClose = nil
        switch answer {
        case .cancel: return
        case .saveAll: if workspace?.saveAll() == false { return }
        case .discard: workspace?.discardAllRecoveryCopies()
        }
        switch pending {
        case .closeWorkspace: discardWorkspace()
        case .quit:
            workspace?.stop()
            terminateApp()
        case .open(let path):
            discardWorkspace()
            open(path: path)
        }
    }

    public func showOpenSheet() {
        openError = nil
        isOpenSheetShown = true
    }

    public func clearOpenError() { openError = nil }

    public func isEnabled(_ c: ShellCommand) -> Bool {
        switch c {
        case .open, .welcome, .newProject, .about, .help, .releaseNotes, .reportBug, .swiftBook, .clone, .downloads, .organizer: true
        case .closeWorkspace: workspace != nil
        default: workspace?.isEnabled(c) ?? false
        }
    }

    public func perform(_ c: ShellCommand) {
        switch c {
        case .open: showOpenSheet()
        case .newProject: showNewProject()
        case .closeWorkspace: closeWorkspace()
        case .welcome: closeWorkspace()
        case .about: isAboutShown = true
        case .help: openLink(ProductIdentity.helpURL)
        case .releaseNotes: openLink(ProductIdentity.releasesURL)
        case .reportBug: openLink(ProductIdentity.bugReportURL())
        case .swiftBook: if let u = URL(string: "https://docs.swift.org/swift-book/") { openLink(u) }
        case .clone: showClone()
        case .downloads: showRuntimeSetup()
        case .organizer: showOrganizer()
        default: workspace?.perform(c)
        }
    }

    public func title(_ c: ShellCommand) -> String { c.title(in: workspace?.menuContext) }

    public func isChecked(_ c: ShellCommand) -> Bool? { workspace.flatMap { $0.debug.isChecked(c) ?? $0.isPreviewCommandChecked(c) } }
}
