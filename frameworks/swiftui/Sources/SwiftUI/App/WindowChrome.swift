import Foundation
import Observation
import OVPlatform
#if OPENVIEWS_RENAMED
import OpenViewsCore
#else
import SwiftUICore
#endif

@MainActor
@Observable
package final class SidebarController {
    package var isVisible = true
    @ObservationIgnored var toggleAction: (() -> Void)?
    package init() {}
    package func toggle() { toggleAction?() }
}

@MainActor
struct WindowChromeConfiguration {
    var menuBar: Bool
    let commands: CommandsModel
    let actions: AppCommandActions
}
