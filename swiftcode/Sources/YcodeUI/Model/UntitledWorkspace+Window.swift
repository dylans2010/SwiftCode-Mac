import AppKit
import YcodeIDECore

extension NewProjectFlow {
    @MainActor
    static func emptyWorkspaceWindow() -> WorkspaceWindowController {
        let wc = WorkspaceWindowController(session: WorkspaceSession(model: .untitled()), loadDestinations: false, startLanguageService: false,
                                           userStateURL: nil)
        wc.window?.title = "Untitled"
        return wc
    }
}
