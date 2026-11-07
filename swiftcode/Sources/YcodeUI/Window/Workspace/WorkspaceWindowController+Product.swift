import AppKit
import YcodeBuild
import YcodeIDECore

extension WorkspaceWindowController {

    func runScheme(building: Bool) {
        if let d = session.destination, d.isSwiftCodeRemoteSimulator { Task { await runOnSwiftCodeRemote(d, building: building) }; return }
        let request = session.model.buildRequest(scheme: session.scheme, destination: session.destination, action: .build)
        let engine = session.engine
        if let d = session.destination, d.isSwiftCodeRemoteSimulator || (d.kind == .simulator && d.platform != "macOS") {
            Task {
                if building {
                    let result = await session.build(.build)
                    guard result.status == .succeeded else { return }
                }
                guard let exe = await Task.detached(operation: { engine.executablePath(for: request) }).value else { return }
                let app = URL(fileURLWithPath: Self.simulatorAppPath(fromExecutablePath: exe))
                guard building || FileManager.default.fileExists(atPath: app.path) else {
                    session.reportMissingProduct(app.path)
                    return
                }
                if d.isSwiftCodeRemoteSimulator {
                    await session.runOnRemoteSimulator(app: app, remote: RemoteSimulator(settings: RemoteSimulatorSettings.load(Preferences.shared.defaults), destination: d))
                } else if let udid = d.identifier {
                    await session.runOnSimulator(app: app, udid: udid, debug: true, simctl: simctl)
                }
            }
            return
        }
        Task {
            let program = await Task.detached { engine.executablePath(for: request) }.value
            await session.run(program: program, building: building)
        }
    }

    @objc public func runWithoutBuilding(_ sender: Any?) { runScheme(building: false) }

    @objc public func profileProduct(_ sender: Any?) { profileScheme(building: true) }
    @objc public func profileWithoutBuilding(_ sender: Any?) { profileScheme(building: false) }

    static let profilingUnavailable = "Gauge records apps on the SwiftCode simulator (experimental); it cannot record apps on this Mac yet. Choose a SwiftCode simulator destination."

    @discardableResult
    func profileScheme(building: Bool, rate: Int = GaugeSettings.sampleRate) -> GaugeWindowController? {
        guard let d = session.destination, d.isSwiftCodeRemoteSimulator else {
            session.appendConsole("SwiftCode: Gauge: \(Self.profilingUnavailable)\n", kind: .debugger)
            if let window, window.isVisible {
                let alert = NSAlert()
                alert.messageText = "Gauge cannot profile this destination yet"
                alert.informativeText = Self.profilingUnavailable
                alert.beginSheetModal(for: window)
            }
            return nil
        }
        var built = session.model.buildRequest(scheme: session.scheme, destination: d, action: .build)
        built.configuration = session.configuration(for: "ProfileAction")
        let request = built
        let engine = session.engine
        let remote = RemoteSimulator(settings: RemoteSimulatorSettings.load(Preferences.shared.defaults), destination: d)
        let gauge = GaugeWindowController(title: "Gauge")
        gauge.onStop = { [weak self] in self?.session.stopSimulatorRun(remote: remote) }
        gauge.onRecord = { [weak self, weak gauge] in
            gauge?.close()
            self?.profileScheme(building: building, rate: rate)
        }
        gauge.beginRecording(target: "\(session.scheme ?? session.model.displayName) on \(d.name)", rate: rate)
        gauge.present()
        Task { [weak self] in
            guard let self else { return }
            if building {
                let result = await self.session.buildFor(.profiling)
                guard result.status == .succeeded else { gauge.fail("the build failed"); return }
            }
            guard let exe = await Task.detached(operation: { engine.executablePath(for: request) }).value else { gauge.fail("no product to profile"); return }
            let app = URL(fileURLWithPath: Self.simulatorAppPath(fromExecutablePath: exe))
            guard FileManager.default.fileExists(atPath: app.path) else {
                self.session.reportMissingProduct(app.path)
                gauge.fail("\(app.lastPathComponent) has not been built")
                return
            }
            let profile = remote.profile(app: app, rate: rate)
            gauge.beginRecording(target: "\(app.deletingPathExtension().lastPathComponent) on \(d.name)", rate: rate)
            await self.session.runOnRemoteSimulator(app: app, remote: remote, profile: profile) { result in
                switch result {
                case .success(let url): gauge.load(url: url)
                case .failure(let error): gauge.fail("\(error)")
                }
            }
        }
        return gauge
    }

