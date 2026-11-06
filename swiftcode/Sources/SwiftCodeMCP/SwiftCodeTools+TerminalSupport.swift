#if canImport(AppKit)
import AppKit
#endif
#if canImport(CoreGraphics)
import CoreGraphics
#endif
#if canImport(Glibc)
import Glibc
#elseif canImport(Darwin)
import Darwin
#endif
#if canImport(ImageIO)
import ImageIO
#endif
#if canImport(ScreenCaptureKit)
import ScreenCaptureKit
#endif
#if canImport(UniformTypeIdentifiers)
import UniformTypeIdentifiers
#endif
#if canImport(UserNotifications)
import UserNotifications
#endif
import Foundation
import SwiftCodeAssistant
import SwiftCodeIDECore

/// Shared helpers for the ported Legacy Terminal / system tool family
/// (Wave 4). See `SwiftCodeTools+Terminal.swift` for the tools themselves.
///
/// Behaviour source: Legacy's `AssistSystemTool`,
/// `AssistAppInteractionEngine` (list/launch/window parts only),
/// `AssistScreenCaptureEngine` (fullscreen capture + PNG encode),
/// `AssistSystemNotificationTool` (UN + osascript fallback),
/// `AgentTerminalService` (timeout, environment) and
/// `AssistExecutionFunctions` (the four registered tasks) — Dylan's
/// own code, ported under MIT.
///
/// The rules that matter:
///
/// * Fixed-argv subprocesses only, never a shell
///   (`terminalRunFixed`). The runner reads stdout/stderr on
///   separate paths (a full pipe never blocks the child, as in
///   `Subprocess.run`) and terminates the child when the timeout
///   expires. It returns `nil` only when the process cannot start.
///   Callers run it off the main actor (`Task.detached`), because
///   it blocks.
/// * `use_terminal` tokenizes its `command` string into an argv
///   vector (`terminalTokenizeCommand`); any shell metacharacter
///   anywhere in the string is rejected, so pipes, redirects,
///   variables, globbing, substitution and chaining can never run.
///   The program is resolved against `PATH`
///   (`terminalResolveProgram`).
/// * The macOS-only helpers (pasteboard, notifications, screen
///   capture, app control, sysctl) have throwing stubs on other
///   platforms: they fail with an exact "only available on macOS"
///   message, never a silent no-op.
extension SwiftCodeMCPHost {
    /// Throws unless this is macOS.
    nonisolated static func terminalRequireMacOS(_ tool: String) throws {
#if os(macOS)
#else
        throw MCPToolError("\(tool) is only available on macOS.")
#endif
    }

    // MARK: - Fixed-argv runner

