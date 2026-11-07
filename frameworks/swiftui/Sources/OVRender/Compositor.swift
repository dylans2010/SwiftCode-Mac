import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

public protocol RenderSurface: AnyObject {
    var pixelSize: PixelSize { get }
    var contentScale: Double { get }
    var presentation: SurfacePresentation { get }
}

public enum SurfacePresentation {
    case vulkan(any VulkanSurfaceProvider)
    case software(any SoftwareSurfaceProvider)
    case offscreen
}

public protocol VulkanSurfaceProvider: AnyObject {
    var requiredInstanceExtensions: [String] { get }
    func createVulkanSurface(instance: OpaquePointer) throws -> UInt64
}

public protocol SoftwareSurfaceProvider: AnyObject {
    func present(_ frame: PixelImage, damage: [PixelRect])
}

public struct RenderFrame: Sendable {
    public var displayList: DisplayList
    public var scale: Double
    public var background: RenderColor

    public init(displayList: DisplayList, scale: Double, background: RenderColor = .clear) {
        self.displayList = displayList
        self.scale = scale
        self.background = background
    }
}

public struct FrameReport: Sendable {
    public var damage: [PixelRect]
    public var layerCount: Int
    public var rasterSeconds: Double
    public var totalSeconds: Double

    public init(damage: [PixelRect], layerCount: Int, rasterSeconds: Double, totalSeconds: Double) {
        self.damage = damage
        self.layerCount = layerCount
        self.rasterSeconds = rasterSeconds
        self.totalSeconds = totalSeconds
    }
}

public protocol Compositor: AnyObject {
    var backendDescription: String { get }
    @discardableResult
    func render(_ frame: RenderFrame) throws -> FrameReport
    func surfaceDidResize()
    func readback() throws -> PixelImage
    func invalidate()
}

public enum CompositorPreference: Sendable {
    case automatic
    case vulkan
    case software
}

public enum CompositorError: Error, CustomStringConvertible {
    case unavailable(String)
    case vulkan(String)
    case surface(String)

    public var description: String {
        switch self {
        case .unavailable(let s): return "compositor unavailable: \(s)"
        case .vulkan(let s): return "vulkan: \(s)"
        case .surface(let s): return "surface: \(s)"
        }
    }
}
