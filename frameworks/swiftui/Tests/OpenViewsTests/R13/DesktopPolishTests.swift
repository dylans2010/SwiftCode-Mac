import Foundation
import OVPlatform
import OVRender
import Testing
#if OPENVIEWS_RENAMED
@testable import OpenViewsCore
@testable import OpenViews
#else
@testable import SwiftUICore
@testable import SwiftUI
#endif

@MainActor
@Suite("Desktop polish")
struct DesktopPolishTests {

    @Test func viewsCopyThroughTheAppsClipboard() {
        let h = CommandsHarness {
            Button("Copy Command") { OpenViewsClipboard.copy("swift build") }
        }
        guard let f = h.textFrame("Copy Command") else { Issue.record("button"); return }
        h.click(CGPoint(x: f.midX, y: f.midY), at: 1)
        #expect(h.backend.clipboard.text == "swift build")
        #expect(OpenViewsClipboard.string == "swift build" && OpenViewsClipboard.hasString)
        OpenViewsClipboard.string = "other"
        #expect(h.backend.clipboard.text == "other")
    }

    struct FieldWithShortcut: View {
        @State var text = "ab"
        var body: some View {
            VStack {
                TextField("Name", text: $text)
                Button("Deactivate") { CommandLog.shared.add("deactivate") }.keyboardShortcut("y")
            }
        }
    }

    struct FieldAlone: View {
        @State var text = "ab"
        var body: some View { TextField("Name", text: $text) }
    }

    @Test func ctrlYGoesToTheAppsShortcutAndCtrlShiftZStillRedoes() {
        let h = CommandsHarness { FieldWithShortcut() }
        h.key(.tab, at: 1)
        guard let field = h.main.services.focus.focusedClient as? TextFieldState else { Issue.record("field"); return }
        h.key(.end, at: 1.1)
        h.type("c", at: 1.2)
        #expect(field.model.text == "abc")
        h.key(.character("z"), [.control], at: 1.5)
        #expect(field.model.text == "ab")
        h.key(.character("y"), [.control], at: 1.7)
        #expect(CommandLog.shared.entries == ["deactivate"])
        #expect(field.model.text == "ab")
        h.key(.character("z"), [.control, .shift], at: 1.9)
        #expect(field.model.text == "abc")
    }

    @Test func ctrlYRedoesWhenNothingElseTakesIt() {
        let h = CommandsHarness(menuBar: false) { FieldAlone() }
        h.key(.tab, at: 1)
        guard let field = h.main.services.focus.focusedClient as? TextFieldState else { Issue.record("field"); return }
        h.key(.end, at: 1.1)
        h.type("c", at: 1.2)
        h.key(.character("z"), [.control], at: 1.5)
        h.key(.character("y"), [.control], at: 1.7)
        #expect(field.model.text == "abc")
    }

    @Test func placementOpensUpwardOrMovesInside() {
        let bounds = CGSize(width: 800, height: 500)
        let size = CGSize(width: 180, height: 140)
        let button = CGRect(x: 20, y: 100, width: 30, height: 20)
        #expect(PopupPlacement.origin(CGPoint(x: 20, y: 124), size: size, anchor: button, bounds: bounds) == CGPoint(x: 20, y: 124))
        let low = CGRect(x: 20, y: 470, width: 30, height: 20)
        #expect(PopupPlacement.origin(CGPoint(x: 20, y: 494), size: size, anchor: low, bounds: bounds) == CGPoint(x: 20, y: 470 - 4 - 140))
        let right = CGRect(x: 760, y: 100, width: 30, height: 20)
        #expect(PopupPlacement.origin(CGPoint(x: 760, y: 124), size: size, anchor: right, bounds: bounds).x == CGFloat(800 - 180))
        let tall = CGSize(width: 180, height: 480)
        #expect(PopupPlacement.origin(CGPoint(x: 20, y: 124), size: tall, anchor: button, bounds: bounds).y == CGFloat(20))
        let row = CGRect(x: 600, y: 300, width: 180, height: 26)
        let sub = PopupPlacement.origin(CGPoint(x: 778, y: 295), size: size, anchor: row, bounds: bounds)
        #expect(sub.x == CGFloat(600 - 180 + 2) && sub.y == 295)
        let point = CGPoint(x: 300, y: 450)
        #expect(PopupPlacement.origin(point, size: size, anchor: CGRect(origin: point, size: .zero), bounds: bounds).y == CGFloat(450 - 140))
    }

    struct BottomMenu: View {
        var body: some View {
            VStack(spacing: 0) {
                Spacer()
                HStack {
                    Menu("Add") {
                        ForEach(0..<6) { i in Button("Item \(i)") {} }
                    }
                    .fixedSize()
                    Spacer()
                }
            }
        }
    }