    /// The environment a terminal/system subprocess runs with: this
    /// process's environment, plus the never-wait-for-a-person
    /// settings, plus the developer-tool paths Legacy's
    /// `AgentTerminalService` appends to `PATH`. Nothing is removed:
    /// unlike the git tools, an arbitrary command's environment is
    /// the user's own.
    nonisolated static func terminalEnvironment() -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        env["GIT_TERMINAL_PROMPT"] = "0"
        let extra = ":/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        if let path = env["PATH"], !path.isEmpty {
            if !path.contains("/usr/local/bin") { env["PATH"] = path + extra }
        } else {
            env["PATH"] = "/usr/bin:/bin:/usr/sbin:/sbin" + extra
        }
        return env
    }

    /// Runs `executable` with `args` as an argument vector (never a
    /// shell), capturing stdout and stderr, and terminating the child
    /// when `timeout` seconds pass. `nil` when the process cannot
    /// start at all.
    nonisolated static func terminalRunFixed(_ executable: String, _ args: [String],
                                            workingDirectory: URL? = nil,
                                            environment: [String: String]? = nil,
                                            timeout: TimeInterval) -> TerminalFixedRun? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: executable)
        p.arguments = args
        if let environment { p.environment = environment }
        if let workingDirectory { p.currentDirectoryURL = workingDirectory }
        let outPipe = Pipe(), errPipe = Pipe()
        p.standardOutput = outPipe
        p.standardError = errPipe
        p.standardInput = FileHandle.nullDevice
        do { try p.run() } catch { return nil }
        // stderr on its own thread: reading the two pipes one after
        // the other deadlocks when the child fills the second one
        // first (the `Subprocess.run` shape).
        final class Box: @unchecked Sendable { var data = Data() }
        let errBox = Box()
        let group = DispatchGroup()
        group.enter()
        Thread { errBox.data = errPipe.fileHandleForReading.readDataToEndOfFile(); group.leave() }.start()
        final class Flag: @unchecked Sendable { var value = false }
        let timedOut = Flag()
        let watchdog = DispatchWorkItem {
            if p.isRunning { timedOut.value = true; p.terminate() }
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: watchdog)
        let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
        group.wait()
        p.waitUntilExit()
        watchdog.cancel()
        return TerminalFixedRun(exitCode: p.terminationStatus,
                                stdout: String(decoding: outData, as: UTF8.self),
                                stderr: String(decoding: errBox.data, as: UTF8.self),
                                timedOut: timedOut.value)
    }

    /// Whether `text` matches `pattern` (a full regular-expression
    /// match, as Legacy's `use_system.matches`).
    nonisolated static func terminalMatches(_ text: String, pattern: String) -> Bool {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return false }
        let range = NSRange(text.startIndex..., in: text)
        return re.firstMatch(in: text, range: range) != nil
    }

    /// Caps tool output at `cap` characters with Legacy's canonical
    /// truncation marker; returns the (possibly capped) text and
    /// whether it was capped.
    nonisolated static func terminalCappedOutput(_ output: String, cap: Int = 8_000) -> (String, Bool) {
        guard output.count > cap else { return (output, false) }
        return (String(output.prefix(cap)) + "\n…[truncated: output exceeded \(cap) characters]", true)
    }

    // MARK: - `use_terminal` argv

    /// Splits a `use_terminal` command string into an argv vector.
    /// Single/double quotes group words and a backslash escapes the
    /// next character; there is no variable expansion, no globbing,
    /// no substitution, and no chaining. `nil` when the string is
    /// empty, has an unterminated quote, or contains any shell
    /// metacharacter anywhere (`| & ; < > \` $ ( ) { } * ? ~ # !`
    /// or a newline): shell syntax is rejected, never reinterpreted.
    nonisolated static func terminalTokenizeCommand(_ command: String) -> [String]? {
        let meta: Set<Character> = ["|", "&", ";", "<", ">", "`", "$", "(", ")", "{", "}", "*", "?", "~", "#", "!", "\n", "\r"]
        if command.contains(where: { meta.contains($0) }) { return nil }
        var tokens: [String] = []
        var current = ""
        var hasCurrent = false
        var quote: Character?
        var i = command.startIndex
        while i < command.endIndex {
            let c = command[i]
            if let q = quote {
                if c == q { quote = nil } else { current.append(c) }
            } else if c == "'" || c == "\"" {
                quote = c
                hasCurrent = true
            } else if c == "\\" {
                let n = command.index(after: i)
                guard n < command.endIndex else { return nil }
                current.append(command[n])
                hasCurrent = true
                i = n
            } else if c.isWhitespace {
                if hasCurrent { tokens.append(current); current = ""; hasCurrent = false }
            } else {
                current.append(c)
                hasCurrent = true
            }
            i = command.index(after: i)
        }
        guard quote == nil else { return nil }
        if hasCurrent { tokens.append(current) }
        return tokens.isEmpty ? nil : tokens
    }

    /// Resolves a program name to an executable path: a name
    /// containing `/` is a path (absolute as-is, relative against
    /// `workingDirectory`); otherwise the first executable match on
    /// `PATH`. `nil` when nothing executable is found.
    nonisolated static func terminalResolveProgram(_ name: String, workingDirectory: URL) -> String? {
        if name.contains("/") {
            let url: URL
            if name.hasPrefix("/") {
                url = URL(fileURLWithPath: name).standardizedFileURL
            } else {
                url = workingDirectory.appendingPathComponent(name).standardizedFileURL
            }
            return FileManager.default.isExecutableFile(atPath: url.path) ? url.path : nil
        }
        let pathEnv = ProcessInfo.processInfo.environment["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
        for dir in pathEnv.split(separator: ":") {
            let candidate = (dir.isEmpty ? "." : String(dir)) + "/" + name
            if FileManager.default.isExecutableFile(atPath: candidate) { return candidate }
        }
        return nil
    }

    // MARK: - `use_system` connectivity (POSIX TCP connect)

    /// Bounded TCP connect: non-blocking connect + poll() with the
    /// requested timeout. Legacy's `AssistSystemTool.tcpConnect`,
    /// with the `SOCK_STREAM` spelling this repository's
    /// `HostResolver` uses on Glibc.
    nonisolated static func terminalTCPConnect(host: String, port: Int, timeoutSeconds: TimeInterval) -> Bool {
        var hints = addrinfo()
#if canImport(Glibc)
        hints.ai_socktype = Int32(SOCK_STREAM.rawValue)
#else
        hints.ai_socktype = SOCK_STREAM
#endif
        var info: UnsafeMutablePointer<addrinfo>?
        guard getaddrinfo(host, "\(port)", &hints, &info) == 0, let list = info else { return false }
        defer { freeaddrinfo(list) }
        let fd = socket(list.pointee.ai_family, list.pointee.ai_socktype, list.pointee.ai_protocol)
        guard fd >= 0 else { return false }
        defer { close(fd) }
        let flags = fcntl(fd, F_GETFL, 0)
        _ = fcntl(fd, F_SETFL, flags | O_NONBLOCK)
        guard let aiAddr = list.pointee.ai_addr else { return false }
        let rc = connect(fd, aiAddr, list.pointee.ai_addrlen)
        if rc == 0 { return true }
        guard errno == EINPROGRESS else { return false }
        var pfd = pollfd(fd: fd, events: Int16(POLLOUT), revents: 0)
        let timeoutMs = Int32(timeoutSeconds * 1000)
        let ready = poll(&pfd, 1, timeoutMs)
        guard ready > 0, (pfd.revents & Int16(POLLOUT)) != 0 else { return false }
        var soError: Int32 = 0
        var len = socklen_t(MemoryLayout<Int32>.size)
        guard getsockopt(fd, SOL_SOCKET, SO_ERROR, &soError, &len) == 0 else { return false }
        return soError == 0
    }

    // MARK: - `use_system` sysctl

#if os(macOS)
    /// Reads one allowlisted sysctl by name (Legacy's
    /// `AssistSystemTool.readSysctl`). macOS only.
    nonisolated static func terminalSysctl(_ name: String, kind: TerminalSysctlKind) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        switch kind {
        case .string:
            var buffer = [CChar](repeating: 0, count: size + 1)
            guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return nil }
            return String(cString: buffer)
        case .int32:
            var value: Int32 = 0
            var len = MemoryLayout<Int32>.size
            guard sysctlbyname(name, &value, &len, nil, 0) == 0 else { return nil }
            return "\(value)"
        case .uint64:
            var value: UInt64 = 0
            var len = MemoryLayout<UInt64>.size
            guard sysctlbyname(name, &value, &len, nil, 0) == 0 else { return nil }
            return "\(value)"
        }
    }
