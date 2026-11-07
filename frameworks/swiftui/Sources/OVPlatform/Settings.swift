import Dispatch
import Foundation
#if canImport(Glibc)
import Glibc
#elseif canImport(Darwin)
import Darwin
#endif

public struct PlatformSettings: Sendable, Equatable {
    public var darkAppearance = false
    public var increasedContrast = false
    public var reduceMotion = false
    public var reduceTransparency = false
    public var differentiateWithoutColor = false
    public var invertColors = false
    public var boldText = false
    public var showButtonShapes = false
    public var contentSizeIndex = 3
    public var localeIdentifier = "en_US"
    public var timeZoneIdentifier: String?

    public init() {}

    public static let contentSizeNames = ["xSmall", "small", "medium", "large", "xLarge", "xxLarge", "xxxLarge",
                                          "accessibility1", "accessibility2", "accessibility3", "accessibility4",
                                          "accessibility5"]

    public static func contentSizeIndex(forTextScale s: Double) -> Int {
        let limits = [0.85, 0.9, 0.95, 1.1, 1.2, 1.3, 1.45, 1.6, 1.8, 2.0, 2.3]
        return limits.firstIndex { s < $0 } ?? 11
    }

    @discardableResult
    public mutating func apply(key: String, value raw: String) -> Bool {
        let v = raw.trimmingCharacters(in: .whitespaces).lowercased()
        let on = ["1", "true", "yes", "on", "high", "dark"].contains(v)
        switch key.lowercased() {
        case "color-scheme", "appearance":
            if v == "dark" || v == "prefer-dark" { darkAppearance = true } else if v == "light" || v == "default" { darkAppearance = false }
        case "contrast", "high-contrast": increasedContrast = on || v == "increased"
        case "reduce-motion": reduceMotion = on
        case "reduce-transparency": reduceTransparency = on
        case "differentiate-without-color": differentiateWithoutColor = on
        case "invert-colors": invertColors = on
        case "bold-text": boldText = on
        case "button-shapes": showButtonShapes = on
        case "content-size":
            guard let i = Self.contentSizeNames.firstIndex(where: { $0.lowercased() == v }) else { return false }
            contentSizeIndex = i
        case "text-scale":
            guard let s = Double(v) else { return false }
            contentSizeIndex = Self.contentSizeIndex(forTextScale: s)
        case "locale":
            localeIdentifier = raw.trimmingCharacters(in: .whitespaces)
        default:
            return false
        }
        return true
    }

    public mutating func apply(fileText: String) {
        for line in fileText.split(whereSeparator: \.isNewline) {
            let l = line.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? ""
            guard let eq = l.firstIndex(of: "=") else { continue }
            let k = l[..<eq].trimmingCharacters(in: .whitespaces)
            let v = l[l.index(after: eq)...].trimmingCharacters(in: .whitespaces)
            apply(key: k, value: v)
        }
    }

    public mutating func apply(environment env: [String: String]) {
        let map: [(String, String)] = [
            ("OV_COLOR_SCHEME", "color-scheme"), ("OV_CONTRAST", "contrast"), ("OV_REDUCE_MOTION", "reduce-motion"),
            ("OV_REDUCE_TRANSPARENCY", "reduce-transparency"),
            ("OV_DIFFERENTIATE_WITHOUT_COLOR", "differentiate-without-color"), ("OV_INVERT_COLORS", "invert-colors"),
            ("OV_BOLD_TEXT", "bold-text"), ("OV_BUTTON_SHAPES", "button-shapes"), ("OV_TEXT_SCALE", "text-scale"),
            ("OV_CONTENT_SIZE", "content-size"), ("OV_LOCALE", "locale"),
        ]
        for (name, key) in map { if let v = env[name], !v.isEmpty { apply(key: key, value: v) } }
    }

    public static func localeIdentifier(fromPOSIX env: [String: String]) -> String? {
        for name in ["LC_ALL", "LC_MESSAGES", "LANG"] {
            guard let v = env[name], !v.isEmpty else { continue }
            let id = String(v.split(separator: ".").first ?? "").split(separator: "@").first.map(String.init) ?? ""
            if id == "C" || id == "POSIX" || id.isEmpty { return nil }
            return id
        }
        return nil
    }
}

public enum PlatformSettingsFile {
    public static func path(environment env: [String: String] = ProcessInfo.processInfo.environment) -> String {
        if let p = env["OV_SETTINGS_FILE"], !p.isEmpty { return p }
        let base = env["XDG_CONFIG_HOME"].flatMap { $0.isEmpty ? nil : $0 }
            ?? ((env["HOME"] ?? NSHomeDirectory()) + "/.config")
        return base + "/openviews/settings.conf"
    }
}

@MainActor
public final class SettingsFileWatcher {
    public let path: String
    private let onChange: @MainActor () -> Void
    private var source: (any DispatchSourceProtocol)?
    private var fd: Int32 = -1

    public init(path: String, onChange: @escaping @MainActor () -> Void) {
        self.path = path
        self.onChange = onChange
        start()
    }

    public var isWatching: Bool { source != nil }

