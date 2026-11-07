import AppKit
import Foundation

extension WorkspaceWindowController {
    @objc public func showDevTools(_ sender: Any?) {
        NotificationCenter.default.post(name: Notification.Name("com.swiftcode.showDevTools"), object: nil)
    }
}