#endif

    // MARK: - Clipboard (macOS NSPasteboard)

#if canImport(AppKit)
    /// The macOS system clipboard's text ("" when empty), as Legacy's
    /// `AssistClipboardManagerTool` reads it.
    func terminalPasteboardRead() throws -> String {
        NSPasteboard.general.string(forType: .string) ?? ""
    }

    /// Replaces the macOS system clipboard's text.
    func terminalPasteboardWrite(_ content: String) throws {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(content, forType: .string)
    }
#else
    func terminalPasteboardRead() throws -> String {
        throw MCPToolError("clipboard_manager_tool is only available on macOS (NSPasteboard).")
    }

    func terminalPasteboardWrite(_ content: String) throws {
        throw MCPToolError("clipboard_manager_tool is only available on macOS (NSPasteboard).")
    }
#endif

    // MARK: - System notification (macOS)

#if canImport(UserNotifications)
    /// Posts a macOS notification the way Legacy does: the genuine
    /// `UNUserNotificationCenter` path first, the `/usr/bin/osascript`
    /// `display notification` fallback when that does not deliver
    /// (Legacy's fallback always uses the sound name "Submarine"
    /// when a sound is wanted — reproduced verbatim). Returns the
    /// Legacy summary text and whether anything delivered.
    func terminalPostNotification(title: String, subtitle: String, message: String,
                                  sound: String, critical: Bool) async throws -> (String, Bool) {
        let center = UNUserNotificationCenter.current()
        var deliveredViaUN = false
        var authStatusDescription = "unknown"
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional:
            let content = UNMutableNotificationContent()
            content.title = title
            if !subtitle.isEmpty { content.subtitle = subtitle }
            content.body = message
            if sound.lowercased() != "none" {
                content.sound = critical ? UNNotificationSound.defaultCritical : UNNotificationSound.default
            }
            do {
                try await center.add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
                deliveredViaUN = true
                authStatusDescription = "authorized"
            } catch {
                authStatusDescription = "failed: \(error.localizedDescription)"
            }
        case .denied:
            authStatusDescription = "denied"
        case .notDetermined:
            do {
                let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
                if granted {
                    let content = UNMutableNotificationContent()
                    content.title = title
                    if !subtitle.isEmpty { content.subtitle = subtitle }
                    content.body = message
                    if sound.lowercased() != "none" { content.sound = .default }
                    try await center.add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
                    deliveredViaUN = true
                    authStatusDescription = "granted_and_delivered"
                } else {
                    authStatusDescription = "not_granted"
                }
            } catch {
                authStatusDescription = "auth_error: \(error.localizedDescription)"
            }
        @unknown default:
            authStatusDescription = "unknown_status"
        }

        var scriptDelivered = false
        if !deliveredViaUN {
            let escapedTitle = title.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
            let escapedSubtitle = subtitle.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
            let escapedBody = message.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
            var scriptText = "display notification \"\(escapedBody)\" with title \"\(escapedTitle)\""
            if !escapedSubtitle.isEmpty { scriptText += " subtitle \"\(escapedSubtitle)\"" }
            if sound.lowercased() != "none" { scriptText += " sound name \"Submarine\"" }
            let run = await Task.detached {
                Self.terminalRunFixed("/usr/bin/osascript", ["-e", scriptText], timeout: 15)
            }.value
            scriptDelivered = run?.exitCode == 0
        }

        let summary = """
        System Notification Delivered:
        - Title: \(title)
        - Subtitle: \(subtitle.isEmpty ? "None" : subtitle)
        - Message: \(message)
        - Native UNUserNotification: \(deliveredViaUN ? "Success" : "Bypassed (\(authStatusDescription))")
        - AppleScript Notification Fallback: \(scriptDelivered ? "Success" : (deliveredViaUN ? "Not needed" : "Failed"))
        - Sound: \(sound)
        - Timestamp: \(ISO8601DateFormatter().string(from: Date()))
        """
        return (summary, deliveredViaUN || scriptDelivered)
    }
