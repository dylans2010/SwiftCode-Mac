import CVulkan
import Foundation
import SwiftCodeMetalHost

extension VulkanMetalBackend {
    public func snapshotSettle() {
        guard isAvailable else { return }
        enterDevice()
        defer { leaveDevice() }
        cond.lock()
        try? flushSetup()
        _ = fn.vkDeviceWaitIdle!(ctx.pointee.device)
        cond.unlock()
    }

    public func bufferContents(_ handle: MetalHandle) -> [UInt8]? {
        cond.lock(); defer { cond.unlock() }
        guard let b = buffers[handle], b.allocation.key == nil, let base = b.allocation.base, b.length > 0 else { return nil }
        return [UInt8](UnsafeRawBufferPointer(start: base + b.offset, count: b.length))
    }

    public func setBufferContents(_ handle: MetalHandle, _ bytes: [UInt8]) -> Bool {
        cond.lock(); defer { cond.unlock() }
        guard let b = buffers[handle], b.allocation.key == nil, let base = b.allocation.base else { return false }
        let n = min(bytes.count, b.length)
        bytes.withUnsafeBytes { (base + b.offset).copyMemory(from: $0.baseAddress!, byteCount: n) }
        return true
    }
}
