import Foundation
import Observation
import SwiftCodeDeviceModel
import SwiftCodeIDECore
import SwiftCodePreviews

@MainActor
@Observable
public final class PreviewCanvasShellModel {
    public enum LayoutChoice: Int, Sendable { case automatic, right, bottom }

    public enum State: Equatable, Sendable {
        case empty(String)
        case starting(String)
        case rendered
        case failed(title: String, message: String, issues: [PreviewIssue])
        case needsSimulator(title: String, message: String)
    }

    public struct Tile: Equatable, Identifiable, Sendable {
        public var id: Int
        public var preview: Int
        public var title: String
        public var caption: String
        public var variant: PreviewVariant
        public var requested: CGSize
        public var image: URL?
        public var size: CGSize
        public var isDevice: Bool
        public var crop: CGRect?
        public var screen: CGSize?
    }

    public struct Banner: Equatable, Sendable {
        public var title: String
        public var issues: [PreviewIssue]
        public var message: String?
    }

    public struct Timing: Equatable, Sendable {
        public var reason: String
        public var decision: String
        public var compile: Double
        public var render: Double
        public var total: Double
        public var summary: String {
            String(format: "%@ (%@): compile %.2f, render %.2f, total %.2f s", reason, decision, compile, render, total)
        }
    }

    @ObservationIgnored public var makeEngine: () -> PreviewCanvasEngine? = { nil }
    @ObservationIgnored public var makeSimulatorEngine: () -> PreviewCanvasEngine? = { nil }
    @ObservationIgnored public var locator: () -> PreviewModuleLocator? = { nil }
    @ObservationIgnored public var reveal: (String, Int) -> Void = { _, _ in }
    @ObservationIgnored public var refreshDelay: TimeInterval = 0.15

    public private(set) var isModeOn = true
    public var layoutChoice: LayoutChoice = .automatic
    public private(set) var path: String?
    public private(set) var previews: [PreviewDeclaration] = []
    public private(set) var isPaused = true
    public private(set) var state: State = .empty("No Previews")
    public private(set) var tiles: [Tile] = []
    public private(set) var selectedIndex = 0
    public private(set) var isGrid = false
    public private(set) var mode: PreviewCanvasMode = .live
    public private(set) var variantKind: PreviewVariantKind?
    public private(set) var zoom: CGFloat?
    public private(set) var settings = PreviewCanvasSettings()
    public private(set) var deviceTypeID: String?
    public private(set) var isUpdating = false
    public private(set) var progressText = ""
    public private(set) var banner: Banner?
    public private(set) var timings: [Timing] = []
    public private(set) var usesSimulator = false

    @ObservationIgnored private var text = ""
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var debounce: Task<Void, Never>?
    @ObservationIgnored private var updateTask: Task<Void, Never>?
    @ObservationIgnored private var engine: PreviewCanvasEngine?
    @ObservationIgnored private var simulatorEngine: PreviewCanvasEngine?
    @ObservationIgnored private var editStart: Date?

    public static let zoomSteps: [CGFloat] = [0.25, 0.5, 0.75, 1, 1.5, 2]
    public static let devices: [DeviceFrameSpec] = [.iPhone18Pro, .iPhoneDuo, .iPadA16, .iPadPro13M5]
    public static let automaticDevice = DeviceFrameSpec.iPhone18Pro

    public init() {}

    public var isShown: Bool { isModeOn && path != nil }

    public var pendingUpdate: Task<Void, Never>? { updateTask }
    public var pendingDebounce: Task<Void, Never>? { debounce }

    public var device: DeviceFrameSpec { Self.devices.first { $0.typeID == deviceTypeID } ?? Self.automaticDevice }
    public var screen: CGSize { device.panels[0].uprightPointSize }
    public var deviceTitle: String { deviceTypeID == nil ? "Automatic – \(Self.automaticDevice.name)" : device.name }
    public var tabTitles: [String] { previews.map(\.tabTitle) }
    public var zoomTitle: String { zoom.map { "\(Int(($0 * 100).rounded()))%" } ?? "Fit" }
    public var statusText: String {
        if isPaused { return "" }
        switch state {
        case .starting(let t): return t
        case .failed: return "Build failed"
        case .needsSimulator: return "Needs a simulator host"
        case .empty(let m): return m
        case .rendered: return isUpdating ? "Updating…" : grid ? "\(previews.count) preview\(previews.count == 1 ? "" : "s")" : ""
        }
    }
    private var grid: Bool { isGrid }