#else
    func terminalPostNotification(title: String, subtitle: String, message: String,
                                  sound: String, critical: Bool) async throws -> (String, Bool) {
        throw MCPToolError("system_notification_tool is only available on macOS (UserNotifications).")
    }
#endif

    // MARK: - Screen capture (macOS ScreenCaptureKit)

#if canImport(ScreenCaptureKit)
    /// Captures the full screen of one display (or the main display)
    /// as a PNG, via `SCScreenshotManager` — Legacy's
    /// `AssistScreenCaptureEngine.captureFullScreen`. The interactive
    /// region-selection overlay Legacy uses for `capture_mode:
    /// "region" is not ported (see `takeScreenshot`).
    func terminalCaptureScreenshot(displayID: UInt32?, includeCursor: Bool) async throws -> TerminalScreenshot {
        guard terminalScreenCaptureAuthorized() else {
            throw MCPToolError("Screen Recording permission has not been granted. Please grant Screen Recording permission to SwiftCode in macOS System Settings > Privacy & Security > Screen Recording, then retry.")
        }
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        let target = displayID.map { CGDirectDisplayID($0) } ?? CGMainDisplayID()
        guard let scDisplay = content.displays.first(where: { $0.displayID == target }) ?? content.displays.first else {
            throw MCPToolError("Target display \(target) was not found in shareable displays.")
        }
        let filter = SCContentFilter(display: scDisplay, excludingWindows: [])
        let config = SCStreamConfiguration()
        config.width = scDisplay.width * 2
        config.height = scDisplay.height * 2
        config.showsCursor = includeCursor
        config.captureResolution = .best
        let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
        guard let png = terminalEncodePNG(image) else {
            throw MCPToolError("Failed to encode the screenshot as PNG.")
        }
        return TerminalScreenshot(png: png, width: image.width, height: image.height, displayID: scDisplay.displayID)
    }

    /// Legacy's `checkAuthorization(promptIfDenied:)`: true when
    /// Screen Recording access is already granted; otherwise asks
    /// once and reports false for this call.
    func terminalScreenCaptureAuthorized() -> Bool {
#if canImport(CoreGraphics)
        if CGPreflightScreenCaptureAccess() { return true }
        _ = CGRequestScreenCaptureAccess()
        return false
#else
        return false
#endif
    }

    /// Legacy's `AssistScreenCaptureEngine.encodePNG`.
    func terminalEncodePNG(_ image: CGImage) -> Data? {
#if canImport(ImageIO) && canImport(UniformTypeIdentifiers)
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data as CFMutableData, UTType.png.identifier as CFString, 1, nil) else {
            return nil
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
#else
        return nil
#endif
    }
