import CVulkan
import Foundation
import Testing
@testable import SwiftCodeMetalHost
@testable import SwiftCodeVulkan

enum IsolationGPU {
    static let deviceName: String? = {
        var c = yvk_context()
        var err = [CChar](repeating: 0, count: 256)
        guard yvk_context_create(&c, nil, &err, err.count) == 0 else { return nil }
        let name = withUnsafeBytes(of: c.properties.deviceName) { raw in
            String(cString: raw.bindMemory(to: CChar.self).baseAddress!)
        }
        yvk_context_destroy(&c)
        return name
    }()

    static var available: Bool { deviceName != nil }

    static let drivesDisplay: Bool = {
        switch ProcessInfo.processInfo.environment["SWIFTCODE_TEST_GPU_HANGS"] {
        case "1": return false
        case "0": return true
        default: return deviceName.map { yvk_presents_to_session($0) == 1 } ?? false
        }
    }()
}

enum GPUHangTests {
    static let lock = NSLock()
}

@Suite(.serialized, .enabled(if: IsolationGPU.available, "needs a Vulkan GPU with VK_EXT_external_memory_host"),
       .disabled(if: IsolationGPU.drivesDisplay, "GPU drives a display"))
struct GPUClientIsolationTests {
    static func translator() -> PrebuiltShaderTranslator {
        let t = GPURecoveryTests.translator()
        t.add(Array("test:tri.vert".utf8), TranslatedShader(spirv: TestShaders.triVert, reflection: ShaderReflection(stage: .vertex, entryPoint: "main")))
        t.add(Array("test:color.frag".utf8), TranslatedShader(spirv: TestShaders.colorFrag, reflection: ShaderReflection(stage: .fragment, entryPoint: "main")))
        return t
    }

    final class Log: @unchecked Sendable {
        let lock = NSLock()
        var lines: [String] = []
        func add(_ s: String) { lock.lock(); lines.append(s); lock.unlock(); print(s) }
        func contains(_ s: String) -> Bool { lock.lock(); defer { lock.unlock() }; return lines.contains { $0.contains(s) } }
    }

    final class Client: @unchecked Sendable {
        let process: MetalProcessID
        let target = VK.handle(), pipeline = VK.handle(), vertices = VK.handle(), transform = VK.handle()
        let pages = HostPages(16384)
        let lock = NSLock()
        var statuses: [Int] = []
        var completedAt: [Double] = []
        init(process: MetalProcessID) { self.process = process }

        func setUp(_ b: VulkanMetalBackend) throws {
            for (i, p) in [(Float(-1), Float(-1)), (1, -1), (0, 1)].enumerated() {
                pages.pointer.storeBytes(of: p.0, toByteOffset: 12 * i, as: Float.self)
                pages.pointer.storeBytes(of: p.1, toByteOffset: 12 * i + 4, as: Float.self)
                pages.pointer.storeBytes(of: UInt32(0xFF00_00FF), toByteOffset: 12 * i + 8, as: UInt32.self)
            }
            for (i, v) in [Float(1), 1, 0, 0].enumerated() { pages.pointer.storeBytes(of: v, toByteOffset: 4096 + 4 * i, as: Float.self) }
            try b.createBuffer(vertices, length: 36, storage: .shared, guestMemory: pages.region(0, 36))
            try b.createBuffer(transform, length: 16, storage: .shared, guestMemory: pages.region(4096, 16))
            try b.createTexture(target, MetalTextureDescriptor(pixelFormat: MetalPixelFormat.rgba8Unorm, width: 64, height: 64,
                                                              usage: 0x5, resourceOptions: 0x20), iosurface: nil)
            let vf = VK.handle(), ff = VK.handle()
            try b.createFunction(vf, metallib: Array("test:tri.vert".utf8))
            try b.createFunction(ff, metallib: Array("test:color.frag".utf8))
            var desc = MetalRenderPipelineDescriptor()
            desc.vertexFunction = vf
            desc.fragmentFunction = ff
            var c = MetalColorAttachmentDescriptor(index: 0)
            c.pixelFormat = MetalPixelFormat.rgba8Unorm
            desc.colorAttachments = [c]
            var vd = MetalVertexDescriptor()
            var a0 = MetalVertexDescriptor.Attribute(index: 0); a0.format = 29; a0.offset = 0; a0.bufferIndex = 0
            var a1 = MetalVertexDescriptor.Attribute(index: 1); a1.format = 9; a1.offset = 8; a1.bufferIndex = 0
            var l0 = MetalVertexDescriptor.Layout(bufferIndex: 0); l0.stride = 12
            vd.attributes = [a0, a1]
            vd.layouts = [l0, l0]
            desc.vertexDescriptor = vd
            try b.createRenderPipeline(pipeline, desc)
        }

