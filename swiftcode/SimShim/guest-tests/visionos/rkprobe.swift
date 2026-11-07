import Foundation
import Metal
import RealityKit

setvbuf(stdout, nil, _IOLBF, 0)
if CommandLine.arguments.count > 1, let s = UInt32(CommandLine.arguments[1]) { sleep(s) }
print("rkprobe: start")
let device = MTLCreateSystemDefaultDevice()
print("rkprobe: device \(device?.name ?? "nil")")
MainActor.assumeIsolated {
    do {
        let renderer = try RealityRenderer()
        print("rkprobe: RealityRenderer created: \(renderer)")
    } catch {
        print("rkprobe: RealityRenderer failed: \(error)")
    }
}
print("rkprobe: end")