#else
    func terminalCaptureScreenshot(displayID: UInt32?, includeCursor: Bool) async throws -> TerminalScreenshot {
        throw MCPToolError("take_screenshot is only available on macOS (ScreenCaptureKit).")
    }
#endif

    // MARK: - App control (macOS NSWorkspace / CoreGraphics)

#if canImport(AppKit)
    /// The running applications (Legacy's
    /// `AssistAppInteractionEngine.listApplications`, running half
    /// only: SwiftCode has no installed-app index, so applications that
    /// are installed but not running are not listed).
    func terminalRunningApplications(filter: String?) throws -> [TerminalAppInfo] {
        NSWorkspace.shared.runningApplications.compactMap { app in
            guard let name = app.localizedName, !name.isEmpty else { return nil }
            let bundleID = app.bundleIdentifier ?? ""
            if let filter, !filter.isEmpty {
                guard name.localizedCaseInsensitiveContains(filter)
                        || bundleID.localizedCaseInsensitiveContains(filter) else { return nil }
            }
            return TerminalAppInfo(name: name, bundleIdentifier: bundleID, pid: app.processIdentifier)
        }
    }

    /// A running application by bundle identifier, name
    /// (case-insensitive), or PID.
    func terminalResolveRunningApplication(_ identifier: String) -> NSRunningApplication? {
        let apps = NSWorkspace.shared.runningApplications
        if let byBundle = apps.first(where: { $0.bundleIdentifier == identifier }) { return byBundle }
        if let pid = Int32(identifier), pid > 0 {
            if let byPid = apps.first(where: { $0.processIdentifier == pid }) { return byPid }
        }
        return apps.first(where: { $0.localizedName?.localizedCaseInsensitiveCompare(identifier) == .orderedSame })
    }

    /// Launches an application by bundle identifier or name (looking
    /// for `<name>.app` under the standard application folders), or
    /// returns it when it is already running. `nil` when nothing
    /// matching can be launched.
    func terminalLaunchApplication(_ identifier: String) -> NSRunningApplication? {
        if let running = terminalResolveRunningApplication(identifier) { return running }
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: identifier) {
            if let launched = try? NSWorkspace.shared.launchApplication(at: url, options: [], configuration: [:]) {
                return launched
            }
            return terminalResolveRunningApplication(identifier)
        }
        let home = FileManager.default.homeDirectoryForCurrentUser
        let folders = [URL(fileURLWithPath: "/Applications"), URL(fileURLWithPath: "/System/Applications"),
                       home.appendingPathComponent("Applications")]
        for folder in folders {
            guard let items = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil,
                                                                            options: [.skipsHiddenFiles]) else { continue }
            for url in items where url.pathExtension == "app"
                    && url.deletingPathExtension().lastPathComponent.localizedCaseInsensitiveCompare(identifier) == .orderedSame {
                if let launched = try? NSWorkspace.shared.launchApplication(at: url, options: [], configuration: [:]) {
                    return launched
                }
                return terminalResolveRunningApplication(identifier)
            }
        }
        return nil
    }