    @objc public func buildForRunning(_ sender: Any?) { Task { await session.buildFor(.running) } }
    @objc public func buildForTesting(_ sender: Any?) { Task { await session.buildFor(.testing) } }
    @objc public func buildForProfiling(_ sender: Any?) { Task { await session.buildFor(.profiling) } }

    @objc public func testWithoutBuilding(_ sender: Any?) { Task { await session.runTests(withoutBuilding: true) } }
    @objc public func testAgain(_ sender: Any?) { Task { await session.testAgain() } }
    @objc public func testWithoutBuildingAgain(_ sender: Any?) { Task { await session.testAgain(withoutBuilding: true) } }
    @objc public func clearTestResults(_ sender: Any?) { session.clearTestResults() }

    @objc public func testSelectedTests(_ sender: Any?) {
        let tests = selectedTests
        guard !tests.isEmpty else { NSSound.beep(); return }
        Task { await session.runTests(only: tests) }
    }

    public var selectedTests: [DiscoveredTest] {
        if navigator.selectedIndex == 5, let item = navigator.selectedItem {
            if let path = item.path, let line = item.line {
                if let t = session.tests.first(where: { $0.file == path && $0.line == line }) { return [t] }
                let suite = session.testsForDiamond(file: path, line: line)
                if !suite.isEmpty { return suite }
            }
            func leaves(_ i: OutlineItem) -> [OutlineItem] { i.children.isEmpty ? [i] : i.children.flatMap(leaves) }
            let rows = leaves(item)
            let found = session.tests.filter { t in rows.contains { $0.path == t.file && $0.line == t.line } }
            if !found.isEmpty { return found }
        }
        guard let file = editor.fileURL?.path, editor.auxiliary == nil else { return [] }
        return session.tests(atCaret: file, line: editor.currentLine)
    }

    @objc public func compileFile(_ sender: Any?) { performFileAction(.compile) }
    @objc public func analyzeFile(_ sender: Any?) { performFileAction(.analyze) }
    @objc public func preprocessFile(_ sender: Any?) { performFileAction(.preprocess) }
    @objc public func assembleFile(_ sender: Any?) { performFileAction(.assemble) }

    @discardableResult
    public func performFileAction(_ action: FileAction) -> Task<(result: BuildResult, output: String?), Never>? {
        guard let file = editor.fileURL?.path, WorkspaceSession.canPerform(action, file: file) else { NSSound.beep(); return nil }
        try? editor.save()
        let request = session.model.buildRequest(scheme: session.scheme, destination: session.destination, action: .build)
        let engine = session.engine
        let isProject = session.model.kind != .package
        return Task { @MainActor in
            let products: String? = isProject ? await Task.detached {
                engine.executablePath(for: request).flatMap { exe -> String? in
                    guard let r = exe.range(of: "/Products/") else { return nil }
                    let rest = exe[r.upperBound...]
                    return String(exe[..<r.upperBound]) + String(rest.prefix { $0 != "/" })
                }
            }.value : nil
            let r = await session.perform(action, file: file, productsDirectory: products)
            if let out = r.output, action == .preprocess || action == .assemble { open(path: out, line: nil) }
            return r
        }
    }