        func frame(_ n: Int) -> MetalCommandBuffer {
            var d = MetalRenderPassDescriptor()
            d.colorAttachments = [MetalColorAttachment(index: 0, attachment: MetalRenderPassAttachment(
                texture: target, loadAction: MetalLoadAction.clear, storeAction: MetalStoreAction.store),
                clearColor: [0, Double(n % 256) / 255, 1, 1])]
            let cmds: [MetalRenderCommand] = [
                .setRenderPipelineState(pipeline),
                .setBuffer(stage: .vertex, index: 0, buffer: vertices, offset: 0),
                .setBuffer(stage: .vertex, index: 1, buffer: transform, offset: 0),
                .draw(MetalDraw(primitiveType: MetalPrimitiveType.triangle, vertexStart: 0, vertexCount: 3)),
            ]
            return MetalCommandBuffer(process: process, queue: nil, commandBufferRef: VK.nextID(),
                                      passes: [.render(MetalRenderPass(descriptor: d, commands: cmds))])
        }

        func draw(_ b: VulkanMetalBackend, count: Int, interval: Double, start: DispatchTime) {
            for n in 0..<count {
                b.submit(frame(n), scheduled: {}, completed: { [self] s in
                    let t = Double(DispatchTime.now().uptimeNanoseconds &- start.uptimeNanoseconds) / 1e9
                    lock.lock(); statuses.append(s); completedAt.append(t); lock.unlock()
                })
                usleep(UInt32(interval * 1e6))
            }
        }

        func waitFor(_ count: Int, seconds: Double) -> Bool {
            let end = DispatchTime.now().uptimeNanoseconds + UInt64(seconds * 1e9)
            while DispatchTime.now().uptimeNanoseconds < end {
                lock.lock(); let n = statuses.count; lock.unlock()
                if n >= count { return true }
                usleep(10000)
            }
            return false
        }

        var longestGap: Double {
            lock.lock(); defer { lock.unlock() }
            var last = 0.0, gap = 0.0
            for t in completedAt.sorted() { gap = max(gap, t - last); last = t }
            return gap
        }

        func pixel(_ b: VulkanMetalBackend, _ x: Int, _ y: Int) throws -> [UInt8] {
            let out = HostPages(65536)
            try b.getBytes(texture: target, MetalRegion(width: 64, height: 64), level: 0, slice: 0,
                           into: out.region(0, 64 * 64 * 4), bytesPerRow: 256, bytesPerImage: 64 * 64 * 4)
            let o = 4 * (y * 64 + x)
            return Array(out.bytes(o, 4))
        }

        func release(_ b: VulkanMetalBackend) { for h in [target, pipeline, vertices, transform] { b.release(h) } }
    }

    final class Spinner: @unchecked Sendable {
        let process: MetalProcessID
        let guest = HostPages(16384)
        let flag = VK.handle(), out = VK.handle(), function = VK.handle(), pipeline = VK.handle()
        let lock = NSLock()
        var statuses: [Int] = []
        let done = DispatchSemaphore(value: 0)
        init(process: MetalProcessID) { self.process = process }

        func setUp(_ b: VulkanMetalBackend) throws {
            try b.createBuffer(flag, length: 4, storage: .shared, guestMemory: guest.region(0, 4))
            try b.createBuffer(out, length: 4, storage: .shared, guestMemory: guest.region(64, 4))
            try b.createFunction(function, metallib: Array("test:spin".utf8))
            _ = try b.createComputePipeline(pipeline, function: function)
        }

        func hang(_ b: VulkanMetalBackend) {
            b.submit(MetalCommandBuffer(process: process, queue: nil, commandBufferRef: VK.nextID(), passes: [.compute([
                .setComputePipelineState(pipeline),
                .setBuffer(index: 0, buffer: flag, offset: 0),
                .setBuffer(index: 1, buffer: out, offset: 0),
                .dispatchThreads(MetalSize3(1, 1, 1), threadsPerThreadgroup: MetalSize3(1, 1, 1)),
            ])]), scheduled: {}, completed: { [self] s in
                lock.lock(); statuses.append(s); lock.unlock()
                done.signal()
            })
        }

