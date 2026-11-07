import Foundation
import OVPlatform
import OVRender
#if OPENVIEWS_RENAMED
import OpenViewsCore
#else
import SwiftUICore
#endif

@MainActor
package protocol FramePresenter: AnyObject {
    func present(_ window: WindowHost)
    func surfaceDidResize()
    func invalidate()
    func readback() -> PixelBuffer?
}

final class WindowRenderSurface: RenderSurface, OVRender.VulkanSurfaceProvider, SoftwareSurfaceProvider,
    @unchecked Sendable {
    nonisolated(unsafe) let window: any PlatformWindow

    init(_ window: any PlatformWindow) { self.window = window }

    var pixelSize: PixelSize {
        MainActor.assumeIsolated {
            let p = window.pixelSize
            return PixelSize(width: p.width, height: p.height)
        }
    }

    var contentScale: Double { MainActor.assumeIsolated { window.scale } }

    var presentation: SurfacePresentation {
        let vulkan = MainActor.assumeIsolated { window.vulkan != nil }
        return vulkan ? .vulkan(self) : .software(self)
    }

    var requiredInstanceExtensions: [String] {
        MainActor.assumeIsolated { window.vulkan?.requiredInstanceExtensions() ?? [] }
    }

    func createVulkanSurface(instance: OpaquePointer) throws -> UInt64 {
        let raw = UInt(bitPattern: Int(bitPattern: UnsafeMutableRawPointer(instance)))
        return try MainActor.assumeIsolated {
            guard let v = window.vulkan, let p = UnsafeMutableRawPointer(bitPattern: raw) else {
                throw CompositorError.surface("window has no Vulkan surface")
            }
            return try v.createSurface(instance: p)
        }
    }

    func present(_ frame: PixelImage, damage: [PixelRect]) {
        let buffer = PixelBuffer(width: frame.size.width, height: frame.size.height, bytes: frame.rgba)
        MainActor.assumeIsolated { window.present(buffer) }
    }
}

@MainActor
package final class CompositorPresenter: FramePresenter {
    let surface: WindowRenderSurface
    package private(set) var compositor: (any Compositor)?
    package private(set) var compositorError: String?
    private let rasterizer = SoftwareRasterizer()
    package private(set) var lastFrame: PixelBuffer?

    init(window: any PlatformWindow, preference: CompositorPreference? = nil) {
        surface = WindowRenderSurface(window)
        do {
            let pref = preference ?? (window.vulkan != nil ? .vulkan : .automatic)
            compositor = try makeCompositor(for: surface, preference: pref)
        } catch {
            compositorError = "\(error)"
        }
    }

    package var description: String { compositor?.backendDescription ?? "cpu-rasterizer" }

    private static func renderColor(_ c: Color.Resolved) -> RenderColor {
        RenderColor(red: Double(c.red), green: Double(c.green), blue: Double(c.blue), alpha: Double(c.opacity))
    }

    package func makeFrame(_ window: WindowHost) -> RenderFrame {
        let env = window.graph.environment
        let list = window.graph.displayList()
        let background: RenderColor = env.colorScheme == .dark ? .black : .white
        return RenderFrame(displayList: list, scale: window.platform.scale, background: background)
    }

    package func present(_ window: WindowHost) {
        let frame = makeFrame(window)
        if let compositor {
            do {
                try compositor.render(frame)
                return
            } catch {
                compositorError = "\(error)"
                self.compositor = nil
            }
        }
        guard window.platform.vulkan == nil else { return }
        let image = rasterizer.render(frame, size: surface.pixelSize)
        let buffer = PixelBuffer(width: image.size.width, height: image.size.height, bytes: image.rgba)
        lastFrame = buffer
        window.platform.present(buffer)
    }

    package func surfaceDidResize() { compositor?.surfaceDidResize() }
    package func invalidate() { compositor?.invalidate() }

    package func readback() -> PixelBuffer? {
        if let compositor, let img = try? compositor.readback() {
            return PixelBuffer(width: img.size.width, height: img.size.height, bytes: img.rgba)
        }
        return lastFrame
    }
}
