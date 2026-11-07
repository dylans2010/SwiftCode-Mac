import AppKit
import SwiftCodeDeviceUI
import SwiftCodeIDECore

public struct HubRuntimeChoice: Equatable, Sendable {
    public struct TypeChoice: Equatable, Sendable {
        public var id: String
        public var name: String
        public init(id: String, name: String) { self.id = id; self.name = name }
    }
    public var root: String
    public var title: String
    public var types: [TypeChoice]
    public init(root: String, title: String, types: [TypeChoice]) {
        self.root = root
        self.title = title
        self.types = types
    }
}

@MainActor
public final class HubPairing {
    public internal(set) var pairs: [RemoteDevicePair] = []
    public internal(set) var status: String?
    public internal(set) var task: Task<Void, Never>?

    public var readPairs: (() async -> [RemoteDevicePair]?)?
    public var pairDevices: ((DeviceRow, DeviceRow) async -> (Bool, String))?
    public var unpairPair: ((RemoteDevicePair) async -> (Bool, String))?
    public var activatePair: ((RemoteDevicePair) async -> (Bool, String))?
    public var createDevice: ((String, String, String) -> DeviceRow?)?
    public var deleteDevice: ((DeviceRow) async -> (Bool, String))?
    public var runtimeChoices: ((String) -> [HubRuntimeChoice])?
    public var presentForm: ((HubDeviceForm, @escaping (Bool) -> Void) -> Void)?
    public var confirm: (String, String, String) -> Bool = { title, text, button in
        let a = NSAlert()
        a.messageText = title
        a.informativeText = text
        a.addButton(withTitle: button)
        a.addButton(withTitle: "Cancel")
        a.alertStyle = .warning
        return a.runModal() == .alertFirstButtonReturn
    }
    public var offerPhoneRestart: (String, String) -> Bool = { title, text in
        let a = NSAlert()
        a.messageText = title
        a.informativeText = text
        a.addButton(withTitle: HubPairing.restartPhoneButton)
        a.addButton(withTitle: "Later")
        return a.runModal() == .alertFirstButtonReturn
    }
    public internal(set) var restartTask: Task<Void, Never>?
    public static let restartPhoneButton = "Restart iPhone"
    var polls = 0

    public init() {}
}

@MainActor
public final class HubDeviceFields {
    public let name = NSTextField()
    public let os = NSPopUpButton(frame: .zero, pullsDown: false)
    public let model = NSPopUpButton(frame: .zero, pullsDown: false)
    public let choices: [HubRuntimeChoice]

    init(choices: [HubRuntimeChoice]) {
        self.choices = choices
        os.addItems(withTitles: choices.map(\.title))
        name.placeholderString = choices.first?.types.first?.name
        reloadModels()
    }

    func reloadModels() {
        model.removeAllItems()
        model.addItems(withTitles: runtime?.types.map(\.name) ?? [])
        name.placeholderString = runtime?.types.first?.name
    }

    var runtime: HubRuntimeChoice? { choices.indices.contains(os.indexOfSelectedItem) ? choices[os.indexOfSelectedItem] : choices.first }
    public var typeID: String? {
        guard let r = runtime, r.types.indices.contains(model.indexOfSelectedItem) else { return runtime?.types.first?.id }
        return r.types[model.indexOfSelectedItem].id
    }
    public var root: String? { runtime?.root }
    public var nameValue: String {
        let t = name.stringValue.trimmingCharacters(in: .whitespaces)
        return t.isEmpty ? (model.titleOfSelectedItem ?? "") : t
    }

    public func selectModel(_ name: String) { model.selectItem(withTitle: name) }

    var rows: [[NSView]] {
        [[Self.label("Name:"), name], [Self.label("OS Version:"), os], [Self.label("Model:"), model]]
    }

    static func label(_ s: String) -> NSTextField {
        let l = NSTextField(labelWithString: s)
        l.alignment = .right
        return l
    }
}

@MainActor
public final class HubDeviceForm: NSView {
    public enum Kind: Equatable { case pairWatch, newWatch, newPairedPhone, newVision }
    public let kind: Kind
    public let title: String
    public let message: String
    public let button: String
    public let watchPopUp = NSPopUpButton(frame: .zero, pullsDown: false)
    public let watchChoices: [DeviceRow]
    public let phone: HubDeviceFields?
    public let watch: HubDeviceFields?
    public let vision: HubDeviceFields?
    public static let newWatchTitle = "New Watch"