    private func start() {
        let dir = (path as NSString).deletingLastPathComponent
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        #if os(Linux)
        let ifd = inotify_init1(Int32(IN_NONBLOCK | IN_CLOEXEC))
        guard ifd >= 0 else { return }
        let mask = UInt32(IN_CLOSE_WRITE | IN_MOVED_TO | IN_CREATE | IN_DELETE | IN_MODIFY)
        guard inotify_add_watch(ifd, dir, mask) >= 0 else {
            close(ifd)
            return
        }
        fd = ifd
        let name = (path as NSString).lastPathComponent
        let s = DispatchSource.makeReadSource(fileDescriptor: ifd, queue: .main)
        s.setEventHandler { [weak self] in
            var buf = [UInt8](repeating: 0, count: 4096)
            var relevant = false
            while true {
                let n = buf.withUnsafeMutableBytes { read(ifd, $0.baseAddress, 4096) }
                if n <= 0 { break }
                var off = 0
                while off + 16 <= n {
                    let len = Int(buf[off + 12]) | Int(buf[off + 13]) << 8 | Int(buf[off + 14]) << 16 | Int(buf[off + 15]) << 24
                    let nameBytes = buf[(off + 16)..<min(n, off + 16 + len)].prefix { $0 != 0 }
                    if String(decoding: nameBytes, as: UTF8.self) == name { relevant = true }
                    off += 16 + len
                }
            }
            if relevant { MainActor.assumeIsolated { self?.onChange() } }
        }
        s.setCancelHandler { close(ifd) }
        s.resume()
        source = s
        #else
        let dfd = open(dir, O_EVTONLY)
        guard dfd >= 0 else { return }
        fd = dfd
        let s = DispatchSource.makeFileSystemObjectSource(fileDescriptor: dfd, eventMask: [.write, .rename, .delete, .extend],
                                                          queue: .main)
        s.setEventHandler { [weak self] in MainActor.assumeIsolated { self?.onChange() } }
        s.setCancelHandler { close(dfd) }
        s.resume()
        source = s
        #endif
    }

    public func stop() {
        source?.cancel()
        source = nil
    }
}

@MainActor
public final class DesktopSettingsReader {
    public private(set) var current: PlatformSettings
    public private(set) var sources: [String] = []
    private let env: [String: String]
    private var watcher: SettingsFileWatcher?
    private var portal: PortalSettings?
    private var portalValues: [String: String] = [:]
    public var systemDark: Bool? { didSet { if oldValue != systemDark { recompute() } } }
    public var onChange: (@MainActor (PlatformSettings) -> Void)?

    public init(environment: [String: String] = ProcessInfo.processInfo.environment, usePortal: Bool? = nil,
                watchFile: Bool = true) {
        env = environment
        current = PlatformSettings()
        let portalWanted = usePortal ?? (environment["OV_SETTINGS_PORTAL"] != "0" && environment["DBUS_SESSION_BUS_ADDRESS"] != nil)
        if portalWanted, let p = PortalSettings() {
            portal = p
            portalValues = p.readAll()
            p.monitor { [weak self] key, value in
                self?.portalValues[key] = value
                self?.recompute()
            }
        }
        if watchFile {
            watcher = SettingsFileWatcher(path: PlatformSettingsFile.path(environment: environment)) { [weak self] in
                self?.recompute()
            }
        }
        current = compute()
    }

    public var settingsFilePath: String { PlatformSettingsFile.path(environment: env) }

    public func recompute() {
        let new = compute()
        guard new != current else { return }
        current = new
        onChange?(new)
    }

    private func compute() -> PlatformSettings {
        var s = PlatformSettings()
        var used: [String] = []
        if let l = PlatformSettings.localeIdentifier(fromPOSIX: env) {
            s.localeIdentifier = l
            used.append("posix-locale")
        }
        if let dark = systemDark {
            s.darkAppearance = dark
            used.append("sdl-theme")
        }
        if !portalValues.isEmpty {
            used.append("portal")
            if let v = portalValues["org.freedesktop.appearance color-scheme"] {
                if v == "1" { s.darkAppearance = true } else if v == "2" { s.darkAppearance = false }
            }
            if portalValues["org.freedesktop.appearance contrast"] == "1" { s.increasedContrast = true }
            if portalValues["org.gnome.desktop.a11y.interface high-contrast"] == "true" { s.increasedContrast = true }
            if portalValues["org.gnome.desktop.interface enable-animations"] == "false" { s.reduceMotion = true }
            if let f = portalValues["org.gnome.desktop.interface text-scaling-factor"].flatMap(Double.init) {
                s.contentSizeIndex = PlatformSettings.contentSizeIndex(forTextScale: f)
            }
        }
        let path = settingsFilePath
        if let text = try? String(contentsOfFile: path, encoding: .utf8) {
            s.apply(fileText: text)
            used.append("file")
        }
        var e = PlatformSettings()
        e.apply(environment: env)
        if e != PlatformSettings() || env.keys.contains(where: { $0.hasPrefix("OV_") }) {
            let before = s
            s.apply(environment: env)
            if s != before { used.append("environment") }
        }
        sources = used
        return s
    }

