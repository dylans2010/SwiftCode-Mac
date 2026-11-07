#if os(Linux) && arch(arm64)
import Foundation
import Glibc
import YcodeDarwinKernel
import YcodeHostServices

final class DeviceCamera: @unchecked Sendable {
    let optIn: CameraOptIn
    let layout: DeviceLayout
    private(set) var libraryGuestPath: String?
    private(set) var service: CameraGuestService?

    static let libraryName = "libSwiftCodeCamera.dylib"
    var stagedLibraryPath: String { layout.dev + "/swiftcode-camera/" + Self.libraryName }

    init(options: Options, layout: DeviceLayout) {
        self.layout = layout
        var setting = CameraOptIn.load(dev: layout.dev)
        if let text = options.camera {
            guard let mode = CameraOptIn.mode(text) else {
                die("--camera needs on, off, synthetic, /dev/videoN or v4l2:<id> (not '\(text)')", status: 64)
            }
            setting.mode = mode
        }
        if let text = options.cameraPosition {
            guard let p = CameraGuestPresentation.Placement(rawValue: text) else {
                die("--camera-position needs back, front or external (not '\(text)')", status: 64)
            }
            setting.placement = p
        }
        if options.camera != nil || options.cameraPosition != nil {
            do { try setting.save(dev: layout.dev) } catch { stderrLine("swiftcode-simd: warning: cannot save the camera setting: \(error)") }
        }
        optIn = setting
        let isPad = layout.deviceType.family == .pad
        if optIn.isOn {
            let caps = optIn.applyCapabilities(DeviceCapabilities.plist(for: layout.deviceType), isPad: isPad)
            if let data = try? PropertyListSerialization.data(fromPropertyList: caps, format: .xml, options: 0) {
                try? data.write(to: URL(fileURLWithPath: layout.capabilitiesPath), options: .atomic)
            }
        }
        guard optIn.isOn else { return }
        guard let library = Self.findLibrary(options: options, layout: layout) else {
            stderrLine("swiftcode-simd: warning: camera: no \(Self.libraryName) (SimGuestAgents/build-camera.sh; --camera-library or the guest tools); "
                + "apps will not see the camera")
            return
        }
        do {
            let fm = FileManager.default
            try fm.createDirectory(atPath: layout.dev + "/swiftcode-camera", withIntermediateDirectories: true)
            if fm.fileExists(atPath: stagedLibraryPath) { try fm.removeItem(atPath: stagedLibraryPath) }
            try fm.copyItem(atPath: library, toPath: stagedLibraryPath)
            libraryGuestPath = layout.guestPath(stagedLibraryPath)
        } catch {
            stderrLine("swiftcode-simd: warning: camera: cannot stage \(library): \(error)")
        }
    }

    static func findLibrary(options: Options, layout: DeviceLayout) -> String? {
        var candidates: [String] = []
        if let explicit = options.cameraLibrary { candidates.append(absolutePath(explicit)) }
        if let tools = layout.guestTools { candidates.append(tools + "/" + libraryName) }
        if let shim = options.shimPath {
            let swiftcode = (((absolutePath(shim) as NSString).deletingLastPathComponent as NSString).deletingLastPathComponent as NSString)
                .deletingLastPathComponent
            candidates.append(swiftcode + "/SimGuestAgents/out/" + libraryName)
        }
        return candidates.first { FileManager.default.fileExists(atPath: $0) }
    }

    func install(on system: DarwinSystem) {
        guard optIn.isOn, let library = libraryGuestPath else { return }
        system.imageEnvironment = { executable, envp in
            guard CameraAppInjection.isAppExecutable(executable) else { return envp }
            return CameraAppInjection.environment(envp, library: library)
        }
    }

