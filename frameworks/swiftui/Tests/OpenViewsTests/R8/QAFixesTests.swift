import Foundation
import OVPlatform
import Testing
#if OPENVIEWS_RENAMED
@testable import OpenViewsCore
@testable import OpenViews
#else
@testable import SwiftUICore
@testable import SwiftUI
#endif

@MainActor
final class CountingPresenter: FramePresenter {
    var presented = 0
    func present(_ window: WindowHost) { presented += 1 }
    func surfaceDidResize() {}
    func invalidate() {}
    func readback() -> PixelBuffer? { nil }
}

struct SpinningBox: View {
    @State var turned = false
    @State var moved = false
    var body: some View {
        VStack {
            Color.red.frame(width: 20, height: 20)
                .rotationEffect(.degrees(turned ? 360 : 0))
                .onAppear {
                    withAnimation(.linear(duration: 1).repeatForever(autoreverses: false)) { turned = true }
                }
            Color.blue.frame(width: 20, height: 20)
                .offset(x: moved ? 100 : 0)
                .onTapGesture { withAnimation(.linear(duration: 0.5)) { moved = true } }
        }
    }
}

@MainActor
@Suite("R8 QA fixes")
struct QAFixesTests {
    @Test func animationFramesArePresented() {
        let presenter = CountingPresenter()
        let backend = HeadlessBackend(scale: 1)
        HarnessApp.content = { AnyView(SpinningBox()) }
        HarnessApp.size = CGSize(width: 300, height: 300)
        let host = AppHost(HarnessApp.self, backend: backend)
        host.makePresenter = { _ in presenter }
        host.launch()
        host.run(until: 0.5)
        let before = presenter.presented
        host.run(until: 1.5)
        let perSecond = presenter.presented - before
        #expect(perSecond >= 58 && perSecond <= 62)
    }

    @Test func strokesAndBordersDoNotBlockTaps() {
        let log = EventLog()
        let h = Harness {
            VStack(spacing: 0) {
                Color.green.frame(width: 100, height: 40).onTapGesture { log.add("row 1") }
                Color.yellow.frame(width: 100, height: 40).onTapGesture { log.add("row 2") }
            }
            .border(Color.gray)
            .overlay { Rectangle().stroke(Color.black, lineWidth: 2) }
        }
        guard let a = h.frame(of: .green), let b = h.frame(of: .yellow) else { Issue.record("rows"); return }
        h.tap(a.center, at: 1.0)
        h.tap(b.center, at: 1.5)
        #expect(log.entries == ["row 1", "row 2"])
        let log2 = EventLog()
        let h2 = Harness {
            Circle().stroke(Color.black).frame(width: 50, height: 50)
                .contentShape(Rectangle()).onTapGesture { log2.add("ring") }
        }
        h2.tap(CGPoint(x: 200, y: 200), at: 1.0)
        #expect(log2.entries == ["ring"])
    }

    @Test func duplicateClicksAreDropped() {
        var f = MouseButtonFilter()
        do { let ok = f.accept(button: 1, down: true, time: 1.0, x: 10, y: 10); #expect(ok) }
        do { let ok = f.accept(button: 1, down: false, time: 1.05, x: 10, y: 10); #expect(ok) }
        do { let ok = f.accept(button: 1, down: true, time: 1.0502, x: 10, y: 10); #expect(!ok) }
        do { let ok = f.accept(button: 1, down: false, time: 1.0504, x: 10, y: 10); #expect(!ok) }
        do { let ok = f.accept(button: 1, down: true, time: 1.15, x: 10, y: 10); #expect(ok) }
        do { let ok = f.accept(button: 1, down: false, time: 1.2, x: 10, y: 10); #expect(ok) }
        do { let ok = f.accept(button: 3, down: true, time: 2, x: 0, y: 0); #expect(ok) }
        do { let ok = f.accept(button: 3, down: true, time: 2.001, x: 0, y: 0); #expect(!ok) }
        do { let ok = f.accept(button: 2, down: false, time: 3, x: 0, y: 0); #expect(ok) }
    }

    @Test func clicksReadLateAreNotTakenForDuplicates() {
        var f = MouseButtonFilter()
        for (i, down) in [true, false, true, false].enumerated() {
            let ok = f.accept(button: 1, down: down, time: 5 + Double(i) * 0.0001, x: 10, y: 10, timeIsReliable: false)
            #expect(ok)
        }
    }
}
