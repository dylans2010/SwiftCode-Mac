import Foundation
import OVPlatform
#if OPENVIEWS_RENAMED
import OpenViewsCore
#else
import SwiftUICore
#endif

@MainActor
package final class HostClock: AnimationTimeSource {
    unowned let backend: any PlatformBackend
    var frameTime: TimeInterval?
    init(backend: any PlatformBackend) { self.backend = backend }
    package var now: TimeInterval { frameTime ?? backend.now }
}

struct AppRootView<A: App>: View, PrimitiveView {
    let app: A
    let host: AppHost
    typealias Body = Never

    private func evaluate(_ node: ViewNode, inputsChanged: Bool, _ transaction: Transaction) {
        let app = app, host = host
        node.updateTracked(inputs: app, inputsChanged: inputsChanged, transaction: transaction) {
            host.log?("App.body")
            host.receive(SceneCollector.collect(app.body))
            return EmptyView()
        }
    }

    func _makeChildren(node: ViewNode, old: AppRootView?, transaction: Transaction) {
        evaluate(node, inputsChanged: old == nil, transaction)
    }

    func _refresh(node: ViewNode, environmentChanged: Bool, transaction: Transaction) {
        evaluate(node, inputsChanged: false, transaction)
    }
}

extension AppRootView: GraphInputComparable {
    nonisolated func _isGraphInputEqual(to other: Any) -> Bool { true }
}

struct WindowRootView: View, PrimitiveView {
    let content: any View
    var overlays: OverlayPopupLayer?
    typealias Body = Never

    var presentations: PresentationCenter?
    var chrome: WindowChromeConfiguration?
    var commands: [any Commands] = []
    var tooltips: TooltipCenter?

    func _makeChildren(node: ViewNode, old: WindowRootView?, transaction: Transaction) {
        var items: [(AnyHashable, any View)] = [(AnyHashable(0), content)]
        if let chrome {
            items.append((AnyHashable("top"), WindowTopChrome(configuration: chrome)))
            items.append((AnyHashable("bottom"), WindowBottomChrome()))
            if chrome.menuBar || !commands.isEmpty {
                items.append((AnyHashable("commands"), CommandsHostView(commands: commands, model: chrome.commands, actions: chrome.actions)))
            }
        }
        if let p = presentations, !p.isEmpty {
            items.append((AnyHashable(2), PresentationLayer(center: p, entries: p.entries)))
        }
        if let overlays { items.append((AnyHashable(1), overlays)) }
        if let tooltips { items.append((AnyHashable("tooltip"), TooltipLayer(center: tooltips))) }
        node.reconcileChildren(items, transaction: transaction)
    }

    func _lower(node: ViewNode) -> [LayoutNode] {
        var base: LayoutNode?
        var top: [LayoutNode] = [], bottom: [LayoutNode] = []
        var layers: [LayoutNode] = []
        for (key, c) in zip(node.childKeys, node.children) {
            switch key {
            case AnyHashable(0):
                let content = c.lower()
                base = content.count == 1 ? content[0] : (content.isEmpty ? .empty() : .vstack(content))
            case AnyHashable("top"): top = c.lower()
            case AnyHashable("bottom"): bottom = c.lower()
            case AnyHashable("commands"): break
            default:
                if let layer = c.lower().first { layers.append(layer) }
            }
        }
        var root = base ?? .empty()
        if !top.isEmpty || !bottom.isEmpty {
            root = .vstack(spacing: 0, top + [root.frame(maxWidth: .infinity, maxHeight: .infinity)] + bottom)
        }
        for l in layers { root = root.overlay(l, alignment: .center) }
        return [root]
    }
}

struct WindowTopChrome: View {
    let configuration: WindowChromeConfiguration
    @Environment(\._windowServices) private var services
    var body: some View {
        if configuration.menuBar {
            MenuBarView(model: configuration.commands, actions: configuration.actions)
        }
        if let toolbar = services?.toolbar {
            WindowToolbarView(model: toolbar)
        }
    }
}

struct WindowBottomChrome: View {
    @Environment(\._windowServices) private var services
    var body: some View {
        if let toolbar = services?.toolbar {
            WindowToolbarView(model: toolbar, bottom: true)
        }
    }
}

