import AppKit
import YcodeDeviceUI
import YcodeIDECore

@MainActor
public final class HubHeadset {
    public var route: ((DeviceRow) -> HeadsetRoute?)?
    public var makeRunner: (HeadsetViewerHost) -> (any HeadsetCommandRunner)? = { host in
        switch host {
        case .thisMachine: LocalHeadsetRunner()
        case .ssh(let d): SSHHeadsetRunner(destination: d)
        case .none: nil
        }
    }
    public var makeLauncher: ((HeadsetViewerPlan, any HeadsetCommandRunner) -> any HeadsetViewerLauncher) = { plan, runner in
        ScriptHeadsetViewerLauncher(runner: runner, plan: plan)
    }
    public var hubIsLinux: Bool = {
        #if os(Linux)
        true
        #else
        false
        #endif
    }()
    public internal(set) var report: HeadsetReport?
    public internal(set) var checkTask: Task<Void, Never>?
    public internal(set) var switches: [String: HeadsetSwitchController] = [:]
    var desktops: [String: HubDesktopStream] = [:]
    var setupWindow: HeadsetSetupWindowController?
    public internal(set) var actionStatus: String?
    public var visionDisplay: (get: () -> String, set: (String) -> Void)?
    public var confirmRestart: (DeviceRow) -> Bool = { HubHeadset.runRestartAlert($0) }
    public var confirmInstall: (HeadsetClientPackage) -> Bool = { HubHeadset.runInstallAlert($0) }
    public init() {}

    static func runRestartAlert(_ r: DeviceRow) -> Bool {
        let a = NSAlert()
        a.messageText = "Restart “\(r.name)” with the new display?"
        a.informativeText = "The display size is set when the device starts. Restarting saves the device and starts it again with the new size; its apps and data stay."
        a.addButton(withTitle: "Restart")
        a.addButton(withTitle: "Later")
        return a.runModal() == .alertFirstButtonReturn
    }

    static func runInstallAlert(_ p: HeadsetClientPackage) -> Bool {
        let a = NSAlert()
        a.messageText = "Install WiVRn \(p.version) on the headset?"
        a.informativeText = p.explanation
        a.addButton(withTitle: "Download and Install")
        a.addButton(withTitle: "Cancel")
        return a.runModal() == .alertFirstButtonReturn
    }
}

@MainActor
final class HubDesktopStream: HeadsetDesktopStream {
    weak var session: DeviceLiveSession?
    init(_ s: DeviceLiveSession?) { session = s }
    func holdForHeadset() { session?.holdForHeadset() }
    func returnFromHeadset() { session?.takeBack() }
}

extension DevicesController {
    public static let headsetSetupTitle = "Set Up Headset…"

    public var headsetSettings: HeadsetSettings {
        get { HeadsetSettings.load(defaults) }
        set { newValue.save(defaults) }
    }

    public var headsetHost: HeadsetViewerHost { headsetSettings.host(hubIsLinux: headset.hubIsLinux) }

    func isHeadsetRow(_ r: DeviceRow?) -> Bool { r?.isSwiftCodeRemote == true && r?.platform == "visionOS" }
    public var headsetControlsShown: Bool { isHeadsetRow(selected) }

    public func headsetSwitch(for r: DeviceRow) -> HeadsetSwitchController? { headset.switches[r.identifier] }

    public func headsetStatus(for r: DeviceRow) -> HeadsetStatus {
        if headset.switches[r.identifier]?.machine.isInHeadset == true { return .inHeadset }
        return headset.report?.status ?? .notSetUp
    }

    public func headsetCommandTitle(for r: DeviceRow?) -> String {
        guard let r, headset.switches[r.identifier]?.machine.isInHeadset == true else { return "View in Headset" }
        return "Back to Desktop"
    }

    func canToggleHeadset(_ r: DeviceRow?) -> Bool {
        guard let r, isHeadsetRow(r), r.state == "Booted" else { return false }
        if let s = headset.switches[r.identifier]?.state, s == .returningToDesktop { return false }
        return true
    }