        func harmless(_ b: VulkanMetalBackend) {
            b.submit(MetalCommandBuffer(process: process, queue: nil, commandBufferRef: VK.nextID(), passes: [.compute([])]),
                     scheduled: {}, completed: { [self] s in
                         lock.lock(); statuses.append(s); lock.unlock()
                         done.signal()
                     })
        }

        func status(_ i: Int) -> Int { lock.lock(); defer { lock.unlock() }; return i < statuses.count ? statuses[i] : -1 }
        func release(_ b: VulkanMetalBackend) {
            guest.pointer.storeBytes(of: UInt32(1), toByteOffset: 0, as: UInt32.self)
            for h in [flag, out, pipeline, function] { b.release(h) }
        }
    }

    @Test func stuckClientFailsAloneAndOthersKeepDrawing() throws {
        GPUHangTests.lock.lock()
        defer { GPUHangTests.lock.unlock() }
        let log = Log()
        var o = VulkanMetalBackend.Options()
        o.log = { log.add($0) }
        o.watchdogSeconds = 30
        o.blockingWatchdogSeconds = 1
        o.hangReportSeconds = 0.5
        o.revokeAfterHangs = 2
        o.describeProcess = { $0 == 1 ? "spinner, guest pid 101" : "client \($0)" }
        let b = VulkanMetalBackend(translator: Self.translator(), options: o)
        defer { b.shutdown() }
        let spinner = Spinner(process: 1)
        let c2 = Client(process: 2), c3 = Client(process: 3)
        try spinner.setUp(b)
        try c2.setUp(b)
        try c3.setUp(b)

        let start = DispatchTime.now()
        spinner.hang(b)
        usleep(100_000)
        let frames = 40
        let t2 = Thread { c2.draw(b, count: frames, interval: 0.05, start: start) }
        let t3 = Thread { c3.draw(b, count: frames, interval: 0.05, start: start) }
        t2.start(); t3.start()
        #expect(spinner.done.wait(timeout: .now() + 60) == .success, "the stuck command buffer never completed")
        #expect(c2.waitFor(frames, seconds: 60) && c3.waitFor(frames, seconds: 60), "frames missing")
        let ended = Double(DispatchTime.now().uptimeNanoseconds &- start.uptimeNanoseconds) / 1e9
        #expect(spinner.status(0) == MetalCommandBufferStatus.error, "the stuck command buffer: \(spinner.status(0))")
        #expect(c2.statuses.allSatisfy { $0 == MetalCommandBufferStatus.completed }, "client 2: \(c2.statuses)")
        #expect(c3.statuses.allSatisfy { $0 == MetalCommandBufferStatus.completed }, "client 3: \(c3.statuses)")
        #expect(b.deviceResetCount == 1)
        print(String(format: "round 1: frames done %.2f s after the hang; longest gap client 2 %.2f s, client 3 %.2f s",
                     ended, c2.longestGap, c3.longestGap))
        #expect(c2.longestGap < 20 && c3.longestGap < 20, "gaps \(c2.longestGap) \(c3.longestGap)")
        if b.lastHangReport.isEmpty {
            #expect(b.lastDeviceResetReport.contains("after a device loss"), "\(b.lastDeviceResetReport)")
            #expect(b.lastDeviceResetReport.contains("failed (process 1"), "\(b.lastDeviceResetReport)")
        } else {
            #expect(b.lastHangReport.contains("process 1 (spinner, guest pid 101)"), "\(b.lastHangReport)")
            #expect(b.lastHangReport.contains("other client"), "\(b.lastHangReport)")
        }
        #expect(log.contains("has run for"), "the hang report (its command buffer described) is missing")
        let last = UInt8((frames - 1) % 256)
        let corner2 = try c2.pixel(b, 2, 2), triangle2 = try c2.pixel(b, 32, 40), triangle3 = try c3.pixel(b, 32, 40)
        #expect(corner2 == [0, last, 255, 255], "client 2 corner \(corner2)")
        #expect(triangle2 == [255, 0, 0, 255], "client 2 triangle \(triangle2)")
        #expect(triangle3 == [255, 0, 0, 255], "client 3 triangle \(triangle3)")
        #expect(!b.gpuAccessRevoked(1))

        let start2 = DispatchTime.now()
        spinner.hang(b)
        usleep(100_000)
        let u2 = Thread { c2.draw(b, count: frames, interval: 0.05, start: start2) }
        u2.start()
        #expect(spinner.done.wait(timeout: .now() + 60) == .success)
        #expect(c2.waitFor(2 * frames, seconds: 60))
        #expect(spinner.status(1) == MetalCommandBufferStatus.error)
        #expect(b.deviceResetCount == 2)
        #expect(b.gpuAccessRevoked(1))
        #expect(log.contains("GPU access revoked for process 1 (spinner, guest pid 101) after 2 GPU hangs"))

        let start3 = DispatchTime.now()
        spinner.hang(b)
        #expect(spinner.done.wait(timeout: .now() + 5) == .success, "a revoked client's command buffer must fail at once")
        #expect(spinner.status(2) == MetalCommandBufferStatus.error)
        c2.draw(b, count: 10, interval: 0.01, start: start3)
        #expect(c2.waitFor(2 * frames + 10, seconds: 5))
        #expect(c2.statuses.allSatisfy { $0 == MetalCommandBufferStatus.completed }, "client 2: \(c2.statuses)")
        #expect(b.deviceResetCount == 2)
        #expect(b.stats.revokedRefusals == 1)
        #expect(try c2.pixel(b, 32, 40) == [255, 0, 0, 255])
        spinner.release(b)
        c2.release(b)
        c3.release(b)
    }