@MainActor
package final class WindowHost {
    package let platform: any PlatformWindow
    package let graph: ViewGraph
    package let gestures: GestureEngine
    package let services: WindowServices
    package let sceneIndex: Int
    package let sceneID: String?
    package private(set) var phase: ScenePhase = .background
    package var isMinimized = false
    package var presenter: (any FramePresenter)?
    package private(set) var presentedFrames = 0
    private var needsDisplay = true
    private var pressedPointers: Set<Int> = []
    private var baseEnvironment: EnvironmentValues
    private var content: any View
    package internal(set) var isPopup = false
    package internal(set) weak var popupOwner: WindowHost?
    package internal(set) var popupOrigin = CGPoint.zero
    var popupHandle: PopupHandle?
    var popupOnDismiss: (() -> Void)?
    package internal(set) var overlayPopups: [OverlayPopup] = [] { didSet { refreshRoot() } }
    var chrome: WindowChromeConfiguration? { didSet { refreshRoot() } }
    var commands: [any Commands] = []
    package let focusedValues: FocusedValuesCenter
    package let sceneStorage: SceneStorageStore
    package private(set) var preferredColorScheme: ColorScheme?

    init(platform: any PlatformWindow, sceneIndex: Int, sceneID: String?, content: any View,
         environment: EnvironmentValues, clock: HostClock, presenter: (any FramePresenter)?,
         chrome: WindowChromeConfiguration? = nil, commands: [any Commands] = [],
         sceneStorage: SceneStorageStore? = nil) {
        self.platform = platform
        self.sceneIndex = sceneIndex
        self.sceneID = sceneID
        services = WindowServices()
        baseEnvironment = environment
        self.content = content
        self.chrome = chrome
        self.commands = commands
        let focused = environment._focusedValues ?? FocusedValuesCenter()
        focusedValues = focused
        self.sceneStorage = sceneStorage ?? environment._sceneStorage ?? SceneStorageStore()
        var env = environment
        env._windowServices = services
        env._focusedValues = focused
        env._sceneStorage = self.sceneStorage
        env.displayScale = platform.scale
        env.scenePhase = .background
        var symbols = OpenSymbolProvider()
        symbols.displayScale = platform.scale
        graph = ViewGraph(rootView: WindowRootView(content: content, presentations: services.presentations, chrome: chrome,
                                                   commands: commands, tooltips: services.tooltips), environment: env,
                          layout: HostLayout(.window(platform.size, safeAreaInsets: EdgeInsets()), symbols: symbols),
                          timeSource: clock)
        gestures = GestureEngine(graph: graph)
        self.presenter = presenter
        services.presentations.onChange = { [weak self] in self?.refreshRoot() }
        services.requestDisplay = { [weak self] in self?.needsDisplay = true }
        services.focus.onTextClientChanged = { [weak self] client in
            guard let self else { return }
            if let client {
                textInputArea = client.caretRect
                platform.startTextInput(caretRect: client.caretRect)
            } else {
                textInputArea = nil
                platform.stopTextInput()
            }
        }
    }

    package private(set) var textInputArea: CGRect?

    func syncTextInputArea() {
        guard let client = services.focus.focusedClient, platform.isTextInputActive else { return }
        let r = client.caretRect
        guard r != textInputArea else { return }
        textInputArea = r
        platform.startTextInput(caretRect: r)
    }

    package var size: CGSize { platform.size }

    private func rootView() -> WindowRootView {
        WindowRootView(content: content, overlays: overlayPopups.isEmpty ? nil
                       : OverlayPopupLayer(items: overlayPopups, windowSize: platform.size),
                       presentations: services.presentations, chrome: chrome, commands: commands,
                       tooltips: isPopup ? nil : services.tooltips)
    }

    private func refreshRoot() { graph.setRootView(rootView()) }

    func setContent(_ content: any View, environment: EnvironmentValues, commands: [any Commands]? = nil) {
        self.content = content
        if let commands { self.commands = commands }
        graph.setRootView(rootView())
        baseEnvironment = environment
        graph.updateEnvironment { env in
            let phase = env.scenePhase, scale = env.displayScale
            env = environment
            env._windowServices = self.services
            env._focusedValues = self.focusedValues
            env._sceneStorage = self.sceneStorage
            env.scenePhase = phase
            env.displayScale = scale
            if let p = self.preferredColorScheme { env.colorScheme = p }
        }
    }

    func applySettings(_ apply: @escaping (inout EnvironmentValues) -> Void) {
        apply(&baseEnvironment)
        var main: WindowHost = self
        while main.isPopup, let o = main.popupOwner { main = o }
        let preferred = main.preferredColorScheme
        graph.updateEnvironment { env in
            apply(&env)
            if let preferred { env.colorScheme = preferred }
        }
    }

    @discardableResult
    func applyPreferredColorScheme() -> Bool {
        let wanted = requestedColorScheme
        guard wanted != preferredColorScheme else { return false }
        preferredColorScheme = wanted
        let scheme = wanted ?? baseEnvironment.colorScheme
        graph.updateEnvironment { $0.colorScheme = scheme }
        needsDisplay = true
        return true
    }

    func setPhase(_ p: ScenePhase) {
        guard p != phase else { return }
        phase = p
        graph.updateEnvironment { $0.scenePhase = p }
    }

    package func update() {
        graph.update()
        if applyPreferredColorScheme() { graph.update() }
        services.focus.sync()
        if !isPopup { focusedValues.recompute(focused: services.focus.focusedNode) }
        if graph.needsUpdate {
            graph.update()
            services.focus.sync()
            if !isPopup { focusedValues.recompute(focused: services.focus.focusedNode) }
        }
    }

    var needsFrame: Bool { graph.needsUpdate || graph.isAnimating || needsDisplay }
    var timerDeadline: TimeInterval? {
        [gestures.deadline, services.nextTimerDeadline].compactMap { $0 }.min()
    }

    func renderFrame() {
        let began = OpenViewsAutomation.frameDurations == nil || isPopup ? nil : DispatchTime.now().uptimeNanoseconds
        defer {
            if let began { OpenViewsAutomation.frameDurations?.append(Double(DispatchTime.now().uptimeNanoseconds - began) / 1e9) }
        }
        let passes = graph.passCount
        let animating = graph.isAnimating
        graph.renderFrame()
        if applyPreferredColorScheme() { graph.update() }
        services.focus.sync()
        if !isPopup { focusedValues.recompute(focused: services.focus.focusedNode) }
        if graph.needsUpdate { update() }
        if animating || passes != graph.passCount || needsDisplay {
            needsDisplay = false
            presentedFrames += 1
            presenter?.present(self)
        }
        syncTextInputArea()
    }

    func teardown() {
        gestures.cancel()
        graph.setRootView(EmptyView())
        graph.update()
        presenter?.invalidate()
    }

    private func sample(_ p: PointerEvent) -> PointerSample {
        let phase: PointerSample.Phase
        switch p.phase {
        case .down: phase = .down
        case .moved: phase = .moved
        case .up: phase = .up
        case .cancelled: phase = .cancelled
        }
        return PointerSample(pointer: p.pointer, phase: phase, location: p.location, time: p.timestamp,
                             isTouch: p.kind == .touch)
    }

    func handlePointer(_ p: PointerEvent) {
        if p.kind == .mouse && p.button == 3 && p.phase == .down {
            services.pointerModifiers = p.modifiers
            gestures.pointer(sample(PointerEvent(window: p.window, phase: .moved, location: p.location, button: 0,
                                                 isPressed: false, timestamp: p.timestamp)), isPressed: false)
            openContextMenu(at: p.location)
            return
        }
        if p.kind == .mouse && p.button > 1 && p.phase != .moved {
            if pressedPointers.isEmpty {
                gestures.pointer(sample(PointerEvent(window: p.window, phase: .moved, location: p.location, button: 0,
                                                     isPressed: false, timestamp: p.timestamp)), isPressed: false)
            }
            return
        }
        trackContextPress(p)
        services.pointerModifiers = p.modifiers
        services.lastEventTime = p.timestamp
        if p.phase == .down { services.tooltips.dismiss() }
        if p.phase == .down && graph.needsUpdate { update() }
        switch p.phase {
        case .down: pressedPointers.insert(p.pointer)
        case .up, .cancelled: pressedPointers.remove(p.pointer)
        case .moved: break
        }
        gestures.pointer(sample(p), isPressed: !pressedPointers.isEmpty)
    }

    var onPopupKey: ((KeyEvent) -> Bool)?
    var onPopupFallbackKey: ((KeyEvent) -> Bool)?

    private var suppressNextText = false

    func handleKey(_ k: KeyEvent) {
        services.lastEventTime = k.timestamp
        if k.isDown { suppressNextText = false }
        if KeyPressDispatch.deliver(k, focused: services.focus.focusedNode) {
            if k.isDown, case .character = k.key, !k.modifiers.contains(.control), !k.modifiers.contains(.command) {
                suppressNextText = true
            } else if k.isDown, k.key == .space {
                suppressNextText = true
            }
            return
        }
        guard k.isDown else { return }
        services.tooltips.dismiss()
        if let client = services.focus.focusedClient, client.handleKey(k) { return }
        if let h = onPopupKey, h(k) { return }
        if let handler = services.focus.focusedKeyHandler, handler(k) { return }
        if let h = onPopupFallbackKey, h(k) { return }
        if k.key == .function(10) {
            if k.modifiers.contains(.shift) {
                if openContextMenuForFocus() { return }
            } else if let bar = services.menuBar, !k.modifiers.contains(.control), !k.modifiers.contains(.command) {
                bar.openFirst()
                return
            }
        }
        if services.shortcuts.perform(key: k.key, modifiers: k.modifiers) { return }
        if k.key == .tab {
            services.focus.focusNext(in: graph.root, reverse: k.modifiers.contains(.shift))
        } else if k.key == .escape, services.focus.focusedNode != nil {
            services.focus.focus(nil)
        }
    }

    func handleText(_ t: TextInputEvent) {
        if suppressNextText {
            suppressNextText = false
            return
        }
        services.focus.focusedClient?.insertText(t.text)
    }

    func handleEditing(_ e: TextEditingEvent) {
        services.focus.focusedClient?.setMarkedText(e.text, cursor: e.cursor)
    }

    func handleScroll(_ s: ScrollEvent) {
        if graph.needsUpdate { update() }
        gestures.scroll(delta: s.delta, at: s.location)
    }

    package var safeAreaInsets = EdgeInsets() {
        didSet { resized(to: platform.size) }
    }

    func resized(to size: CGSize) {
        graph.layout = HostLayout(.window(size, safeAreaInsets: safeAreaInsets), symbols: graph.layout?.symbols ?? StubSymbolProvider())
        presenter?.surfaceDidResize()
        needsDisplay = true
    }

    func scaleChanged(_ s: Double) {
        graph.updateEnvironment { $0.displayScale = s }
        presenter?.surfaceDidResize()
        needsDisplay = true
    }

    func exposed() { needsDisplay = true }
    func pointerLeft() { gestures.pointerLeft() }

    func deliver(_ url: URL) -> Bool {
        let handlers = services.urlHandlers
        for h in handlers { h.action(url) }
        return !handlers.isEmpty
    }
}