    @discardableResult
    public func checkHeadset(_ row: DeviceRow? = nil) -> Task<Void, Never> {
        if let t = headset.checkTask { return t }
        let r = row ?? selected
        let settings = headsetSettings
        let host = headsetHost
        let route = r.flatMap { headset.route?($0) }
        let runner = headset.makeRunner(host) ?? NoHeadsetRunner()
        let task = Task { [weak self] in
            let report = await HeadsetChecker(host: host, settings: settings, route: route, runner: runner).run()
            guard let self else { return }
            self.headset.report = report
            self.headset.checkTask = nil
            self.headsetChanged()
        }
        headset.checkTask = task
        return task
    }

    func headsetChanged() {
        guard isViewLoaded else { return }
        if inspectorTab == .settings, headsetControlsShown { updateInspector() }
        view.window?.toolbar?.validateVisibleItems()
        headset.setupWindow?.refresh()
        for w in compactWindows.values { w.window?.toolbar?.validateVisibleItems() }
    }

    @discardableResult
    public func toggleHeadset(_ row: DeviceRow? = nil) -> Task<Void, Never>? {
        guard let r = row ?? selected, canToggleHeadset(r) else { NSSound.beep(); return nil }
        if headset.switches[r.identifier]?.machine.isInHeadset == true { return backToDesktop(r) }
        return viewInHeadset(r)
    }

    @discardableResult
    public func viewInHeadset(_ r: DeviceRow) -> Task<Void, Never>? {
        guard canToggleHeadset(r) else { return nil }
        return Task { [weak self] in
            guard let self else { return }
            if self.headset.report == nil { await self.checkHeadset(r).value }
            guard let report = self.headset.report, report.isReady, let route = self.headset.route?(r),
                  let runner = self.headset.makeRunner(self.headsetHost) else {
                self.presentHeadsetSetup()
                return
            }
            if !report.isConnected, let serial = report.serial, let package = report.clientPackage, self.headsetSettings.connection == .usb {
                _ = await runner.run(HeadsetActions.connectCommand(serial: serial, package: package))
            }
            let c = self.switchController(for: r, route: route, runner: runner)
            await c.viewInHeadset()
        }
    }

    @discardableResult
    public func backToDesktop(_ r: DeviceRow) -> Task<Void, Never>? {
        guard let c = headset.switches[r.identifier] else { return nil }
        return Task { await c.backToDesktop() }
    }

    func switchController(for r: DeviceRow, route: HeadsetRoute, runner: any HeadsetCommandRunner) -> HeadsetSwitchController {
        let settings = headsetSettings
        let plan = HeadsetViewerPlan(device: r.deviceDirectory ?? r.name, route: route, viewerPath: settings.viewerPath,
                                     options: settings.viewerOptions.split(separator: " ").map(String.init))
        let desktop = HubDesktopStream(link(for: r)?.session)
        if headset.switches[r.identifier]?.state == .desktop { headset.switches[r.identifier] = nil }
        if let c = headset.switches[r.identifier] { return c }
        let c = HeadsetSwitchController(launcher: headset.makeLauncher(plan, runner), desktop: desktop)
        c.onNotice = { [weak self] text in self?.canvas.showBanner(text, seconds: 4) }
        c.onChange = { [weak self] _ in self?.headsetChanged() }
        headset.switches[r.identifier] = c
        headset.desktops[r.identifier] = desktop
        return c
    }

    func headsetDeviceStopped(_ id: String) {
        guard let c = headset.switches[id] else { return }
        Task { await c.deviceStopped() }
    }

    @objc func headsetToggleChosen(_ sender: Any?) {
        if let id = (sender as? NSMenuItem)?.representedObject as? String, let r = allRows.first(where: { $0.identifier == id }) {
            toggleHeadset(r)
        } else {
            toggleHeadset()
        }
    }

    @objc func headsetSetupChosen(_ sender: Any?) { presentHeadsetSetup() }