    init(kind: Kind, title: String, message: String, button: String, watchChoices: [DeviceRow] = [],
         phoneChoices: [HubRuntimeChoice], watchRuntimeChoices: [HubRuntimeChoice], visionRuntimeChoices: [HubRuntimeChoice] = []) {
        self.kind = kind
        self.title = title
        self.message = message
        self.button = button
        self.watchChoices = watchChoices
        phone = kind == .newPairedPhone ? HubDeviceFields(choices: phoneChoices) : nil
        watch = kind == .newVision ? nil : HubDeviceFields(choices: watchRuntimeChoices)
        vision = kind == .newVision ? HubDeviceFields(choices: visionRuntimeChoices) : nil
        super.init(frame: NSRect(x: 0, y: 0, width: 380, height: 10))
        for f in [phone, watch, vision].compactMap({ $0 }) {
            f.os.target = self
            f.os.action = #selector(osChosen(_:))
        }
        var rows: [[NSView]] = []
        if kind == .pairWatch {
            watchPopUp.addItems(withTitles: watchChoices.map(\.name))
            if !watchChoices.isEmpty { watchPopUp.menu?.addItem(.separator()) }
            watchPopUp.addItem(withTitle: Self.newWatchTitle)
            watchPopUp.target = self
            watchPopUp.action = #selector(watchChosen(_:))
            rows.append([HubDeviceFields.label("Watch:"), watchPopUp])
        }
        if let phone { rows += phone.rows }
        if kind == .newPairedPhone {
            let h = NSTextField(labelWithString: "Paired Watch")
            h.font = .systemFont(ofSize: 12, weight: .semibold)
            rows.append([NSGridCell.emptyContentView, h])
        }
        if let watch { rows += watch.rows }
        if let vision { rows += vision.rows }
        let grid = NSGridView(views: rows)
        grid.rowSpacing = 8
        grid.columnSpacing = 8
        grid.column(at: 0).xPlacement = .trailing
        grid.translatesAutoresizingMaskIntoConstraints = false
        addSubview(grid)
        NSLayoutConstraint.activate([
            grid.leadingAnchor.constraint(equalTo: leadingAnchor), grid.trailingAnchor.constraint(equalTo: trailingAnchor),
            grid.topAnchor.constraint(equalTo: topAnchor), grid.bottomAnchor.constraint(equalTo: bottomAnchor),
            widthAnchor.constraint(equalToConstant: 380),
        ])
        for f in [phone?.name, watch?.name, vision?.name].compactMap({ $0 }) { f.widthAnchor.constraint(equalToConstant: 260).isActive = true }
        frame.size = fittingSize
        updateEnabled()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    public var chosenWatch: DeviceRow? {
        watchChoices.indices.contains(watchPopUp.indexOfSelectedItem) ? watchChoices[watchPopUp.indexOfSelectedItem] : nil
    }

    public func chooseWatch(_ name: String) {
        watchPopUp.selectItem(withTitle: name)
        updateEnabled()
    }

    func updateEnabled() {
        let new = kind != .pairWatch || chosenWatch == nil
        for c in [watch?.name, watch?.os, watch?.model].compactMap({ $0 as NSControl? }) { c.isEnabled = new }
    }

    @objc func watchChosen(_ sender: Any?) { updateEnabled() }
    @objc func osChosen(_ sender: NSPopUpButton) {
        for f in [phone, watch, vision].compactMap({ $0 }) where f.os === sender { f.reloadModels() }
    }
}

extension DevicesController {

    func isPairablePhone(_ r: DeviceRow) -> Bool { r.isSwiftCodeRemote && r.platform == "iOS" && (r.deviceTypeID?.hasPrefix("iphone") ?? false) }
    func isSwiftCodeWatch(_ r: DeviceRow) -> Bool { r.isSwiftCodeRemote && r.platform == "watchOS" }

    func remoteRow(directory: String) -> DeviceRow? { simulators.first { $0.isSwiftCodeRemote && $0.deviceDirectory == directory } }

    func displayName(directory: String, typeName: String) -> String { remoteRow(directory: directory)?.name ?? typeName }

    public func pairs(of r: DeviceRow) -> [RemoteDevicePair] {
        guard let dir = r.deviceDirectory else { return [] }
        return RemotePairing(pairing.pairs).pairs(ofDirectory: dir)
    }

    public func pairedCapsuleTitle(for r: DeviceRow) -> String? {
        guard let dir = r.deviceDirectory else { return nil }
        let p = RemotePairing(pairing.pairs)
        if isSwiftCodeWatch(r), let pair = p.pairs(ofDirectory: dir).first {
            return "Paired with \(displayName(directory: pair.phoneDirectory, typeName: pair.phoneTypeName))"
        }
        if let pair = p.activePair(phone: dir) { return "Paired with \(displayName(directory: pair.watchDirectory, typeName: pair.watchTypeName))" }
        return nil
    }

