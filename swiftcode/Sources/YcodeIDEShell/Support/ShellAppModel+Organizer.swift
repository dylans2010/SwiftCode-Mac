import Foundation
import YcodeIDECore

extension ShellAppModel {
    public static let organizerWindowID = "organizer"

    public func showOrganizer() {
        organizer.reload()
        openWindow(Self.organizerWindowID)
    }
}
