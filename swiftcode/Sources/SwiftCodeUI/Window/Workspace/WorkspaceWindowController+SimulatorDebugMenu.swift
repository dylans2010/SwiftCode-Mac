import AppKit
import SwiftCodeIDECore
import SwiftCodeSimFeatures

extension WorkspaceWindowController {
    var simulatorRunTakesOverrides: Bool {
        debugArea.syncWithRun()
        return debugArea.applyEnvironmentOverrides != nil && debugArea.simulatorRunKey?() != nil
    }

    @objc public func disableAllEnvironmentOverrides(_ sender: Any?) { disableAllOverrides() }

    @discardableResult
    public func disableAllOverrides() -> Task<(Bool, String), Never>? { sendEnvironmentOverrides(EnvironmentOverrides()) }

    @objc public func debugAppearanceSystem(_ sender: Any?) { _ = chooseDebugAppearance(0) }
    @objc public func debugAppearanceLight(_ sender: Any?) { _ = chooseDebugAppearance(1) }
    @objc public func debugAppearanceDark(_ sender: Any?) { _ = chooseDebugAppearance(2) }
    @objc public func debugAppearanceHighContrastLight(_ sender: Any?) { _ = chooseDebugAppearance(3) }
    @objc public func debugAppearanceHighContrastDark(_ sender: Any?) { _ = chooseDebugAppearance(4) }

    @discardableResult
    public func chooseDebugAppearance(_ index: Int) -> Task<(Bool, String), Never>? {
        debugArea.syncWithRun()
        return sendEnvironmentOverrides(DebugAppearanceMenu.apply(index, to: debugArea.environmentOverrides))
    }

    func sendEnvironmentOverrides(_ o: EnvironmentOverrides) -> Task<(Bool, String), Never>? {
        guard simulatorRunTakesOverrides, let apply = debugArea.applyEnvironmentOverrides else { NSSound.beep(); return nil }
        debugArea.environmentOverrides = o
        return Task { await apply(o) }
    }

    func validateSimulatorDebugMenuItem(_ item: NSMenuItem) -> Bool? {
        guard let a = item.action else { return nil }
        let name = NSStringFromSelector(a)
        if let i = DebugAppearanceMenu.actions.firstIndex(of: name) {
            let on = simulatorRunTakesOverrides
            item.state = on && DebugAppearanceMenu.checkedIndex(debugArea.environmentOverrides) == i ? .on : .off
            return on
        }
        if name == "disableAllEnvironmentOverrides:" { return simulatorRunTakesOverrides && !debugArea.environmentOverrides.isEmpty }
        return nil
    }
}

extension DynamicMenus {
    static func fillSimulateLocation(_ m: NSMenu, controller wc: WorkspaceWindowController?) {
        m.removeAllItems()
        m.autoenablesItems = false
        guard let wc else {
            let note = NSMenuItem(title: "Location simulation needs a run on the SwiftCode simulator", action: nil, keyEquivalent: "")
            note.isEnabled = false
            m.addItem(note)
            return
        }
        let source = wc.debugArea.simulateLocationMenu()
        for item in source.items {
            source.removeItem(item)
            m.addItem(item)
        }
    }
}