    func pairedPeer(of r: DeviceRow) -> DeviceRow? {
        guard let dir = r.deviceDirectory else { return nil }
        let p = RemotePairing(pairing.pairs)
        if isSwiftCodeWatch(r) { return p.pairs(ofDirectory: dir).first.flatMap { remoteRow(directory: $0.phoneDirectory) } }
        return p.activePair(phone: dir).flatMap { remoteRow(directory: $0.watchDirectory) }
    }

    var pairingAvailable: Bool { !pairing.pairs.isEmpty || !(pairing.runtimeChoices?("watchOS") ?? []).isEmpty }

    func pairInfoRows(for r: DeviceRow) -> [(String, String)] {
        var out: [(String, String)] = []
        guard pairingAvailable else { return out }
        let ps = pairs(of: r)
        if isPairablePhone(r) {
            let active = ps.first { $0.active }
            out.append(("Active Watch", active.map { displayName(directory: $0.watchDirectory, typeName: $0.watchTypeName) } ?? "None"))
            if !ps.isEmpty {
                out.append(("Paired Watches", ps.map { displayName(directory: $0.watchDirectory, typeName: $0.watchTypeName) + ($0.active ? " (active)" : "") }
                    .joined(separator: ", ")))
            }
            if let active { out.append(("Pair", active.stateText)) }
        } else if isSwiftCodeWatch(r) {
            if let pair = ps.first {
                out.append(("Paired With", displayName(directory: pair.phoneDirectory, typeName: pair.phoneTypeName)))
                out.append(("Pair", pair.stateText))
            } else {
                out.append(("Paired With", "None"))
            }
        }
        if r.isSwiftCodeRemote, let s = pairing.status { out.append(("Pairing", s)) }
        return out
    }

    func updatePairedCapsule(for r: DeviceRow?) {
        canvas.pairedTitle = r.flatMap(pairedCapsuleTitle(for:))
        canvas.onPaired = { [weak self] in
            guard let self, let r = self.selected, let peer = self.pairedPeer(of: r), let i = self.rows.firstIndex(where: { $0.identifier == peer.identifier }) else { return }
            self.select(row: i)
        }
    }