    func headsetMenuItems(for r: DeviceRow) -> [NSMenuItem] {
        guard isHeadsetRow(r) else { return [] }
        let toggle = NSMenuItem(title: headsetCommandTitle(for: r), action: #selector(headsetToggleChosen(_:)), keyEquivalent: "h")
        toggle.keyEquivalentModifierMask = [.command, .control]
        toggle.target = self
        toggle.representedObject = r.identifier
        toggle.isEnabled = canToggleHeadset(r)
        let setup = NSMenuItem(title: Self.headsetSetupTitle, action: #selector(headsetSetupChosen(_:)), keyEquivalent: "")
        setup.target = self
        return [toggle, setup, .separator()]
    }

    @discardableResult
    public func presentHeadsetSetup() -> HeadsetSetupWindowController {
        if let w = headset.setupWindow {
            w.window?.makeKeyAndOrderFront(nil)
            return w
        }
        let w = HeadsetSetupWindowController(hub: self)
        headset.setupWindow = w
        w.onClose = { [weak self] in self?.headset.setupWindow = nil }
        w.showWindow(nil)
        if headset.report == nil { checkHeadset() }
        return w
    }

    @discardableResult
    public func connectHeadset() -> Task<Void, Never>? {
        guard let report = headset.report, let serial = report.serial, let package = report.clientPackage,
              let runner = headset.makeRunner(headsetHost) else { return nil }
        headset.actionStatus = "Connecting…"
        headsetChanged()
        return Task { [weak self] in
            let r = await runner.run(HeadsetActions.connectCommand(serial: serial, package: package))
            guard let self else { return }
            self.headset.actionStatus = r.ok ? "Asked the headset to connect; put it on." : "Connect failed: \(r.output.trimmingCharacters(in: .whitespacesAndNewlines))"
            await self.checkHeadset().value
        }
    }

    @discardableResult
    public func installHeadsetClient(_ p: HeadsetClientPackage) -> Task<Void, Never>? {
        guard let serial = headset.report?.serial, let runner = headset.makeRunner(headsetHost), headset.confirmInstall(p) else { return nil }
        headset.actionStatus = "Downloading WiVRn \(p.version) and installing it…"
        headsetChanged()
        return Task { [weak self] in
            let r = await runner.run(HeadsetActions.installCommand(serial: serial, package: p))
            guard let self else { return }
            self.headset.actionStatus = r.ok ? "Installed WiVRn \(p.version) on the headset." : "Install failed: \(r.output.suffix(300))"
            await self.checkHeadset().value
        }
    }

    public static let displayTitles = ["Desktop (3840 × 2160)", "Headset (2160 × 3840)"]

    func runningDisplayIsTall(_ r: DeviceRow) -> Bool? {
        guard r.state == "Booted", let h = links[r.identifier]?.session.hello else { return nil }
        return h.pixelHeight > h.pixelWidth
    }

    public func chooseVisionDisplay(_ title: String, row: DeviceRow? = nil) {
        guard let i = Self.displayTitles.firstIndex(of: title), let setting = headset.visionDisplay else { return }
        let value = i == 1 ? RemoteSimulatorSettings.headsetVisionDisplay : ""
        guard value != setting.get() else { return }
        setting.set(value)
        if let r = row ?? selected, let tall = runningDisplayIsTall(r), tall != (i == 1), headset.confirmRestart(r) { restart(r) }
        headsetChanged()
    }

    @objc func visionDisplayChosen(_ sender: NSPopUpButton) {
        if let t = sender.titleOfSelectedItem { chooseVisionDisplay(t) }
    }

    func headsetControls() -> NSView {
        let r = selected!
        let image = NSImageView(image: NSImage(systemSymbolName: "eyeglasses", accessibilityDescription: "Headset") ?? NSImage())
        image.contentTintColor = .secondaryLabelColor
        let label = NSTextField(labelWithString: "Headset")
        label.font = .systemFont(ofSize: 12)
        let status = headsetStatus(for: r)
        let statusText = NSTextField(labelWithString: status.rawValue)
        statusText.font = .systemFont(ofSize: 11, weight: .medium)
        statusText.identifier = .init("headset-status")
        statusText.setAccessibilityLabel("Headset: \(status.rawValue)")
        let (mark, markColor): (String, NSColor) = switch status {
        case .notSetUp: ("exclamationmark.circle", .secondaryLabelColor)
        case .ready: ("checkmark.circle.fill", .systemGreen)
        case .inHeadset: ("eyeglasses", .controlAccentColor)
        }
        let markView = NSImageView(image: NSImage(systemSymbolName: mark, accessibilityDescription: nil) ?? NSImage())
        markView.contentTintColor = markColor
        markView.symbolConfiguration = .init(pointSize: 11, weight: .medium)
        let statusRow = NSStackView(views: [markView, statusText])
        statusRow.spacing = 4
        statusRow.edgeInsets = NSEdgeInsets(top: 2, left: 8, bottom: 2, right: 8)
        let capsule = NSView()
        let pill = SelectionPillView()
        for v in [pill, statusRow] as [NSView] {
            v.translatesAutoresizingMaskIntoConstraints = false
            capsule.addSubview(v)
        }
        NSLayoutConstraint.activate([
            pill.leadingAnchor.constraint(equalTo: capsule.leadingAnchor), pill.trailingAnchor.constraint(equalTo: capsule.trailingAnchor),
            pill.topAnchor.constraint(equalTo: capsule.topAnchor), pill.bottomAnchor.constraint(equalTo: capsule.bottomAnchor),
            statusRow.leadingAnchor.constraint(equalTo: capsule.leadingAnchor), statusRow.trailingAnchor.constraint(equalTo: capsule.trailingAnchor),
            statusRow.topAnchor.constraint(equalTo: capsule.topAnchor), statusRow.bottomAnchor.constraint(equalTo: capsule.bottomAnchor),
        ])
        let setup = NSButton(title: Self.headsetSetupTitle, target: self, action: #selector(headsetSetupChosen(_:)))
        GlassBars.style(setup)
        setup.controlSize = .small
        setup.identifier = .init("headset-setup")
        let toggle = NSButton(title: headsetCommandTitle(for: r), target: self, action: #selector(headsetToggleChosen(_:)))
        GlassBars.style(toggle, primary: true)
        toggle.controlSize = .small
        toggle.isEnabled = canToggleHeadset(r)
        toggle.identifier = .init("headset-toggle")
        let buttons = NSStackView(views: [setup, toggle])
        buttons.spacing = 6
        var rows: [[NSView]] = []
        if let setting = headset.visionDisplay {
            let display = NSPopUpButton(frame: .zero, pullsDown: false)
            display.addItems(withTitles: Self.displayTitles)
            display.selectItem(at: setting.get().isEmpty ? 0 : 1)
            if #available(macOS 26, *) { display.bezelStyle = .glass; display.borderShape = .capsule }
            display.controlSize = .small
            display.target = self
            display.action = #selector(visionDisplayChosen(_:))
            display.identifier = .init("headset-display")
            display.toolTip = "The headset shows 90° × 121° with a tall display, 90° × 59° with the desktop's. Applies when the device starts."
            let dl = NSTextField(labelWithString: "Display")
            dl.font = .systemFont(ofSize: 12)
            rows.append([NSGridCell.emptyContentView, dl, display])
        }
        let note = NSTextField(wrappingLabelWithString: headsetNote(for: r))
        note.font = .systemFont(ofSize: 11)
        note.textColor = .secondaryLabelColor
        let grid = NSGridView(views: [[image, label, capsule], [NSGridCell.emptyContentView, NSGridCell.emptyContentView, buttons]] + rows
                                + [[NSGridCell.emptyContentView, NSGridCell.emptyContentView, note]])
        grid.rowSpacing = 6
        grid.columnSpacing = 8
        grid.column(at: 0).width = 18
        grid.column(at: 1).xPlacement = .leading
        grid.column(at: 2).xPlacement = .leading
        let box = NSBox()
        box.titlePosition = .noTitle
        box.contentView = grid
        box.identifier = .init("headset-controls")
        return box
    }

    func headsetNote(for r: DeviceRow) -> String {
        if headset.switches[r.identifier]?.machine.isInHeadset == true { return "The device shows in the headset; the canvas waits." }
        if r.state != "Booted" { return "Start the device to view it in the headset." }
        if headset.checkTask != nil { return "Checking…" }
        guard let report = headset.report else { return "Not checked yet." }
        if !report.isReady { return "Step \(report.firstProblemStep.rawValue + 1), \(report.firstProblemStep.title), needs you." }
        if runningDisplayIsTall(r) == false, headset.visionDisplay != nil {
            return "This device runs the desktop's display: the headset shows 90° × 59°. Display ▸ Headset gives 90° × 121° from the next start."
        }
        return report.isConnected ? "The headset is connected to WiVRn." : "View in Headset connects the headset first."
    }
}

struct NoHeadsetRunner: HeadsetCommandRunner {
    func run(_ command: String) async -> HeadsetCommandResult { HeadsetCommandResult(status: 255) }
}
