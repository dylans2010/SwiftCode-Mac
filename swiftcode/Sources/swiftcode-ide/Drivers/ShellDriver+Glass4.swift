import Foundation
import SwiftUI
import SwiftCodeIDECore
import SwiftCodeIDEShell
#if os(Linux)
import OVPlatform
#endif

extension ShellDriver {
    #if os(Linux)
    static func glass4Walk(_ app: ShellAppModel, prefix: String) async {
        guard let w = app.workspace else { say("g4: no workspace"); return }
        func shot(_ name: String) async {
            await pause(0.6)
            say("g4 \(name): document=\(w.document?.path ?? "-") navigator=\(w.navigator) "
                + OpenViewsAutomation.screenshot(to: "\(prefix)-g4-\(name).png"))
        }
        await shot("74-empty-editor")
        say("g4 74: minimap target \(frame("minimap").map { "\($0)" } ?? "none")")
        if let bands = w.root.allFiles.compactMap(\.path).first(where: { $0.hasSuffix("Bands.swift") }) {
            if let ids = w.root.idPath(to: bands) { for id in ids.dropLast() { w.setExpanded(id, true) } }
            await pause(0.3)
            if let id = w.root.idPath(to: bands)?.last { await clickProjectRow(w, id: id, dx: 10) }
            if w.document?.path != bands { w.open(bands) }
            await shot("75-77-bands-outline-focused")
            say("g4 77: editor \(frame("editor").map { "\($0)" } ?? "-") minimap \(frame("minimap").map { "\($0)" } ?? "-")")
            if let e = frame("editor") { await OpenViewsAutomation.click(at: CGPoint(x: e.midX, y: e.midY)) }
            await shot("81-editor-focused")
        } else {
            say("g4: no Bands.swift under the workspace")
        }
        await click("selector 1")
        await pause(0.8)
        await click("scm mode 1")
        await w.sourceControl.idle()
        await shot("82-repositories")
        say("g4 82: rows \(w.sourceControl.rows.map(\.title)) collapsed \(w.sourceControl.collapsed.sorted())")
    }
    #endif
}