    func pairingMenuItems(for r: DeviceRow) -> [NSMenuItem] {
        var out: [NSMenuItem] = []
        let idle = pairing.task == nil
        func item(_ title: String, _ action: Selector, _ object: Any?, enabled: Bool) -> NSMenuItem {
            let i = NSMenuItem(title: title, action: action, keyEquivalent: "")
            i.target = self
            i.representedObject = object
            i.isEnabled = enabled
            return i
        }
        let watches = pairing.runtimeChoices?("watchOS") ?? []
        if isPairablePhone(r), pairingAvailable {
            out.append(item("Pair Watch…", #selector(pairWatchChosen(_:)), r.identifier, enabled: idle && pairing.pairDevices != nil && !watches.isEmpty))
            for p in pairs(of: r) {
                let name = displayName(directory: p.watchDirectory, typeName: p.watchTypeName)
                if !p.active { out.append(item("Make “\(name)” Active", #selector(activatePairChosen(_:)), p.id, enabled: idle && pairing.activatePair != nil)) }
                out.append(item("Unpair “\(name)”", #selector(unpairChosen(_:)), p.id, enabled: idle && pairing.unpairPair != nil))
            }
        } else if isSwiftCodeWatch(r), let p = pairs(of: r).first {
            let name = displayName(directory: p.phoneDirectory, typeName: p.phoneTypeName)
            out.append(item("Unpair from “\(name)”", #selector(unpairChosen(_:)), p.id, enabled: idle && pairing.unpairPair != nil))
        }
        if r.isCreated {
            out.append(item("Delete…", #selector(deleteDeviceChosen(_:)), r.identifier, enabled: idle && pairing.deleteDevice != nil && r.state != "Booted"))
        }
        if !out.isEmpty { out.append(.separator()) }
        return out
    }

    private func pair(id: Any?) -> RemoteDevicePair? { (id as? String).flatMap { id in pairing.pairs.first { $0.id == id } } }
    private func row(identifier: Any?) -> DeviceRow? { (identifier as? String).flatMap { id in allRows.first { $0.identifier == id } } }

    @objc func pairWatchChosen(_ sender: NSMenuItem) { if let r = row(identifier: sender.representedObject) { presentPairWatch(phone: r) } }
    @objc func unpairChosen(_ sender: NSMenuItem) { if let p = pair(id: sender.representedObject) { unpair(p) } }
    @objc func activatePairChosen(_ sender: NSMenuItem) { if let p = pair(id: sender.representedObject) { activate(p) } }
    @objc func deleteDeviceChosen(_ sender: NSMenuItem) { if let r = row(identifier: sender.representedObject) { delete(r) } }
    @objc public func newWatchChosen(_ sender: Any?) { presentNewWatch() }
    @objc public func newPairedPhoneChosen(_ sender: Any?) { presentNewPairedPhone() }
    @objc public func newVisionDeviceChosen(_ sender: Any?) { presentNewVisionDevice() }

    public var canCreateVisionDevices: Bool { pairing.createDevice != nil && !(pairing.runtimeChoices?("visionOS") ?? []).isEmpty }

    public var canCreateWatches: Bool { pairing.createDevice != nil && !(pairing.runtimeChoices?("watchOS") ?? []).isEmpty }

    func unpairedWatches() -> [DeviceRow] {
        let p = RemotePairing(pairing.pairs)
        return simulators.filter { isSwiftCodeWatch($0) && !p.isPaired(watch: $0.deviceDirectory ?? "") }
    }

    @discardableResult
    public func presentPairWatch(phone: DeviceRow) -> HubDeviceForm {
        let form = HubDeviceForm(kind: .pairWatch, title: "Pair a Watch with “\(phone.name)”",
                                 message: "Choose a watch simulator, or create one. The watch pairs with this iPhone; a new pair is active when the phone has no active watch.",
                                 button: "Pair", watchChoices: unpairedWatches(), phoneChoices: [], watchRuntimeChoices: pairing.runtimeChoices?("watchOS") ?? [])
        present(form) { [weak self] ok in
            guard ok, let self else { return }
            self.runPairing("Pairing…") {
                guard let watch = form.chosenWatch ?? self.create(form.watch) else { return (false, "The watch could not be created.") }
                return await self.pairing.pairDevices?(phone, watch) ?? (false, "Pairing is not available.")
            }
        }
        return form
    }

    @discardableResult
    public func presentNewWatch() -> HubDeviceForm {
        let form = HubDeviceForm(kind: .newWatch, title: "New Watch Simulator", message: "A watch simulator of SwiftCode's. Pair it with an iPhone from the iPhone's context menu.",
                                 button: "Create", phoneChoices: [], watchRuntimeChoices: pairing.runtimeChoices?("watchOS") ?? [])
        present(form) { [weak self] ok in
            guard ok, let self, let row = self.create(form.watch) else { return }
            if let i = self.rows.firstIndex(where: { $0.identifier == row.identifier }) { self.select(row: i) }
        }
        return form
    }

    @discardableResult
    public func presentNewPairedPhone() -> HubDeviceForm {
        let form = HubDeviceForm(kind: .newPairedPhone, title: "New iPhone with Paired Watch",
                                 message: "Creates an iPhone simulator and a watch simulator of SwiftCode's and pairs them.",
                                 button: "Create", phoneChoices: pairing.runtimeChoices?("iOS") ?? [], watchRuntimeChoices: pairing.runtimeChoices?("watchOS") ?? [])
        present(form) { [weak self] ok in
            guard ok, let self else { return }
            self.runPairing("Creating and pairing…") {
                guard let phone = self.create(form.phone), let watch = self.create(form.watch) else { return (false, "The devices could not be created.") }
                if let i = self.rows.firstIndex(where: { $0.identifier == phone.identifier }) { self.select(row: i) }
                return await self.pairing.pairDevices?(phone, watch) ?? (false, "Pairing is not available.")
            }
        }
        return form
    }

    @discardableResult
    public func presentNewVisionDevice() -> HubDeviceForm {
        let form = HubDeviceForm(kind: .newVision, title: "New Apple Vision Pro Simulator",
                                 message: "An Apple Vision Pro simulator of SwiftCode's. Start it to boot it to its room.",
                                 button: "Create", phoneChoices: [], watchRuntimeChoices: [],
                                 visionRuntimeChoices: pairing.runtimeChoices?("visionOS") ?? [])
        present(form) { [weak self] ok in
            guard ok, let self, let row = self.create(form.vision) else { return }
            if let i = self.rows.firstIndex(where: { $0.identifier == row.identifier }) { self.select(row: i) }
        }
        return form
    }

    private func create(_ f: HubDeviceFields?) -> DeviceRow? {
        guard let f, let type = f.typeID, let root = f.root else { return nil }
        return pairing.createDevice?(f.nameValue, type, root)
    }

    private func present(_ form: HubDeviceForm, _ done: @escaping (Bool) -> Void) {
        if let p = pairing.presentForm { p(form, done); return }
        let a = NSAlert()
        a.messageText = form.title
        a.informativeText = form.message
        a.accessoryView = form
        a.addButton(withTitle: form.button)
        a.addButton(withTitle: "Cancel")
        if let w = view.window, w.isVisible {
            a.beginSheetModal(for: w) { done($0 == .alertFirstButtonReturn) }
        } else {
            done(a.runModal() == .alertFirstButtonReturn)
        }
    }

    @discardableResult
    public func unpair(_ p: RemoteDevicePair) -> Task<Void, Never>? {
        let watch = displayName(directory: p.watchDirectory, typeName: p.watchTypeName)
        let phone = displayName(directory: p.phoneDirectory, typeName: p.phoneTypeName)
        guard pairing.confirm("Unpair “\(watch)” from “\(phone)”?",
                              "The watch is shut down and erased: its apps, their data and its settings are deleted. The iPhone is kept.", "Unpair") else { return nil }
        return runPairing("Unpairing…") { await self.pairing.unpairPair?(p) ?? (false, "Pairing is not available.") }
    }

    @discardableResult
    public func activate(_ p: RemoteDevicePair) -> Task<Void, Never>? {
        runPairing("Switching the active watch…", then: { [weak self] ok in
            guard ok, let self else { return }
            self.notePhoneRestart(after: p)
        }) { await self.pairing.activatePair?(p) ?? (false, "Pairing is not available.") }
    }

    static func phoneRestartNote(phone: String, watch: String) -> (title: String, text: String) {
        ("“\(watch)” is now the active watch of “\(phone)”.",
         "Apps on the iPhone keep using the previous watch until the iPhone restarts. Restart the iPhone now to connect its apps to “\(watch)”.")
    }

    private func notePhoneRestart(after p: RemoteDevicePair) {
        guard let phoneRow = remoteRow(directory: p.phoneDirectory), phoneRow.state == "Booted" else { return }
        let watch = displayName(directory: p.watchDirectory, typeName: p.watchTypeName)
        let note = Self.phoneRestartNote(phone: phoneRow.name, watch: watch)
        pairing.status = "Active; apps on the iPhone keep the previous watch until the iPhone restarts"
        if isViewLoaded { updateInspector() }
        guard pairing.offerPhoneRestart(note.title, note.text) else { return }
        pairing.status = "Active; restarting the iPhone"
        if isViewLoaded { updateInspector() }
        pairing.restartTask = restart(phoneRow)
    }

    @discardableResult
    public func delete(_ r: DeviceRow) -> Task<Void, Never>? {
        if !pairs(of: r).isEmpty {
            pairing.status = "Unpair “\(r.name)” before deleting it."
            if isViewLoaded { updateInspector() }
            return nil
        }
        guard pairing.confirm("Delete “\(r.name)”?", "Its apps, their data, its settings and its saved state are deleted. You can’t undo this action.", "Delete") else { return nil }
        return runPairing("Deleting…") { await self.pairing.deleteDevice?(r) ?? (false, "Deleting is not available.") }
    }

    @discardableResult
    func runPairing(_ busy: String, then: (@MainActor (Bool) -> Void)? = nil,
                    _ work: @escaping @MainActor () async -> (Bool, String)) -> Task<Void, Never>? {
        guard pairing.task == nil else { return nil }
        pairing.status = busy
        if isViewLoaded { updateInspector() }
        let task = Task { [weak self] in
            let (ok, message) = await work()
            guard let self else { return }
            self.pairing.status = ok ? message : "Failed: \(message)"
            await self.refreshPairs()
            self.pairing.task = nil
            self.reloadRemoteRows()
            then?(ok)
        }
        pairing.task = task
        return task
    }

    public func refreshPairs() async {
        guard let read = pairing.readPairs, let p = await read() else { return }
        setPairs(p)
    }

    public func setPairs(_ p: [RemoteDevicePair]) {
        pairing.pairs = p
        guard isViewLoaded else { return }
        updatePairedCapsule(for: multipleSelection.count > 1 ? nil : selected)
        updateInspector()
    }

    func reloadRemoteRows() {
        if let rows = currentRemoteRows?() { setSwiftCodeRemote(rows: rows) }
        if isViewLoaded { showDetails() }
    }

    func pollPairs() {
        pairing.polls += 1
        guard pairing.polls % 8 == 0, pairing.task == nil else { return }
        Task { await refreshPairs() }
    }
}
