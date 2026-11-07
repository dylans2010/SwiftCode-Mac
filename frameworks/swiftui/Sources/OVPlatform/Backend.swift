import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

public struct WindowConfiguration: Sendable, Equatable {
    public var title: String
    public var size: CGSize
    public var resizable: Bool
    public var vulkan: Bool
    public var highPixelDensity: Bool
    public var popupParent: PlatformWindowID?
    public var popupOrigin: CGPoint

    public init(title: String = "", size: CGSize = CGSize(width: 800, height: 600), resizable: Bool = true,
                vulkan: Bool = false, highPixelDensity: Bool = true, popupParent: PlatformWindowID? = nil,
                popupOrigin: CGPoint = .zero) {
        self.title = title
        self.size = size
        self.resizable = resizable
        self.vulkan = vulkan
        self.highPixelDensity = highPixelDensity
        self.popupParent = popupParent
        self.popupOrigin = popupOrigin
    }
}

@MainActor
public protocol PlatformClipboard: AnyObject {
    var text: String? { get set }
    var hasText: Bool { get }
}

@MainActor
public protocol PlatformVulkanSurface: AnyObject {
    func requiredInstanceExtensions() -> [String]
    var instanceProcAddress: UnsafeMutableRawPointer? { get }
    func createSurface(instance: UnsafeMutableRawPointer) throws -> UInt64
    func destroySurface(_ surface: UInt64, instance: UnsafeMutableRawPointer)
    func probe() -> VulkanProbeResult
}

public struct VulkanProbeResult: Sendable, Equatable {
    public var presentingDevices: Int
    public var report: String
    public init(presentingDevices: Int, report: String) {
        self.presentingDevices = presentingDevices
        self.report = report
    }
}

@MainActor
public protocol PlatformWindow: AnyObject {
    var id: PlatformWindowID { get }
    var title: String { get set }
    var size: CGSize { get }
    var pixelSize: (width: Int, height: Int) { get }
    var scale: Double { get }
    var refreshRate: Double { get }
    var isClosed: Bool { get }
    func setSize(_ size: CGSize)
    func present(_ frame: PixelBuffer)
    func readback() -> PixelBuffer?
    func startTextInput(caretRect: CGRect)
    func stopTextInput()
    var isTextInputActive: Bool { get }
    var vulkan: (any PlatformVulkanSurface)? { get }
    var popupParent: PlatformWindowID? { get }
    func activate()
    func minimize()
    func close()
    var screenOrigin: CGPoint? { get }
}

extension PlatformWindow {
    public var screenOrigin: CGPoint? { nil }
}

@MainActor
public protocol PlatformBackend: AnyObject {
    var name: String { get }
    var now: TimeInterval { get }
    var clipboard: any PlatformClipboard { get }
    func makeWindow(_ configuration: WindowConfiguration) throws -> any PlatformWindow
    var windows: [any PlatformWindow] { get }
    func waitForEvents(until deadline: TimeInterval?) -> [PlatformEvent]
    func post(_ event: PlatformEvent)
    func openExternally(_ url: URL) -> Bool
    var settings: PlatformSettings { get }
    func shutdown()
}

public enum PlatformError: Error, CustomStringConvertible {
    case unavailable(String)
    case windowCreationFailed(String)
    case vulkan(String)

    public var description: String {
        switch self {
        case .unavailable(let s): return "platform unavailable: \(s)"
        case .windowCreationFailed(let s): return "window creation failed: \(s)"
        case .vulkan(let s): return "Vulkan: \(s)"
        }
    }
}

@MainActor
public enum Platform {
    public static func makeDefaultBackend() -> any PlatformBackend {
        let choice = ProcessInfo.processInfo.environment["OV_PLATFORM"]?.lowercased()
        if choice == "headless" { return HeadlessBackend() }
        do {
            return try SDLBackend()
        } catch {
            if choice == "sdl" {
                FileHandle.standardError.write(Data("OVPlatform: \(error)\n".utf8))
            }
            return HeadlessBackend()
        }
    }
}