    @discardableResult
    public func confirmCleanBuildFolder() -> NSAlert {
        let alert = NSAlert()
        alert.messageText = "Clean the build folder of \u{201C}\(session.scheme ?? session.model.displayName)\u{201D}?"
        alert.informativeText = "All products and intermediate files in the build folder are deleted. The next build builds everything again."
        alert.addButton(withTitle: "Clean")
        alert.addButton(withTitle: "Cancel")
        if let window, window.isVisible {
            alert.beginSheetModal(for: window) { [weak self] r in
                if r == .alertFirstButtonReturn { self?.cleanProductImmediately(nil) }
            }
        }
        return alert
    }

    @objc public func cleanProductImmediately(_ sender: Any?) { Task { await session.build(.clean) } }

    @discardableResult
    public func editSchemeThenPerform(action index: Int, _ perform: @escaping @MainActor () -> Void) -> SchemeEditorController? {
        guard let scheme = session.model.loadSchemes().first(where: { $0.name == session.scheme }) else {
            perform()
            return nil
        }
        let editor = SchemeEditorController(scheme: scheme, configurations: session.model.configurationNames)
        editor.startSelection = (index, 0)
        editor.onSelect = { [weak self] a, t in self?.schemeEditorState.selection = (a, t) }
        editor.onManage = { [weak self, weak editor] in
            guard let self else { return }
            editor?.presentAsSheet(self.manageSchemesController())
        }
        editor.onClose = { _ in perform() }
        if window?.isVisible == true { contentViewController?.presentAsSheet(editor) }
        return editor
    }

    @objc public func runProductEditingScheme(_ sender: Any?) { editSchemeThenPerform(action: 1) { [weak self] in self?.runProduct(nil) } }
    @objc public func testProductEditingScheme(_ sender: Any?) { editSchemeThenPerform(action: 2) { [weak self] in self?.testProduct(nil) } }
    @objc public func profileProductEditingScheme(_ sender: Any?) { editSchemeThenPerform(action: 3) { [weak self] in self?.profileProduct(nil) } }
    @objc public func analyzeProductEditingScheme(_ sender: Any?) { editSchemeThenPerform(action: 4) { [weak self] in self?.analyzeProduct(nil) } }
    @objc public func archiveProductEditingScheme(_ sender: Any?) { editSchemeThenPerform(action: 5) { [weak self] in self?.archiveProduct(nil) } }

    @objc public func selectDestinationRow(_ sender: Any?) {
        guard let key = (sender as? NSMenuItem)?.representedObject as? String ?? sender as? String else { return }
        let all = session.model.destinations + destinationMenuModel().sections.flatMap(\.destinations)
        guard let d = Self.destination(forKey: key, in: all) else { return }
        session.destination = d
        rememberDestination()
        rebuildDestinationMenu()
    }

    @objc public func selectNextDestination(_ sender: Any?) { stepDestination(1) }
    @objc public func selectPreviousDestination(_ sender: Any?) { stepDestination(-1) }

    func stepDestination(_ delta: Int) {
        let rows = destinationMenuModel().selectable
        guard !rows.isEmpty else { NSSound.beep(); return }
        let current = session.destination.map(Self.menuKey(for:))
        let i = rows.firstIndex { Self.menuKey(for: $0) == current }
        let next = i.map { ($0 + delta + rows.count) % rows.count } ?? (delta > 0 ? 0 : rows.count - 1)
        selectDestinationRow(Self.menuKey(for: rows[next]))
    }

    @objc public func showAllRunDestinations(_ sender: Any?) {
        guard window?.isVisible == true else { return }
        rebuildDestinationMenu(expandIncompatible: true)
        destinationPopUp.performClick(nil)
        rebuildDestinationMenu()
    }

    @objc public func selectNextTestPlan(_ sender: Any?) { session.stepTestPlan(1) }
    @objc public func selectPreviousTestPlan(_ sender: Any?) { session.stepTestPlan(-1) }

    @objc public func selectTestPlanRow(_ sender: Any?) {
        guard let name = (sender as? NSMenuItem)?.representedObject as? String, session.testPlanNames.contains(name) else { return }
        session.activeTestPlan = name
    }