    @Test func systemUIKeepsGPUAccess() throws {
        GPUHangTests.lock.lock()
        defer { GPUHangTests.lock.unlock() }
        let log = Log()
        var o = VulkanMetalBackend.Options()
        o.log = { log.add($0) }
        o.watchdogSeconds = 30
        o.blockingWatchdogSeconds = 1
        o.revokeAfterHangs = 2
        o.describeProcess = { $0 == 1 ? "backboardd, guest pid 124" : "client \($0)" }
        o.exemptFromRevocation = { $0 == 1 }
        let b = VulkanMetalBackend(translator: Self.translator(), options: o)
        defer { b.shutdown() }
        let server = Spinner(process: 1)
        let c2 = Client(process: 2)
        try server.setUp(b)
        try c2.setUp(b)
        for round in 0..<3 {
            let start = DispatchTime.now()
            server.hang(b)
            usleep(100_000)
            c2.draw(b, count: 10, interval: 0.05, start: start)
            #expect(server.done.wait(timeout: .now() + 60) == .success, "hang \(round + 1) was not ended")
            #expect(server.status(round) == MetalCommandBufferStatus.error)
            #expect(c2.waitFor(10 * (round + 1), seconds: 60))
            #expect(!b.gpuAccessRevoked(1), "the system UI lost GPU access after hang \(round + 1)")
        }
        #expect(b.deviceResetCount == 3)
        #expect(log.contains("GPU access kept for process 1 (backboardd, guest pid 124) after 2 GPU hangs"))
        #expect(b.stats.revokedRefusals == 0)
        #expect(b.stats.exemptFromRevocation == 2)
        server.harmless(b)
        #expect(server.done.wait(timeout: .now() + 10) == .success)
        #expect(server.status(3) == MetalCommandBufferStatus.completed)
        #expect(c2.statuses.allSatisfy { $0 == MetalCommandBufferStatus.completed }, "client 2: \(c2.statuses)")
        server.release(b)
        c2.release(b)
    }

    @Test func longWorkWithNobodyWaitingIsNotEnded() throws {
        GPUHangTests.lock.lock()
        defer { GPUHangTests.lock.unlock() }
        var o = VulkanMetalBackend.Options()
        o.log = { print($0) }
        o.watchdogSeconds = 6
        o.blockingWatchdogSeconds = 1
        let b = VulkanMetalBackend(translator: Self.translator(), options: o)
        defer { b.shutdown() }
        let spinner = Spinner(process: 1)
        try spinner.setUp(b)
        spinner.hang(b)
        spinner.harmless(b)
        usleep(3_000_000)
        #expect(b.deviceResetCount == 0)
        #expect(b.lastHangReport.isEmpty, "\(b.lastHangReport)")
        spinner.guest.pointer.storeBytes(of: UInt32(1), toByteOffset: 0, as: UInt32.self)
        _ = spinner.done.wait(timeout: .now() + 90)
        _ = spinner.done.wait(timeout: .now() + 5)
        #expect(spinner.status(0) != -1)
        #expect(spinner.status(1) != -1)
        spinner.release(b)
    }
}
