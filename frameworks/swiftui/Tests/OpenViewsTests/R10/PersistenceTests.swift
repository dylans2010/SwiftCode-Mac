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
final class PersistLog {
    static let shared = PersistLog()
    var entries: [String] = []
    var defaults = UserDefaults(suiteName: "openviews.tests.r10")!
}

enum Theme: String { case plain, solar }

struct StorageView: View {
    @AppStorage("launchCount", store: PersistLog.shared.defaults) var launches = 0
    @AppStorage("name", store: PersistLog.shared.defaults) var name = "none"
    @AppStorage("theme", store: PersistLog.shared.defaults) var theme = Theme.plain
    @AppStorage("optional", store: PersistLog.shared.defaults) var optional: String?

    var body: some View {
        PersistLog.shared.entries.append("body \(launches) \(name) \(theme.rawValue) \(optional ?? "nil")")
        return Text("\(launches)")
            .onChange(of: name) { _, n in PersistLog.shared.entries.append("onChange \(n)") }
    }
}

struct SceneStorageView: View {
    @SceneStorage("tab") var tab = 0
    @SceneStorage("query") var query: String?
    var body: some View {
        PersistLog.shared.entries.append("scene \(tab) \(query ?? "nil")")
        return Text("tab \(tab)")
    }
}

struct SceneStorageHost: View {
    @State var show = true
    var body: some View {
        VStack {
            if show { SceneStorageView() }
            Button("Toggle") { show.toggle() }
        }
    }
}

struct PersistApp: App {
    var body: some Scene {
        WindowGroup { SceneStorageView() }
    }
}

@MainActor
@Suite("R10 persistence (T-PERSIST)")
struct PersistenceTests {
    func reset() {
        let d = PersistLog.shared.defaults
        for k in ["launchCount", "name", "theme", "optional"] { d.removeObject(forKey: k) }
        PersistLog.shared.entries = []
    }

    @Test func appStorageRoundTripAndExternalWrites() {
        reset()
        let h = Harness { StorageView() }
        #expect(PersistLog.shared.entries.last == "body 0 none plain nil")
        guard let node = h.window.graph.root else { return }
        var view: StorageView?
        node.forEachNode { n in if view == nil, let v = n.view as? StorageView { view = v } }
        view?.launches += 1
        h.run(until: 1)
        #expect(PersistLog.shared.defaults.integer(forKey: "launchCount") == 1)
        #expect(PersistLog.shared.entries.last == "body 1 none plain nil")
        PersistLog.shared.entries = []
        PersistLog.shared.defaults.set("Ada", forKey: "name")
        PersistLog.shared.defaults.set("solar", forKey: "theme")
        h.run(until: 1.5)
        #expect(PersistLog.shared.entries.contains("body 1 Ada solar nil"))
        #expect(PersistLog.shared.entries.contains("onChange Ada"))
        view?.optional = "x"
        h.run(until: 2)
        #expect(PersistLog.shared.defaults.string(forKey: "optional") == "x")
        view?.optional = nil
        h.run(until: 2.5)
        #expect(PersistLog.shared.defaults.object(forKey: "optional") == nil)
        #expect(PersistLog.shared.entries.last == "body 1 Ada solar nil")
    }

    @Test func didChangeNotificationAloneIsEnough() {
        reset()
        let h = Harness { StorageView() }
        PersistLog.shared.entries = []
        PersistLog.shared.defaults.set(7, forKey: "launchCount")
        NotificationCenter.default.post(name: UserDefaults.didChangeNotification, object: PersistLog.shared.defaults)
        h.run(until: 1)
        #expect(PersistLog.shared.entries.last?.hasPrefix("body 7") == true)
    }

    @Test func sceneStorageBelongsToTheWindowAndSurvivesRecreation() {
        PersistLog.shared.entries = []
        let h = Harness { SceneStorageHost() }
        var v: SceneStorageView?
        h.window.graph.root?.forEachNode { n in if v == nil, let x = n.view as? SceneStorageView { v = x } }
        v?.tab = 3
        v?.query = "swift"
        h.run(until: 1)
        #expect(PersistLog.shared.entries.last == "scene 3 swift")
        #expect(h.window.sceneStorage.value(forKey: "tab") as? Int == 3)
        if let f = h.frame(where: { ($0 as? Text)?.plainString == "Toggle" }) { h.tap(f.center, at: 1.5) }
        if let f = h.frame(where: { ($0 as? Text)?.plainString == "Toggle" }) { h.tap(f.center, at: 2) }
        #expect(PersistLog.shared.entries.last == "scene 3 swift")
        h.host.openWindow(id: nil)
        h.run(until: 2.5)
        #expect(h.host.windows.count == 2)
        #expect(h.host.windows[1].sceneStorage.value(forKey: "tab") == nil)
    }

    @Test func scenesAreRestoredOnlyAfterAnEndThatWasNotAUserQuit() {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("ov-r10-scenes-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        func launch() -> (HeadlessBackend, AppHost) {
            let b = HeadlessBackend(scale: 1)
            let host = AppHost(PersistApp.self, backend: b)
            host.makePresenter = { _ in nil }
            host.sceneArchive = SceneStorageArchive(directory: dir)
            host.launch()
            host.run(until: 0.5)
            return (b, host)
        }
        func set(_ host: AppHost, _ tab: Int) {
            var v: SceneStorageView?
            host.windows[0].graph.root?.forEachNode { n in if v == nil, let x = n.view as? SceneStorageView { v = x } }
            v?.tab = tab
            host.run(until: host.backend.now + 0.2)
        }
        var (b, host) = launch()
        set(host, 5)
        if let id = host.windows.first?.platform.id { b.post(.window(id, .minimized)) }
        host.run(until: 1.5)
        #expect(host.appPhase == .background)
        (b, host) = launch()
        #expect(host.windows[0].sceneStorage.value(forKey: "tab") as? Int == 5)
        b.post(.quit)
        host.run(until: 1)
        #expect(host.isFinished)
        (b, host) = launch()
        #expect(host.windows[0].sceneStorage.value(forKey: "tab") == nil)
        _ = b
    }
}
