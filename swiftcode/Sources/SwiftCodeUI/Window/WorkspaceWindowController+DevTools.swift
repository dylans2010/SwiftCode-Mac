import AppKit
import Foundation

extension WorkspaceWindowController {
    /// View ▸ Navigators ▸ Show Developer Tools…: the workspace's
    /// DevTools hub sheet (`DevToolsMainView`).
    ///
    /// Mirrors `showCollaboration:` (`WorkspaceWindowController+Collaboration.swift`):
    /// the menu item's action is the `CommandTable` selector string
    /// (`AppSupport.swift` builds menu items with `Selector(c.action)`),
    /// and it resolves through the responder chain to this `@objc` method,
    /// which posts the notification the SwiftUI shell listens for
    /// (`WorkspaceView` presents the sheet on `.showDevTools`).
    /// The name is spelled out here rather than referenced as `.showDevTools`
    /// because that static member lives in the `swiftcode-ide` target
    /// (`WorkspaceView.swift`), which `SwiftCodeUI` cannot see; the string
    /// must stay identical to the one defined there.
    @objc public func showDevTools(_ sender: Any?) {
        NotificationCenter.default.post(name: Notification.Name("com.swiftcode.showDevTools"), object: nil)
    }
}