    @Test func aMenuAtTheBottomEdgeOpensAboveItsButton() {
        let h = CommandsHarness(menuBar: false) { BottomMenu() }
        guard let f = h.textFrame("Add") else { Issue.record("menu"); return }
        h.click(CGPoint(x: f.midX, y: f.midY), at: 1)
        guard let p = h.popups.first else { Issue.record("no pop-up"); return }
        #expect(p.popupOrigin.y + p.size.height <= f.minY + 0.5)
        #expect(p.popupOrigin.y >= 0)
        #expect(h.openItems.contains("Item 5"))
    }

    @Test func preferredColorSchemeColorsTheWholeWindowAndItsMenus() {
        let h = CommandsHarness { Text("Body").preferredColorScheme(.dark) }
        h.run(until: 1)
        #expect(h.main.graph.environment.colorScheme == .dark)
        var barScheme: ColorScheme?
        h.main.graph.root?.forEachNode { n in
            if barScheme == nil, String(describing: type(of: n.view)) == "MenuBarView" { barScheme = n.environment.colorScheme }
        }
        #expect(barScheme == .dark)
        h.openMenu("File", at: 1.2)
        #expect(h.popups.first?.graph.environment.colorScheme == .dark)
    }

    struct Switchable: View {
        @State var dark = true
        var body: some View {
            Button("Switch") { dark.toggle() }.preferredColorScheme(dark ? .dark : nil)
        }
    }

    @Test func clearingThePreferenceReturnsToTheDesktopsScheme() {
        let h = CommandsHarness { Switchable() }
        h.run(until: 1)
        #expect(h.main.graph.environment.colorScheme == .dark)
        guard let f = h.textFrame("Switch") else { Issue.record("button"); return }
        h.click(CGPoint(x: f.midX, y: f.midY), at: 1.2)
        h.run(until: 1.5)
        #expect(h.main.graph.environment.colorScheme == .light)
        #expect(barScheme(h) == .light)
        h.click(CGPoint(x: f.midX, y: f.midY), at: 1.8)
        h.run(until: 2.1)
        #expect(barScheme(h) == .dark)
        #expect(barTitleScheme(h) == .dark)
    }

    func barScheme(_ h: CommandsHarness) -> ColorScheme? {
        var out: ColorScheme?
        h.main.graph.root?.forEachNode { n in
            if out == nil, String(describing: type(of: n.view)) == "MenuBarView" { out = n.environment.colorScheme }
        }
        return out
    }

    func barTitleScheme(_ h: CommandsHarness) -> ColorScheme? {
        var out: ColorScheme?
        h.main.graph.root?.forEachNode { n in
            if out == nil, let t = n.view as? MenuBarTitle { _ = t; out = n.environment.colorScheme }
        }
        return out
    }

    enum Size: String, CaseIterable { case small = "Small", large = "Large" }

    struct ColumnsForm: View {
        @State var size = Size.small
        @State var on = true
        @State var width = 4
        var body: some View {
            Form {
                Section("Navigation and Files") {
                    Stepper("Tab width: \(width) spaces", value: $width)
                    Picker("Navigator size:", selection: $size) {
                        ForEach(Size.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    Toggle("Automatically unlock files", isOn: $on).toggleStyle(.checkbox)
                    LabeledContent("Settings file:") { Text("Export") }
                }
            }
            .formStyle(.columns)
        }
    }

    @Test func columnsFormPutsLabelsInARightAlignedColumn() {
        let h = CommandsHarness(menuBar: false) { ColumnsForm() }
        guard let heading = h.textFrame("Navigation and Files"), let label = h.textFrame("Navigator size:"),
              let choice = h.textFrame("Small"), let check = h.textFrame("Automatically unlock files"),
              let other = h.textFrame("Settings file:"), let value = h.textFrame("Export") else {
            Issue.record("rows")
            return
        }
        let column = ColumnsFormMetrics.sides + ColumnsFormMetrics.labelColumn
        #expect(abs(heading.minX - ColumnsFormMetrics.sides) < 0.5 && abs(heading.minY - ColumnsFormMetrics.top) < 3)
        #expect(abs(label.maxX - column) < 1 && abs(other.maxX - column) < 1)
        #expect(choice.minX > column + 8 && choice.minX < column + 8 + 12)
        #expect(abs(value.minX - (column + 8)) < 1)
        #expect(check.minX > column + 8 + 18)
        let stepper = h.frame { $0 is StepperControl }
        #expect(stepper.map { abs($0.width - StepperControl.compactSize.width) < 0.5 && abs($0.minX - (column + 8)) < 1 } == true)
        let first = h.textFrame("Tab width: 4 spaces")
        #expect(first.map { $0.minY - heading.maxY > 8 && $0.minY - heading.maxY < 16 } == true)
    }

    @Test func theSymbolNavigatorsSymbolIsDrawn() {
        let a = SymbolArtwork.all["list.bullet.indent"]
        #expect(a != nil && a?.operations.isEmpty == false)
    }
}