#else
    func terminalRunningApplications(filter: String?) throws -> [TerminalAppInfo] {
        throw MCPToolError("use_app is only available on macOS.")
    }
#endif

#if canImport(CoreGraphics)
    /// The on-screen windows of one process, via
    /// `CGWindowListCopyWindowInfo` (no Accessibility permission
    /// needed; minimized and hidden windows are not on-screen and so
    /// are not listed, unlike Legacy's Accessibility window list).
    func terminalAppWindows(pid: Int32) -> [TerminalWindowInfo] {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] else {
            return []
        }
        var out: [TerminalWindowInfo] = []
        for w in list {
            guard (w[kCGWindowOwnerPID as String] as? NSNumber)?.intValue == Int(pid) else { continue }
            let number = (w[kCGWindowNumber as String] as? NSNumber)?.intValue ?? 0
            let title = (w[kCGWindowName as String] as? String) ?? ""
            let bounds = w[kCGWindowBounds as String] as? [String: Any] ?? [:]
            let x = (bounds["X"] as? NSNumber)?.intValue ?? 0
            let y = (bounds["Y"] as? NSNumber)?.intValue ?? 0
            let width = (bounds["Width"] as? NSNumber)?.intValue ?? 0
            let height = (bounds["Height"] as? NSNumber)?.intValue ?? 0
            out.append(TerminalWindowInfo(id: "window_\(number)", title: title, x: x, y: y, width: width, height: height))
        }
        return out
    }
#else
    func terminalAppWindows(pid: Int32) -> [TerminalWindowInfo] { [] }
#endif
}

/// One fixed-argv subprocess run.
struct TerminalFixedRun: Sendable {
    var exitCode: Int32
    var stdout: String
    var stderr: String
    var timedOut: Bool
}

/// The expected value kind of one allowlisted sysctl name (Legacy's
/// `AssistSystemTool.SysctlKind`).
enum TerminalSysctlKind: Sendable {
    case string
    case int32
    case uint64
}

/// One fullscreen screen capture.
struct TerminalScreenshot: Sendable {
    var png: Data
    var width: Int
    var height: Int
    var displayID: UInt32
}

/// One running application (the `use_app` list shape).
struct TerminalAppInfo: Sendable {
    var name: String
    var bundleIdentifier: String
    var pid: Int32
}

/// One on-screen window (the `use_app` list shape).
struct TerminalWindowInfo: Sendable {
    var id: String
    var title: String
    var x: Int
    var y: Int
    var width: Int
    var height: Int
}
