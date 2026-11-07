import Foundation
import Testing
@testable import SwiftCodeIDECore

@MainActor
@Suite(.serialized) struct MenuR43Tests {

    @Test func minimapIsOnInTheFactoryState() {
        let t = TestDefaults("r43-minimap")
        defer { t.remove() }
        let p = Preferences(defaults: t.defaults)
        #expect(p.showMinimap)
        #expect(t.defaults.persistentDomain(forName: t.suite)?["SwiftCode.minimap"] == nil)
        p.showMinimap = false
        #expect(!Preferences(defaults: t.defaults).showMinimap)
        p.showMinimap = true
        #expect(Preferences(defaults: t.defaults).showMinimap)
    }
}
