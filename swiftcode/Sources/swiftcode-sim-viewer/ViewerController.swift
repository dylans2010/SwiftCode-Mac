#if os(macOS)
import AppKit
import SwiftCodeDeviceModel
import SwiftCodeDeviceUI
import SwiftCodeDisplayStream

@MainActor
final class ViewerController: NSObject, DeviceMenuTarget, NSMenuDelegate {
    let connection: ViewerConnection
    let session: DeviceLiveSession
    let windowController: DeviceWindowController
    private lazy var menus = DeviceMenus(target: self)
    private lazy var settingsMenu = ViewerSettingsMenu(
        send: { [weak self] text, reply in self?.session.sendCommand(text, reply: reply) },
        report: { [weak self] text in self?.windowController.canvas.showBanner(text, seconds: 3) })
    private var foldItem: NSMenuItem?
    private var roomItem: NSMenuItem?

    var log: (String) -> Void = { _ in } {
        didSet { session.log = log }
    }

    init(connection: ViewerConnection, zoom: CGFloat?) {
        self.connection = connection
        session = DeviceLiveSession(connection: connection)
        windowController = DeviceWindowController(session: session, kind: .compact)
        windowController.initialScale = zoom.map(Double.init)
        super.init()
        windowController.onClose = { NSApp.terminate(nil) }
    }

    var window: NSWindow { windowController.window! }
    var canvas: DeviceCanvasView { windowController.canvas }
    var deviceView: DeviceView { canvas.frameView.screen }
    var panelState: DisplayPanelState? { session.panelState }
    var latencies: [(label: String, ms: Double)] { session.latencies }
    var onFrame: ((DisplayFrame) -> Void)? {
        get { session.onFrame }
        set { session.onFrame = newValue }
    }
    var isLiveWithImage: Bool { session.isLive && session.hasImage }

    func fold(to angle: Int) { session.fold(to: angle) }
    func rotate(left: Bool) { session.rotate(left: left) }
    func press(_ b: DisplayButton) { session.press(b) }
    func sendKey(usage: UInt16, down: Bool, label: String?) { session.sendKey(usage: usage, down: down, label: label) }
    func requestScreenshot(_ done: @escaping ([UInt8]?) -> Void) { session.requestScreenshot(done) }
    func shownPNG() -> [UInt8]? { session.shownPNG() }

    func perform(_ c: DeviceCommand) { canvas.perform(c) }

    var activeCanvas: DeviceCanvasView? { windowController.canvas }

    func buildMenu() -> NSMenu {
        let main = NSMenu()
        func item(_ title: String, _ action: Selector?, _ key: String = "", _ mods: NSEvent.ModifierFlags = [.command],
                  target: AnyObject? = nil) -> NSMenuItem {
            let i = NSMenuItem(title: title, action: action, keyEquivalent: key)
            i.keyEquivalentModifierMask = mods
            i.target = target
            return i
        }
        func top(_ menu: NSMenu) {
            let i = NSMenuItem()
            i.submenu = menu
            main.addItem(i)
        }
        let app = NSMenu(title: "SwiftCode Simulator Viewer")
        app.addItem(item("Hide", #selector(NSApplication.hide(_:)), "h", target: NSApp))
        app.addItem(.separator())
        app.addItem(item("Quit", #selector(NSApplication.terminate(_:)), "q", target: NSApp))
        top(app)

        let file = NSMenu(title: "File")
        file.addItem(item("Close", #selector(NSWindow.performClose(_:)), "w"))
        top(file)

        let view = NSMenu(title: "View")
        for i in menus.viewItems() { view.addItem(i) }
        view.addItem(.separator())
        view.addItem(item("Show Frame Rate", #selector(DeviceWindowController.toggleStatistics(_:)), target: windowController))
        view.addItem(.separator())
        view.addItem(item("Enter Full Screen", #selector(NSWindow.toggleFullScreen(_:)), "f", [.command, .control]))
        top(view)

        let device = NSMenu(title: "Device")
        let settings = settingsMenu.items()
        let own = menus.deviceItems()
        for i in settings.prefix(4) { device.addItem(i) }
        device.addItem(own[0])
        for i in settings.dropFirst(4) { device.addItem(i) }
        device.addItem(own[1])
        device.addItem(.separator())
        device.addItem(own[2])
        foldItem = own[2]
        device.addItem(own[3])
        roomItem = own[3]
        device.addItem(.separator())
        device.addItem(item("Refresh Display", #selector(refreshDisplay(_:)), "r", target: self))
        device.delegate = self
        top(device)

        top(menus.controlsMenu())

        let win = NSMenu(title: "Window")
        win.addItem(item("Minimize", #selector(NSWindow.performMiniaturize(_:)), "m"))
        win.addItem(item("Expand", #selector(DeviceWindowController.expand(_:)), target: windowController))
        win.addItem(item("Open in New Window", #selector(DeviceWindowController.openInNewWindow(_:)), target: windowController))
        top(win)
        NSApp.windowsMenu = win
        return main
    }

    @objc func refreshDisplay(_ sender: Any?) { session.refreshDisplay() }

    func menuNeedsUpdate(_ menu: NSMenu) {
        settingsMenu.refresh()
        foldItem?.isHidden = !session.isFoldable
        roomItem?.isHidden = !session.isSpatial
    }
}
#endif