    public func stop() {
        watcher?.stop()
        portal?.stop()
    }
}

nonisolated(unsafe) private var portalMonitorPID: pid_t = 0
nonisolated(unsafe) private var portalMonitorExitHandlerInstalled = false

@MainActor
package final class PortalSettings {
    static let namespaces = ["org.freedesktop.appearance", "org.gnome.desktop.interface", "org.gnome.desktop.a11y.interface"]
    static let keys: Set<String> = ["org.freedesktop.appearance color-scheme", "org.freedesktop.appearance contrast",
                                    "org.gnome.desktop.interface text-scaling-factor",
                                    "org.gnome.desktop.interface enable-animations",
                                    "org.gnome.desktop.a11y.interface high-contrast"]
    let tool: String
    private var monitorProcess: Process?
    private var buffer = ""

    init?() {
        let candidates = ["/usr/bin/gdbus", "/bin/gdbus", "/usr/local/bin/gdbus"]
        guard let t = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else { return nil }
        tool = t
    }

    private func run(_ args: [String], timeout: TimeInterval = 2) -> String? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: tool)
        p.arguments = args
        let out = Pipe()
        p.standardOutput = out
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return nil }
        let deadline = Date().addingTimeInterval(timeout)
        while p.isRunning && Date() < deadline { usleep(5_000) }
        if p.isRunning {
            p.terminate()
            return nil
        }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        return p.terminationStatus == 0 ? String(decoding: data, as: UTF8.self) : nil
    }

    func readAll() -> [String: String] {
        let list = "[" + Self.namespaces.map { "'\($0)'" }.joined(separator: ", ") + "]"
        guard let text = run(["call", "--session", "--dest", "org.freedesktop.portal.Desktop",
                              "--object-path", "/org/freedesktop/portal/desktop",
                              "--method", "org.freedesktop.portal.Settings.ReadAll", list]) else { return [:] }
        return Self.parseReadAll(text)
    }

    package static func parseReadAll(_ text: String) -> [String: String] {
        var out: [String: String] = [:]
        var namespace: String?
        var i = text.startIndex
        var depth = 0
        while i < text.endIndex {
            let c = text[i]
            if c == "{" { depth += 1 } else if c == "}" { depth -= 1 }
            if c == "'" {
                guard let end = text[text.index(after: i)...].firstIndex(of: "'") else { break }
                let word = String(text[text.index(after: i)..<end])
                i = text.index(after: end)
                if depth == 1 {
                    namespace = word
                } else if depth == 2, let ns = namespace,
                          let lt = text[i...].firstIndex(of: "<"), let gt = text[lt...].firstIndex(of: ">") {
                    out["\(ns) \(word)"] = normalise(String(text[text.index(after: lt)..<gt]))
                    i = text.index(after: gt)
                }
                continue
            }
            i = text.index(after: i)
        }
        return out.filter { keys.contains($0.key) }
    }

    static func normalise(_ v: String) -> String {
        let parts = v.trimmingCharacters(in: CharacterSet(charactersIn: "<> ")).split(separator: " ")
        return String(parts.last ?? "").trimmingCharacters(in: CharacterSet(charactersIn: "'<>"))
    }

    package static func parseSignal(_ line: String) -> (String, String)? {
        guard line.contains("SettingChanged"), let open = line.firstIndex(of: "(") else { return nil }
        let words = line[open...].split(separator: "'").enumerated().filter { $0.offset % 2 == 1 }.map { String($0.element) }
        guard words.count >= 2, let lt = line.lastIndex(of: "<"), let gt = line.lastIndex(of: ">"), lt < gt else { return nil }
        return ("\(words[0]) \(words[1])", normalise(String(line[line.index(after: lt)..<gt])))
    }

    func monitor(_ handler: @escaping @MainActor (String, String) -> Void) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: tool)
        p.arguments = ["monitor", "--session", "--dest", "org.freedesktop.portal.Desktop",
                       "--object-path", "/org/freedesktop/portal/desktop"]
        let out = Pipe()
        p.standardOutput = out
        p.standardError = FileHandle.nullDevice
        out.fileHandleForReading.readabilityHandler = { [weak self] h in
            let data = h.availableData
            guard !data.isEmpty else {
                h.readabilityHandler = nil
                return
            }
            let s = String(decoding: data, as: UTF8.self)
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.buffer += s
                    while let nl = self.buffer.firstIndex(of: "\n") {
                        let line = String(self.buffer[..<nl])
                        self.buffer.removeSubrange(...nl)
                        if let (k, v) = Self.parseSignal(line), Self.keys.contains(k) { handler(k, v) }
                    }
                }
            }
        }
        do {
            try p.run()
            monitorProcess = p
            portalMonitorPID = p.processIdentifier
            if !portalMonitorExitHandlerInstalled {
                portalMonitorExitHandlerInstalled = true
                atexit {
                    if portalMonitorPID > 0 { kill(portalMonitorPID, SIGTERM) }
                }
            }
        } catch {
            out.fileHandleForReading.readabilityHandler = nil
        }
    }

    func stop() {
        monitorProcess?.terminate()
        monitorProcess = nil
        portalMonitorPID = 0
    }
}
