import AppKit
import YcodeIDECore

extension WorkspaceWindowController {
    @objc public func toggleToolsDrawer(_ sender: Any?) {
        let folder = session.model.workspaceDirectoryURL ?? session.model.projects.keys.first.map(URL.init(fileURLWithPath:))
        SCToolsWindowManager.shared.toggle(workspaceFolder: folder)
    }
}
