import Foundation
import Testing
import AppKit
@testable import YcodeUI
import YcodeIcon

@Suite struct IconComposerTests {
    @Test @MainActor func handlesIconFileExtension() {
        let iconURL = URL(fileURLWithPath: "/path/to/MyIcon.icon")
        let pngURL = URL(fileURLWithPath: "/path/to/MyIcon.png")
        let assetURL = URL(fileURLWithPath: "/path/to/Assets.xcassets")

        #expect(IconComposerController.handles(iconURL))
        #expect(!IconComposerController.handles(pngURL))
        #expect(!IconComposerController.handles(assetURL))
    }

    @Test @MainActor func createsIconComposerController() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let iconURL = tempDir.appendingPathComponent("TestIcon.icon")
        let package = IconPackage(url: iconURL, document: IconDocument())
        try package.write(to: iconURL)

        let controller = IconComposerController(url: iconURL)
        #expect(controller.url == iconURL)
        #expect(controller.package != nil)
        #expect(controller.selectedPlatform == .iOS)
        #expect(controller.selectedAppearance == .light)
    }
}