    public func placement(forWidth width: CGFloat) -> CanvasPlacement {
        switch layoutChoice {
        case .automatic: CanvasPlacement.placement(forWidth: width)
        case .right: .beside
        case .bottom: .below
        }
    }

    public func focus(path newPath: String?, text newText: String?) {
        let has = newPath.map { CanvasAutoShow.hasPreviews(fileName: ($0 as NSString).lastPathComponent, text: newText ?? "") } ?? false
        let changed = newPath != path
        let same = !changed && text == (newText ?? "")
        text = newText ?? ""
        if !has {
            if path != nil { path = nil; previews = []; tiles = []; banner = nil; state = .empty("No Previews") }
            return
        }
        path = newPath
        let list = PreviewDiscovery.previews(in: text)
        previews = list
        if changed {
            selectedIndex = 0
            tiles = []
            banner = nil
            state = .empty("")
        }
        if selectedIndex >= list.count { selectedIndex = 0 }
        usesSimulator = Self.needsSimulator(text: text, previews: list)
        if !isPaused, !same { update(reason: changed ? "open" : "refresh") }
    }

    public func edited(path p: String, text newText: String) {
        guard p == path || CanvasAutoShow.hasPreviews(fileName: (p as NSString).lastPathComponent, text: newText) else { return }
        if p != path { focus(path: p, text: newText); return }
        text = newText
        let list = PreviewDiscovery.previews(in: newText)
        if list.isEmpty { focus(path: p, text: newText); return }
        previews = list
        if selectedIndex >= list.count { selectedIndex = 0 }
        usesSimulator = Self.needsSimulator(text: newText, previews: list)
        guard !isPaused, isModeOn else { return }
        if editStart == nil { editStart = Date() }
        debounce?.cancel()
        let delay = refreshDelay
        debounce = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1e9))
            guard !Task.isCancelled, let self else { return }
            self.update(reason: "edit")
        }
    }

    public static func needsSimulator(text: String, previews: [PreviewDeclaration]) -> Bool {
        PreviewDiscovery.needsUIKit(text: text, previews: previews)
    }

    public func toggleMode() {
        isModeOn.toggle()
        if isModeOn, !isPaused, path != nil { update(reason: "canvas") }
    }

    public func resume() {
        guard isPaused else { return }
        isPaused = false
        update(reason: "resume")
    }

    public func select(_ index: Int) {
        guard previews.indices.contains(index) else { return }
        selectedIndex = index
        isGrid = false
        relayout()
    }

    public func setMode(_ m: PreviewCanvasMode) {
        switch m {
        case .live, .selectable: mode = m
        case .grid:
            isGrid.toggle()
            if isGrid { variantKind = nil }
            relayout()
        case .variants:
            let all = PreviewVariantKind.allCases
            setVariants(variantKind.flatMap { all.firstIndex(of: $0) }.map { $0 + 1 < all.count ? all[$0 + 1] : nil } ?? all.first)
        }
    }

    public func setVariants(_ kind: PreviewVariantKind?) {
        variantKind = kind
        if kind != nil { isGrid = false }
        relayout()
    }

    public func setZoom(_ z: CGFloat?) { zoom = z }

    public func setSetting(_ name: String, _ on: Bool) {
        if on { settings.on.insert(name) } else { settings.on.remove(name) }
        if ["Color Scheme", "Orientation", "Dynamic Type"].contains(name) { relayout() }
    }

    public func chooseDevice(_ typeID: String?) {
        deviceTypeID = typeID
        relayout()
    }

    public func setLayout(_ choice: LayoutChoice) { layoutChoice = choice }

    public func tileClicked(_ tile: Tile) {
        if selectedIndex != tile.preview, isGrid { selectedIndex = tile.preview }
        if mode == .selectable, let path, previews.indices.contains(tile.preview) { reveal(path, previews[tile.preview].line) }
    }

    public func open(_ issue: PreviewIssue) {
        guard let f = issue.file else { return }
        reveal(f.path, issue.line)
    }

    public func stop() {
        debounce?.cancel()
        updateTask?.cancel()
        engine?.stop()
        simulatorEngine?.stop()
    }

    public var baseVariant: PreviewVariant {
        PreviewVariant(colorScheme: settings.on.contains("Color Scheme") ? "dark" : "light",
                       dynamicType: settings.on.contains("Dynamic Type") ? "accessibility1" : nil,
                       orientation: settings.on.contains("Orientation") ? .landscapeLeft : nil)
    }

    public func plannedTiles() -> [Tile] {
        guard !previews.isEmpty else { return [] }
        let base = baseVariant
        func tile(_ id: Int, _ i: Int, _ v: PreviewVariant, caption: String) -> Tile {
            let p = previews[i]
            var variant = v
            if variant.orientation == nil, p.orientation != .portrait { variant.orientation = p.orientation.rawValue }
            let size: CGSize = p.layout == .sizeThatFits ? .zero : PreviewScreenLayout.tileSize(p, screen: screen, variant: variant)
            return Tile(id: id, preview: i, title: tabTitles[i], caption: caption, variant: variant, requested: size, image: nil,
                        size: size, isDevice: p.layout == .device, crop: nil, screen: nil)
        }
        let sel = min(max(selectedIndex, 0), previews.count - 1)
        if isGrid { return previews.indices.map { tile($0, $0, base, caption: "") } }
        if let kind = variantKind {
            return kind.variants(base: base).enumerated().map { tile($0.offset, sel, $0.element, caption: $0.element.label) }
        }
        return [tile(0, sel, base, caption: "")]
    }

    private func relayout() {
        guard !isPaused, isShown else { return }
        update(reason: "layout")
    }

    public func update(reason: String) {
        guard isShown, !isPaused, let path else { return }
        debounce?.cancel()
        let start = reason == "edit" ? (editStart ?? Date()) : Date()
        editStart = nil
        let planned = plannedTiles()
        guard !planned.isEmpty else { state = .empty("No Previews"); return }
        let eng: PreviewCanvasEngine
        if usesSimulator {
            if simulatorEngine == nil { simulatorEngine = makeSimulatorEngine() }
            guard let s = simulatorEngine else {
                tiles = []
                banner = nil
                state = .needsSimulator(title: Self.needsSimulatorTitle, message: Self.needsSimulatorMessage)
                return
            }
            eng = s
        } else {
            if engine == nil { engine = makeEngine() }
            guard let e = engine else { state = .failed(title: "Previews are not available", message: "No preview engine.", issues: []); return }
            eng = e
        }
        guard let locator = locator() else { return }
        generation += 1
        let g = generation
        if case .rendered = state {
            if tiles.map(\.preview) != planned.map(\.preview) || tiles.map(\.variant) != planned.map(\.variant) {
                tiles = zip(planned, planned.indices).map { t, i in
                    var t = t
                    if let old = tiles.first(where: { $0.preview == t.preview && $0.variant == t.variant }) ?? (i < tiles.count && tiles[i].preview == t.preview ? tiles[i] : nil) {
                        (t.image, t.size, t.crop, t.screen) = (old.image, old.size, old.crop, old.screen)
                    }
                    return t
                }
            }
        } else {
            state = .starting(usesSimulator ? "Starting the preview device" : "Preparing the preview")
        }
        isUpdating = true
        let request = PreviewCanvasRequest(file: URL(fileURLWithPath: path), text: text, previews: previews,
                                           tiles: planned.map { PreviewCanvasTileRequest(preview: $0.preview, variant: $0.variant, size: $0.requested) },
                                           locator: locator, deviceTypeID: device.typeID, screen: screen)
        let progress: @Sendable (String) -> Void = { [weak self] text in
            Task { @MainActor in if self?.generation == g { self?.noteProgress(text) } }
        }
        updateTask = Task { [weak self] in
            let result = await eng.update(request, generation: g, progress: progress)
            guard let self, g == self.generation, let result else { return }
            self.finish(result, planned: planned, reason: reason, start: start)
        }
    }

    private func noteProgress(_ text: String) {
        progressText = text
        if case .starting = state { state = .starting(text) }
    }

    private func finish(_ result: Result<PreviewCanvasOutcome, PreviewFailure>, planned: [Tile], reason: String, start: Date) {
        isUpdating = false
        progressText = ""
        switch result {
        case .success(let o):
            tiles = planned.enumerated().map { i, t in
                var t = t
                if i < o.pictures.count { t.image = o.pictures[i]; t.size = o.sizes[i] }
                if let c = o.crops, i < c.count { t.crop = c[i]; t.screen = o.screen }
                return t
            }
            banner = nil
            state = .rendered
            let timing = Timing(reason: reason, decision: o.decision, compile: o.compile, render: o.render, total: Date().timeIntervalSince(start))
            timings.append(timing)
            if timings.count > 100 { timings.removeFirst(timings.count - 100) }
        case .failure(.unsupported(let why)) where usesSimulator:
            tiles = []
            banner = nil
            state = .needsSimulator(title: "UIKit Previews Need Setup", message: why)
        case .failure(let f):
            let title = f.issues.isEmpty ? (Self.isHostFailure(f) ? "The preview host failed" : "Preview failed") : "Compiling the preview failed"
            if case .rendered = state, tiles.contains(where: { $0.image != nil }) {
                banner = Banner(title: title, issues: Array(f.issues.prefix(3)), message: f.issues.isEmpty ? f.description : nil)
            } else {
                tiles = []
                state = .failed(title: f.issues.isEmpty ? "Preview build failed" : "Compiling the preview failed", message: f.description,
                                issues: Array(f.issues.prefix(3)))
            }
        }
    }

    private static func isHostFailure(_ f: PreviewFailure) -> Bool { if case .host = f { return true }; return false }

    public static let needsSimulatorTitle = "Needs a Simulator Host"
    public static let needsSimulatorMessage = "UIKit previews run in SwiftCode's iOS simulator, on an arm64 Linux simulator host. "
        + "Pair one with swiftcode sim remote pair (Window ▸ Downloads checks it), then choose Check Again. SwiftUI previews render here without one."

    public static let gap: CGFloat = 24
    public static let captionHeight: CGFloat = 18

    public func fitZoom(area: CGSize) -> CGFloat { Self.arrange(tiles, area: area, zoom: nil).zoom }

    public func frames(area: CGSize) -> (frames: [CGRect], size: CGSize, zoom: CGFloat) { Self.arrange(tiles, area: area, zoom: zoom) }

    public static func arrange(_ tiles: [Tile], area: CGSize, zoom: CGFloat?) -> (frames: [CGRect], size: CGSize, zoom: CGFloat) {
        guard !tiles.isEmpty else { return ([], .zero, zoom ?? 1) }
        let sizes = tiles.map { $0.size.width > 0 && $0.size.height > 0 ? $0.size : CGSize(width: 200, height: 120) }
        let n = tiles.count
        func layout(cols: Int, z: CGFloat) -> ([CGRect], CGSize) {
            var frames: [CGRect] = []
            var y = gap, width: CGFloat = 0
            var i = 0
            while i < n {
                let row = Array(i..<min(i + cols, n))
                let h = row.map { sizes[$0].height * z }.max() ?? 0
                var x = gap
                for k in row {
                    let s = CGSize(width: sizes[k].width * z, height: sizes[k].height * z)
                    frames.append(CGRect(x: x, y: y + captionHeight, width: s.width, height: s.height))
                    x += s.width + gap
                }
                width = max(width, x)
                y += captionHeight + h + gap
                i += cols
            }
            return (frames, CGSize(width: width, height: y))
        }
        if let z = zoom {
            var cols = n
            while cols > 1, layout(cols: cols, z: z).1.width > area.width { cols -= 1 }
            let (f, s) = layout(cols: cols, z: z)
            return (f, s, z)
        }
        var best = (cols: 1, zoom: CGFloat(0.1))
        for cols in 1...n {
            let (_, s1) = layout(cols: cols, z: 1)
            let w = s1.width - gap * CGFloat(min(cols, n) + 1), h = s1.height - (gap + captionHeight) * CGFloat((n + cols - 1) / cols) - gap
            let zw = (area.width - gap * CGFloat(min(cols, n) + 1)) / max(w, 1)
            let zh = (area.height - (gap + captionHeight) * CGFloat((n + cols - 1) / cols) - gap) / max(h, 1)
            let z = max(0.1, min(1, zw, zh))
            if z >= best.zoom - 1e-9 { best = (cols, z) }
        }
        let (f, s) = layout(cols: best.cols, z: best.zoom)
        return (f, s, best.zoom)
    }
}