@MainActor
package final class AppHost: RunLoopClient {
    package let backend: any PlatformBackend
    package let runLoop: PlatformRunLoop
    package let clock: HostClock
    package private(set) var appGraph: ViewGraph?
    package private(set) var windows: [WindowHost] = []
    package private(set) var scenes: [SceneDescription] = []
    package private(set) var appPhase: ScenePhase = .background
    package var log: ((String) -> Void)?
    package var defaultWindowSize = CGSize(width: 800, height: 600)
    package var desktopTextInput: Bool
    package var makePresenter: (any PlatformWindow) -> (any FramePresenter)? = { CompositorPresenter(window: $0) }
    package var renderer = ProcessInfo.processInfo.environment["OV_RENDERER"]?.lowercased() ?? "auto"
    package private(set) var isFinished = false
    package var showsMenuBar: Bool
    package lazy var appName: String = {
        let env = ProcessInfo.processInfo.environment
        if let n = env["OV_APP_NAME"], !n.isEmpty { return n }
        if let n = Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String, !n.isEmpty { return n }
        return ProcessInfo.processInfo.processName
    }()
    package private(set) var quitByUser = false
    package var sceneArchive: SceneStorageArchive?
    package private(set) var activeWindowID: PlatformWindowID?
    package private(set) var windowFocusKnown = false
    package var accessibilityExport: AccessibilityExport?

    private var delegates: [any AppDelegateAdaptorProtocol] = []
    private var makeRoot: ((AppHost) -> any View)?
    private var previousObserverValues: [String: Any] = [:]
    private var pendingURLs: [URL] = []
    private var launched = false

    package init<A: App>(_ type: A.Type, backend: any PlatformBackend, urls: [URL] = []) {
        self.backend = backend
        clock = HostClock(backend: backend)
        runLoop = PlatformRunLoop(backend: backend)
        desktopTextInput = !(backend is HeadlessBackend)
        let menuBarSetting = ProcessInfo.processInfo.environment["OV_MENU_BAR"]
        showsMenuBar = menuBarSetting.map { $0 != "0" } ?? !(backend is HeadlessBackend)
        pendingURLs = urls
        makeRoot = { host in
            host.log?("App.init")
            let app = A()
            host.delegates = Mirror(reflecting: app).children.compactMap { $0.value as? any AppDelegateAdaptorProtocol }
            return AppRootView(app: app, host: host)
        }
    }

    package private(set) static weak var current: AppHost?
    package private(set) static weak var lastLaunched: AppHost?

    package static func runMain<A: App>(_ type: A.Type) {
        let backend = Platform.makeDefaultBackend()
        let urls = CommandLine.arguments.dropFirst().compactMap { a -> URL? in
            guard a.contains("://"), let u = URL(string: a) else { return nil }
            return u
        }
        let host = AppHost(type, backend: backend, urls: urls)
        current = host
        if ProcessInfo.processInfo.environment["OV_TRACE"] != nil {
            host.log = { FileHandle.standardError.write(Data("[ov] \($0)\n".utf8)) }
        }
        if !(backend is HeadlessBackend) { host.sceneArchive = SceneStorageArchive.forCurrentProcess() }
        host.launch()
        host.accessibilityExport = AccessibilityExport.start(host: host)
        if backend is HeadlessBackend && ProcessInfo.processInfo.environment["OV_PLATFORM"] != "headless" {
            FileHandle.standardError.write(Data("OpenViews: no display back end (libSDL3 or a display); ran headless\n".utf8))
            host.terminate()
        } else {
            host.run()
        }
        backend.shutdown()
    }

    private func environment(for sceneIndex: Int?) -> EnvironmentValues {
        var env = EnvironmentValues()
        env.scenePhase = appPhase
        env._defaultAutocapitalization = desktopTextInput ? .never : .sentences
        env._desktopChrome = desktopTextInput
        env._desktopTextStyles = desktopTextInput
        env.openWindow = OpenWindowAction { [weak self] id in self?.openWindow(id: id) }
        env.openSettings = OpenSettingsAction { [weak self] in self?.openSettings() }
        PlatformEnvironment.apply(backend.settings, to: &env)
        if let i = sceneIndex, scenes.indices.contains(i) {
            for t in scenes[i].environment { t(&env) }
        }
        return env
    }

    private func deliver(_ event: AppLifecycleEvent) {
        if case .openURLs = event {} else { log?("delegate \(event)") }
        for d in delegates { d._deliver(event) }
    }

    package func launch() {
        guard !launched, let makeRoot else { return }
        launched = true
        Self.lastLaunched = self
        OpenURLAction.systemOpener = { [weak self] url in self?.backend.openExternally(url) ?? false }
        UIApplication.shared.applicationState = .background
        let root = makeRoot(self)
        deliver(.didFinishLaunching)
        let graph = ViewGraph(rootView: root, environment: environment(for: nil))
        appGraph = graph
        graph.update()
        if let first = scenes.indices.first(where: { scenes[$0].kind != .settings }) { openWindow(sceneIndex: first) }
        setAppPhase(.inactive)
        setAppPhase(.active)
        let urls = pendingURLs
        pendingURLs = []
        for u in urls { openURL(u) }
    }

    package func setAppPhase(_ phase: ScenePhase) {
        guard phase != appPhase else { return }
        let old = appPhase
        if old == .active { deliver(.willResignActive) }
        appPhase = phase
        UIApplication.shared.applicationState = UIApplication.State(phase)
        log?("App scenePhase \(phase)")
        appGraph?.updateEnvironment { $0.scenePhase = phase }
        appGraph?.update()
        if old == .background { deliver(.willEnterForeground) }
        for w in windows {
            w.setPhase(phase)
            w.update()
        }
        if phase == .background {
            for w in windows where !w.isPopup { sceneArchive?.save(w.sceneStorage) }
            deliver(.didEnterBackground)
        }
        if phase == .active { deliver(.didBecomeActive) }
    }

    func receive(_ new: [SceneDescription]) {
        scenes = new
        let commands = allCommands
        for w in windows where !w.isPopup && scenes.indices.contains(w.sceneIndex) {
            w.setContent(scenes[w.sceneIndex].content(), environment: windowEnvironment(w.sceneIndex, window: w),
                         commands: commands)
        }
        for (i, s) in scenes.enumerated() {
            for (j, o) in s.changeObservers.enumerated() {
                let key = "\(i).\(j)"
                if let old = previousObserverValues[key] {
                    if !o.equal(old, o.value) { o.action(old, o.value) }
                } else if o.initial {
                    o.action(o.value, o.value)
                }
                previousObserverValues[key] = o.value
            }
        }
    }

    private func windowEnvironment(_ sceneIndex: Int, window: WindowHost? = nil, box: WeakWindowBox? = nil) -> EnvironmentValues {
        var env = environment(for: sceneIndex)
        let b = box ?? WeakWindowBox()
        if let window { b.window = window }
        env.dismissWindow = DismissWindowAction { [weak self] id in
            guard let self else { return }
            if id == nil, let w = b.window { self.closeWindow(w) } else { self.dismissWindow(id: id) }
        }
        if let window { env._appCommands = window.chrome?.actions }
        return env
    }

    package var allCommands: [any Commands] { scenes.flatMap(\.commands) }

    private func commandActions(_ box: WeakWindowBox) -> AppCommandActions {
        let a = AppCommandActions()
        a.appName = appName
        a.quit = { [weak self] in self?.quit() }
        let removed = { (s: SceneDescription) in s.commands.contains { $0 is RemoveDefaultCommands } }
        if let g = scenes.firstIndex(where: { $0.kind == .windowGroup && !removed($0) }) {
            a.newWindow = { [weak self] in self?.openWindow(sceneIndex: g, activate: true) }
        }
        a.closeWindow = { [weak self] in if let w = box.window { self?.closeWindow(w) } }
        if scenes.contains(where: { $0.kind == .settings }) { a.openSettings = { [weak self] in self?.openSettings() } }
        a.minimize = { box.window?.platform.minimize() }
        a.about = { [weak self] in self?.log?("about \(self?.appName ?? "")") }
        a.windows = { [weak self] in
            guard let self else { return [] }
            return self.windows.filter { !$0.isPopup }.map { w in
                (title: self.scenes.indices.contains(w.sceneIndex) ? self.scenes[w.sceneIndex].title : "",
                 isCurrent: w === box.window, activate: { @MainActor in w.platform.activate() })
            }
        }
        a.singleWindows = scenes.enumerated().filter { $0.element.kind == .window && !removed($0.element) }.map { i, s in
            (title: s.title.isEmpty ? (s.id ?? "Window") : s.title,
             open: { @MainActor [weak self] in self?.openWindow(sceneIndex: i, activate: true) })
        }
        return a
    }

    package func openWindow(id: String?) {
        let index = id.flatMap { i in scenes.firstIndex { $0.id == i } } ?? scenes.firstIndex { $0.kind == .windowGroup }
        guard let index else { return }
        if scenes[index].kind != .windowGroup, windows.contains(where: { $0.sceneIndex == index && !$0.isPopup }) { return }
        openWindow(sceneIndex: index)
        windows.last?.setPhase(appPhase)
        windows.last?.update()
    }

    @discardableResult
    package func openWindow(sceneIndex: Int, activate: Bool) -> WindowHost? {
        let scene = scenes[sceneIndex]
        if scene.kind != .windowGroup, let existing = windows.first(where: { !$0.isPopup && $0.sceneIndex == sceneIndex }) {
            existing.platform.activate()
            return existing
        }
        let w = openWindow(sceneIndex: sceneIndex)
        if activate {
            w?.setPhase(appPhase)
            w?.update()
        }
        return w
    }

    @discardableResult
    package func openWindow(sceneIndex: Int) -> WindowHost? {
        let scene = scenes[sceneIndex]
        let box = WeakWindowBox()
        let isSettings = scene.kind == .settings
        var env = windowEnvironment(sceneIndex, box: box)
        let actions = commandActions(box)
        env._appCommands = actions
        var size = scene.defaultSize ?? defaultWindowSize
        if isSettings && scene.defaultSize == nil {
            size = idealSize(of: scene.content(), environment: env, minimum: CGSize(width: 360, height: 200))
        }
        var config = WindowConfiguration(title: isSettings && scene.title.isEmpty ? "Settings" : scene.title, size: size,
                                         resizable: isSettings ? false : scene.resizable)
        guard let (pw, presenter) = makeWindow(&config) else {
            log?("window creation failed")
            return nil
        }
        log?("scene connect \(scene.id ?? "#\(sceneIndex)")")
        let chrome = WindowChromeConfiguration(menuBar: showsMenuBar && !isSettings, commands: CommandsModel(), actions: actions)
        let storageKey = "\(scene.id ?? "#\(sceneIndex)").\(windows.filter { $0.sceneIndex == sceneIndex && !$0.isPopup }.count)"
        let storage = sceneArchive?.restore(key: storageKey) ?? SceneStorageStore()
        storage.archiveKey = storageKey
        env._focusedValues = nil
        let w = WindowHost(platform: pw, sceneIndex: sceneIndex, sceneID: scene.id, content: scene.content(),
                           environment: env, clock: clock, presenter: presenter, chrome: chrome,
                           commands: isSettings ? [] : allCommands, sceneStorage: storage)
        box.window = w
        w.services.clipboard = backend.clipboard
        w.services.popups = WindowPopupPresenter(host: self, window: w)
        windows.append(w)
        return w
    }

    private func idealSize(of content: any View, environment env: EnvironmentValues, minimum: CGSize) -> CGSize {
        var e = env
        e._windowServices = nil
        let measure = ViewGraph(rootView: AnyView(_fromValue: content) ?? AnyView(EmptyView()), environment: e,
                                layout: HostLayout(.proposal(.unspecified), symbols: StubSymbolProvider()))
        measure.update()
        let s = measure.layoutResult?.size ?? minimum
        measure.setRootView(EmptyView())
        measure.update()
        func ok(_ v: CGFloat, _ m: CGFloat) -> CGFloat { v.isFinite && v > 0 ? max(m, v.rounded(.up)) : m }
        return CGSize(width: min(ok(s.width, minimum.width), 1200), height: min(ok(s.height, minimum.height), 900))
    }

    package func openSettings() {
        guard let i = scenes.firstIndex(where: { $0.kind == .settings }) else { return }
        openWindow(sceneIndex: i, activate: true)
    }

    package func quit() {
        if ApplicationTermination.shouldTerminate?() == false { return }
        quitByUser = true
        terminate()
    }

    private func makeWindow(_ config: inout WindowConfiguration)
        -> (any PlatformWindow, (any FramePresenter)?)? {
        if renderer != "software" && !(backend is HeadlessBackend) {
            config.vulkan = true
            if let pw = try? backend.makeWindow(config) {
                let p = makePresenter(pw)
                if let cp = p as? CompositorPresenter, cp.compositor == nil {
                    log?("Vulkan compositor unavailable (\(cp.compositorError ?? "?")); using a software window")
                    pw.close()
                } else {
                    return (pw, p)
                }
            }
            config.vulkan = false
        }
        guard let pw = try? backend.makeWindow(config) else { return nil }
        return (pw, makePresenter(pw))
    }

    package func dismissWindow(id: String?) {
        let targets = id.map { i in windows.filter { $0.sceneID == i } } ?? Array(windows.suffix(1))
        for w in targets { closeWindow(w) }
    }

    package func closeWindow(_ w: WindowHost) {
        if w.isPopup {
            closePopup(w)
            return
        }
        guard let i = windows.firstIndex(where: { $0 === w }) else { return }
        log?("window close \(w.sceneID ?? "#\(w.sceneIndex)")")
        for p in windows where p.isPopup && p.popupOwner === w { closePopup(p) }
        w.setPhase(.background)
        sceneArchive?.discard(key: w.sceneStorage.archiveKey)
        w.teardown()
        w.platform.close()
        windows.removeAll { $0 === w }
        _ = i
        if !windows.contains(where: { !$0.isPopup }) {
            quitByUser = true
            terminate()
        }
    }

    func removeWindow(_ w: WindowHost) { windows.removeAll { $0 === w } }

    func addWindow(_ w: WindowHost) { windows.append(w) }

    package func window(for id: PlatformWindowID) -> WindowHost? { windows.first { $0.platform.id == id } }

    package func openURL(_ url: URL, confirming: Bool = false) {
        log?("openURL \(url.absoluteString)")
        let wasActive = appPhase == .active
        if confirming && wasActive { setAppPhase(.inactive) }
        deliver(.openURLs([url]))
        for w in windows.reversed() {
            w.update()
            if w.deliver(url) { break }
        }
        if confirming && wasActive { setAppPhase(.active) }
    }

    package func terminate() {
        guard !isFinished else { return }
        if appPhase == .active { setAppPhase(.inactive) }
        if appPhase == .inactive { setAppPhase(.background) }
        if quitByUser { sceneArchive?.discardAll() }
        deliver(.willTerminate)
        isFinished = true
        runLoop.stop()
    }

    package func run() { runLoop.run(self) }

    package func run(until deadline: TimeInterval) { runLoop.run(self, until: deadline) }

    package func run(for seconds: TimeInterval) { run(until: backend.now + seconds) }

    package func handle(_ event: PlatformEvent) {
        switch event {
        case .pointer(let p):
            if p.phase == .down, closePopups(outside: p.window, at: p.location) { return }
            window(for: p.window)?.handlePointer(p)
        case .scroll(let s): window(for: s.window)?.handleScroll(s)
        case .key(let k):
            if k.isDown { log?("key \(k.key) \(k.modifiers.rawValue) window \(k.window)") }
            guard var target = window(for: k.window) else { return }
            while let p = windows.last(where: { $0.isPopup && $0.popupOwner === target }) { target = p }
            target.handleKey(k)
        case .textInput(let t): window(for: t.window)?.handleText(t)
        case .textEditing(let e): window(for: e.window)?.handleEditing(e)
        case .openURL(let u): openURL(u)
        case .quit:
            quitByUser = true
            terminate()
        case .settingsChanged: applySettings()
        case .window(let id, let kind):
            guard let w = window(for: id) else { return }
            handleWindowEvent(w, kind)
        }
    }

    private func handleWindowEvent(_ w: WindowHost, _ kind: WindowEventKind) {
        log?("window \(w.platform.id) \(kind)")
        if w.isPopup {
            switch kind {
            case .resized(let s): w.resized(to: s)
            case .scaleChanged(let s): w.scaleChanged(s)
            case .closeRequested, .hidden, .minimized: closePopup(w)
            case .pointerLeft: w.pointerLeft()
            default: w.exposed()
            }
            return
        }
        switch kind {
        case .resized(let s): w.resized(to: s)
        case .scaleChanged(let s): w.scaleChanged(s)
        case .exposed: w.exposed()
        case .closeRequested:
            if windows.filter({ !$0.isPopup }).count == 1, ApplicationTermination.shouldTerminate?() == false { return }
            closeWindow(w)
        case .pointerLeft: w.pointerLeft()
        case .minimized, .hidden:
            w.isMinimized = true
            for p in windows where p.isPopup && p.popupOwner === w { closePopup(p) }
            if windows.filter({ !$0.isPopup }).allSatisfy(\.isMinimized) {
                if appPhase == .active { setAppPhase(.inactive) }
                setAppPhase(.background)
            }
        case .restored, .shown:
            guard w.isMinimized else {
                w.exposed()
                return
            }
            w.isMinimized = false
            w.exposed()
            if appPhase == .background { setAppPhase(.inactive) }
            setAppPhase(.active)
        case .focusGained:
            windowFocusKnown = true
            activeWindowID = w.platform.id
            accessibilityExport?.afterFrame()
        case .focusLost:
            windowFocusKnown = true
            if activeWindowID == w.platform.id { activeWindowID = nil }
            accessibilityExport?.afterFrame()
        }
    }

    package func applySettings() {
        let settings = backend.settings
        log?("settings changed")
        let apply: (inout EnvironmentValues) -> Void = { PlatformEnvironment.apply(settings, to: &$0) }
        appGraph?.updateEnvironment(apply)
        for w in windows { w.applySettings(apply) }
    }

    package var nextTimerDeadline: TimeInterval? { windows.compactMap(\.timerDeadline).min() }

    package func afterWait() { AppStorageCenter.shared.refreshIfObserved() }

    package func fireTimers(now: TimeInterval) {
        for w in windows {
            w.gestures.tick(now)
            w.services.fireTimers(now: now)
        }
    }

    package var needsFrame: Bool { (appGraph?.needsUpdate ?? false) || windows.contains { $0.needsFrame } }

    package func renderFrame(at time: TimeInterval) {
        clock.frameTime = time
        defer { clock.frameTime = nil }
        appGraph?.update()
        for w in windows { w.renderFrame() }
        accessibilityExport?.afterFrame()
    }
}
