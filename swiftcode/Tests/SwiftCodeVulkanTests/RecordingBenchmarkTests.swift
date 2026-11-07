import Foundation
import Testing
@testable import SwiftCodeMetalHost
@testable import SwiftCodeVulkan

@Suite(.serialized, .enabled(if: ProcessInfo.processInfo.environment["SWIFTCODE_VULKAN_BENCH"] == "1" && VK.available,
                             "SWIFTCODE_VULKAN_BENCH=1 on a Vulkan GPU host"))
struct RecordingBenchmarkTests {
    static func frame(target: MetalHandle, offscreen: [MetalHandle], pipelines: [MetalHandle], buffer: MetalHandle,
                      texture: MetalHandle, sampler: MetalHandle, passes: Int, draws: Int) -> [MetalPass] {
        var out: [MetalPass] = []
        for p in 0..<passes {
            var cmds: [MetalRenderCommand] = []
            for d in 0..<draws {
                cmds.append(.setRenderPipelineState(pipelines[(p + d) % pipelines.count]))
                cmds.append(.setBuffer(stage: .vertex, index: 0, buffer: buffer, offset: 256 * d))
                cmds.append(.setBuffer(stage: .vertex, index: 1, buffer: buffer, offset: 4096))
                cmds.append(.setBuffer(stage: .fragment, index: 0, buffer: buffer, offset: 8192 + 64 * d))
                cmds.append(.setTexture(stage: .fragment, index: 0, texture: texture))
                cmds.append(.setSamplerState(stage: .fragment, index: 0, sampler: sampler, lodMinClamp: nil, lodMaxClamp: nil))
                cmds.append(.setScissorRect(MetalScissorRect(x: 0, y: 0, width: 32, height: 32)))
                cmds.append(.draw(MetalDraw(primitiveType: MetalPrimitiveType.triangleStrip, vertexStart: 0, vertexCount: 4)))
            }
            let into = p == passes - 1 ? target : offscreen[p % offscreen.count]
            out.append(VK.colorPass(into, load: MetalLoadAction.load, cmds))
        }
        return out
    }

    func measure(_ backend: VulkanMetalBackend, rounds: Int) throws -> (perCB: Double, perDraw: Double, parts: String) {
        let b = backend
        func fn(_ name: String) throws -> MetalHandle {
            let h = VK.handle()
            try b.createFunction(h, metallib: Array("test:\(name)".utf8))
            return h
        }
        var pipes: [MetalHandle] = []
        for _ in 0..<4 {
            var desc = MetalRenderPipelineDescriptor()
            desc.vertexFunction = try fn("full.vert")
            desc.fragmentFunction = try fn("tex.frag")
            var c = MetalColorAttachmentDescriptor(index: 0)
            c.pixelFormat = MetalPixelFormat.bgra8Unorm
            desc.colorAttachments = [c]
            let pipe = VK.handle()
            try b.createRenderPipeline(pipe, desc)
            pipes.append(pipe)
        }
        let mem = HostPages(1 << 16)
        let buf = VK.handle()
        try b.createBuffer(buf, length: 1 << 16, storage: .shared, guestMemory: mem.region(0, 1 << 16))
        let smp = VK.handle()
        try b.createSampler(smp, MetalSamplerDescriptor())
        func tex(_ w: Int) throws -> MetalHandle {
            let t = VK.handle()
            try b.createTexture(t, MetalTextureDescriptor(pixelFormat: MetalPixelFormat.bgra8Unorm, width: w, height: w, usage: 0x5,
                                                          resourceOptions: 0x20), iosurface: nil)
            return t
        }
        let target = try tex(256), src = try tex(64)
        let offscreen = try (0..<6).map { _ in try tex(128) }
        let passes = 20, draws = 2
        let frame = Self.frame(target: target, offscreen: offscreen, pipelines: pipes, buffer: buf, texture: src, sampler: smp,
                               passes: passes, draws: draws)
        func run() {
            let done = DispatchSemaphore(value: 0)
            let cb = MetalCommandBuffer(process: 1, queue: nil, commandBufferRef: VK.nextID(), passes: frame)
            b.submit(cb, scheduled: {}, completed: { _ in done.signal() })
            _ = done.wait(timeout: .now() + 10)
        }
        for _ in 0..<10 { run() }
        let before = b.stats.recording
        for _ in 0..<rounds { run() }
        let after = b.stats.recording
        let ns = Double(after.totalNs &- before.totalNs) / Double(max(after.count - before.count, 1))
        for h in pipes + [buf, smp, target, src] + offscreen { b.release(h) }
        return (ns / 1e6, ns / 1e3 / Double(passes * draws), b.recordProfiling ? b.lockedRecordProfileSummary() : "")
    }

    @Test func recordingCostPerDraw() throws {
        let fast = try measure(VK.backend, rounds: 200)
        print(String(format: "recording (fast %@): %.3f ms per command buffer, %.2f µs per draw", VK.backend.options.recordFast ? "on" : "off",
                     fast.perCB, fast.perDraw))
        if !fast.parts.isEmpty { print("  parts: \(fast.parts)") }
        var o = VulkanMetalBackend.Options()
        o.recordFast = !VK.backend.options.recordFast
        let other = VulkanMetalBackend(translator: VK.translator, options: o)
        defer { other.shutdown() }
        let slow = try measure(other, rounds: 200)
        print(String(format: "recording (fast %@): %.3f ms per command buffer, %.2f µs per draw", o.recordFast ? "on" : "off",
                     slow.perCB, slow.perDraw))
        if !slow.parts.isEmpty { print("  parts: \(slow.parts)") }
    }
}
