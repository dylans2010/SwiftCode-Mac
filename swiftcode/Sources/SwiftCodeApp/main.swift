import AppKit
import SwiftCodeRelease
import SwiftCodeUI

SwiftCodeRelease.handleVersionFlag(tool: "SwiftCode")
SwiftCodeRelease.adoptBundledHelpers()
MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.regular)
    app.run()
}
