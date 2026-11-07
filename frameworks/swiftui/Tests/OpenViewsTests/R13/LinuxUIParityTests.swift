import Foundation
import OVRender
import OVText
import Testing
#if OPENVIEWS_RENAMED
@testable import OpenViewsCore
@testable import OpenViews
#else
@testable import SwiftUICore
@testable import SwiftUI
#endif

@Suite("LINUX-UI-PARITY: toolkit")
struct LinuxUIParityToolkitTests {
    @Test func desktopTextStylesUseTheDesktopSizes() {
        let desktop = Font.Context(desktopTextStyles: true), phone = Font.Context()
        let expected: [(Font, CGFloat)] = [(.largeTitle, 26), (.title, 22), (.title2, 17), (.title3, 15), (.headline, 13), (.body, 13),
                                           (.callout, 12), (.subheadline, 11), (.footnote, 10), (.caption, 10), (.caption2, 10)]
        for (font, size) in expected {
            #expect(font.resolve(in: desktop).pointSize == size)
        }
        #expect(Font.headline.resolve(in: desktop).weight == .bold)
        #expect(Font.body.resolve(in: phone).pointSize == 17 && Font.headline.resolve(in: phone).weight == .semibold)
        #expect(Font.system(size: 12).resolve(in: desktop).pointSize == 12)
        #expect(Font.custom("X", size: 20, relativeTo: .body).resolve(in: desktop).pointSize == 20)
        var env = EnvironmentValues()
        env._desktopTextStyles = true
        #expect(env.fontResolutionContext.desktopTextStyles)
    }

    @MainActor @Test func aFlexibleFramesIdealAnswersAnUnspecifiedProposal() {
        let wide = Color.red.frame(width: 300, height: 10)
        let node = ViewGraph.layoutNode(for: wide.frame(minWidth: 180, idealWidth: 290, maxWidth: 500))
        let engine = Fixture.engine
        #expect(engine.sizeThatFits(node, .unspecified).size.width == 290)
        #expect(engine.sizeThatFits(node, ProposedViewSize(width: 400, height: nil)).size.width == 400)
        let clamped = ViewGraph.layoutNode(for: Color.red.frame(minWidth: 180, idealWidth: 100, maxWidth: 500))
        #expect(engine.sizeThatFits(clamped, .unspecified).size.width == 180)
        let plain = ViewGraph.layoutNode(for: wide.frame(minWidth: 180, maxWidth: 500))
        #expect(engine.sizeThatFits(plain, .unspecified).size.width == 300)
    }

    @Test func interIsBundledAndCanBeTheUIFamily() throws {
        let c = FontCatalog()
        c.addBundledFonts()
        #expect(c.face(for: FontRequest())?.familyName == "Noto Sans")
        #expect(c.registeredFaces.first?.familyName.hasPrefix("Noto") == true)
        c.setFamilies(["Inter 24pt", "Noto Sans"], for: .default)
        let regular = try #require(c.face(for: FontRequest()))
        #expect(regular.familyName == "Inter 24pt" && regular.traits.weight == 400)
        let bold = try #require(c.face(for: FontRequest(traits: FontTraits(weight: 700))))
        #expect(bold.familyName == "Inter 24pt" && bold.traits.weight == 700)
        #expect(c.face(for: FontRequest(traits: FontTraits(weight: 500)))?.traits.weight == 500)
        let m = regular.lineMetrics(size: 13)
        #expect(abs(m.ascent + m.descent + m.leading - 15.73) < 0.05)
        #expect(c.face(for: FontRequest(design: .monospaced))?.familyName == "Noto Sans Mono")
    }

    @MainActor @Test func aDividerIsPaintedAndPaddedInMenus() {
        func leaf(_ n: LayoutNode) -> LayoutNode { n.behavior is DividerLeaf ? n : n.children.first.map(leaf) ?? n }
        let plain = ViewGraph.layoutNode(for: Divider())
        #expect(leaf(plain).draw != nil)
        let engine = Fixture.engine
        #expect(engine.sizeThatFits(plain, ProposedViewSize(width: 100, height: nil)).size.height < 1)
        let inMenu = ViewGraph.layoutNode(for: Divider().environment(\._inMenu, true))
        let s = engine.sizeThatFits(inMenu, ProposedViewSize(width: 100, height: nil)).size
        #expect(s.width == 100 && s.height > 8 && s.height < 9)
        #expect(leaf(inMenu).draw != nil)
    }

    @Test func theChromesSymbolsAreDrawn() {
        let names = ["text.bubble", "plus.bubble", "plus.rectangle.on.rectangle", "rectangle.righthalf.inset.filled",
                     "rectangle.split.2x1", "rectangle.bottomthird.inset.filled", "arrow.left.arrow.right", "arrow.triangle.branch",
                     "bookmark", "checkmark.diamond", "gauge.with.dots.needle.33percent", "tag", "clock", "shippingbox",
                     "desktopcomputer", "square.grid.2x2", "eye", "line.3.horizontal.decrease", "chevron.up.chevron.down",
                     "arrow.right.circle.fill", "c.square", "text.magnifyingglass", "app.dashed", "plusminus.circle",
                     "xmark.octagon", "checklist", "rectangle.on.rectangle"]
        for name in names {
            let art = SymbolArtwork.all[name]
            #expect(art != nil, "\(name)")
            #expect(art.map { !$0.operations.isEmpty } == true, "\(name)")
        }
    }
}