    func validateProductMenuItem(_ item: NSMenuItem) -> Bool? {
        switch item.action {
        case #selector(testAgain(_:)), #selector(testWithoutBuildingAgain(_:)): return session.lastTestRun != nil
        case #selector(testSelectedTests(_:)): return !selectedTests.isEmpty
        case #selector(clearTestResults(_:)): return !session.testResults.isEmpty || session.failedTestCount > 0
        case #selector(compileFile(_:)): return WorkspaceSession.canPerform(.compile, file: editor.fileURL?.path)
        case #selector(analyzeFile(_:)): return WorkspaceSession.canPerform(.analyze, file: editor.fileURL?.path)
        case #selector(preprocessFile(_:)): return WorkspaceSession.canPerform(.preprocess, file: editor.fileURL?.path)
        case #selector(assembleFile(_:)): return WorkspaceSession.canPerform(.assemble, file: editor.fileURL?.path)
        case #selector(archiveProductEditingScheme(_:)): return session.model.kind != .package
        case #selector(selectNextDestination(_:)), #selector(selectPreviousDestination(_:)):
            return destinationMenuModel().selectable.count > 1
        case #selector(selectDestinationRow(_:)):
            let key = item.representedObject as? String
            item.state = key != nil && key == session.destination.map(Self.menuKey(for:)) ? .on : .off
            return key != nil
        case #selector(selectNextTestPlan(_:)), #selector(selectPreviousTestPlan(_:)): return session.testPlanNames.count > 1
        case #selector(selectTestPlanRow(_:)):
            item.state = (item.representedObject as? String ?? item.title) == session.effectiveTestPlan ? .on : .off
            return item.representedObject == nil || session.testPlanNames.contains(item.representedObject as? String ?? "")
        default: return nil
        }
    }
}

extension DynamicMenus {
    static func fillDestinations(_ m: NSMenu, model: DestinationMenuModel, current: Destination?, target: AnyObject?) {
        removeDynamic(m)
        let currentKey = current.map(WorkspaceWindowController.menuKey(for:))
        func row(_ d: Destination, enabled: Bool = true) -> NSMenuItem {
            let i = NSMenuItem(title: DestinationMenuModel.submenuTitle(d), action: enabled ? #selector(WorkspaceWindowController.selectDestinationRow(_:)) : nil,
                               keyEquivalent: "")
            i.target = enabled ? target : nil
            i.representedObject = enabled ? WorkspaceWindowController.menuKey(for: d) : nil
            i.tag = MenuBarDelegate.dynamicTag
            i.state = enabled && WorkspaceWindowController.menuKey(for: d) == currentKey ? .on : .off
            i.isEnabled = enabled
            return i
        }
        for label in ["Devices", "Simulators", "Build"] {
            guard let at = m.items.firstIndex(where: { $0.isSectionHeader && $0.title == label }) else { continue }
            let rows = model.rows(label)
            for (n, d) in rows.enumerated() { m.insertItem(row(d), at: at + 1 + n) }
        }
        if let sub = m.items.first(where: { $0.title == DestinationMenuModel.incompatibleTitle })?.submenu {
            sub.removeAllItems()
            sub.autoenablesItems = false
            for d in model.incompatible { sub.addItem(row(d, enabled: false)) }
        }
    }

    static func fillTestPlans(_ m: NSMenu, rows: [String], plans: [String], active: String, target: AnyObject?) {
        removeDynamic(m)
        let sep = NSMenuItem.separator()
        sep.tag = MenuBarDelegate.dynamicTag
        m.addItem(sep)
        for name in rows {
            let i = NSMenuItem(title: name, action: #selector(WorkspaceWindowController.selectTestPlanRow(_:)), keyEquivalent: "")
            i.target = target
            i.representedObject = plans.contains(name) ? name : nil
            i.tag = MenuBarDelegate.dynamicTag
            i.state = name == active ? .on : .off
            m.addItem(i)
        }
    }
}