    func start(host: MachHostTask, surfaces: IOSurfaceHostService?, session: DeviceSession) {
        guard optIn.isOn, let selection = optIn.selection else { return }
        guard let surfaces else {
            stderrLine("swiftcode-simd: warning: camera: no IOSurface service; no camera endpoint")
            return
        }
        let placement = optIn.placement(isPad: layout.deviceType.family == .pad)
        do {
            let s = try CameraGuestService(host: host, surfaces: surfaces, selection: selection,
                                           presentation: CameraGuestPresentation(placement: placement),
                                           log: { stderrLine("swiftcode-simd: " + $0) })
            s.start()
            session.hostServices.append((CameraGuestService.serviceName, s.servicePort))
            service = s
            let device = try? CameraHostService.resolve(selection)
            stderrLine("swiftcode-simd: camera: on (\(optIn.modeName), \(placement.rawValue)): "
                + (device.map { "\($0.name) [\($0.id)]" } ?? "no host camera now")
                + (libraryGuestPath == nil ? "; no capture layer" : "; capture layer \(libraryGuestPath!)"))
        } catch {
            stderrLine("swiftcode-simd: warning: camera: cannot start \(CameraGuestService.serviceName): \(error)")
        }
    }

    func setGuestClock(_ clock: @escaping @Sendable () -> (ticks: UInt64, frequency: UInt64)) { service?.setGuestClock(clock) }

    func stop() {
        guard let s = service else { return }
        s.stop()
        stderrLine("swiftcode-simd: camera: \(s.streamsStarted) streams, \(s.framesSent) frames sent, \(s.framesNotSent) not taken, "
            + "\(s.framesReleased) released")
    }

    func handle(_ words: [String], session: DeviceSession?) -> String? {
        switch words.first {
        case "camera":
            return "ok camera \(optIn)" + (service.map { "; streaming \($0.isStreaming); \($0.framesSent) frames sent" } ?? "")
        case "privacy":
            guard words.count == 4, let action = CameraPrivacy.Action(rawValue: words[1]) else {
                return "error: privacy grant|revoke|reset camera|microphone <bundle id>"
            }
            do {
                try CameraPrivacy.apply(action, service: words[2], bundleID: words[3], dev: layout.dev)
            } catch {
                return "error: \(error)"
            }
            let ended = session?.killApp(words[3]) ?? "no session"
            return "ok \(action.rawValue) \(words[2]) \(words[3]); app: \(ended)"
        default:
            return nil
        }
    }
}

nonisolated(unsafe) var deviceCameraControl: (([String]) -> String?)?

func isPrivacyClient(_ arguments: [String]) -> Bool { arguments.contains("--privacy") }

func runPrivacyClient(_ arguments: [String]) -> Never {
    let help = "usage: swiftcode-simd --device <dir> --privacy grant|revoke|reset camera|microphone <bundle id>"
    guard let d = arguments.firstIndex(of: "--device"), d + 1 < arguments.count,
          let p = arguments.firstIndex(of: "--privacy"), p + 3 < arguments.count else { die(help, status: 64) }
    let dev = absolutePath(arguments[d + 1])
    let words = ["privacy"] + arguments[(p + 1)...(p + 3)]
    guard CameraPrivacy.Action(rawValue: words[1]) != nil, CameraPrivacy.services[words[2]] != nil else { die(help, status: 64) }
    let path = DeviceLayout.controlSocketPath(dev: dev)
    let fd = socket(AF_UNIX, Int32(SOCK_STREAM.rawValue), 0)
    if fd >= 0, withUnixAddress(path, { connect(fd, $0, $1) }) == 0 {
        let line = words.joined(separator: " ") + "\n"
        _ = line.withCString { write(fd, $0, strlen($0)) }
        var reply = [UInt8]()
        var buf = [UInt8](repeating: 0, count: 4096)
        while true {
            let n = read(fd, &buf, buf.count)
            if n <= 0 { break }
            reply += buf[0..<n]
        }
        close(fd)
        let text = String(decoding: reply, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        print(text)
        exit(text.hasPrefix("ok") ? 0 : 1)
    }
    if fd >= 0 { close(fd) }
    do {
        try CameraPrivacy.apply(CameraPrivacy.Action(rawValue: words[1])!, service: words[2], bundleID: words[3], dev: dev)
        print("ok \(words[1]) \(words[2]) \(words[3]) (the device is not running; its next boot reads it)")
        exit(0)
    } catch {
        stderrLine("swiftcode-simd: \(error)")
        exit(1)
    }
}
#endif
