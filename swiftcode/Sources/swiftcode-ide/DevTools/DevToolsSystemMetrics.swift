import Foundation
#if os(macOS)
import Darwin
#endif

enum DevToolsSystemMetrics {
    static func hostCPULoadPercent() -> Double? {
        #if os(macOS)
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        let user = Double(info.cpu_ticks.0)
        let system = Double(info.cpu_ticks.1)
        let idle = Double(info.cpu_ticks.2)
        let nice = Double(info.cpu_ticks.3)
        let total = user + system + idle + nice
        guard total > 0 else { return nil }
        return (user + system + nice) / total * 100
        #else
        return nil
        #endif
    }

    static func taskResidentMemoryMB() -> Double? {
        #if os(macOS)
        var taskInfo = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        let result = withUnsafeMutablePointer(to: &taskInfo) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        return Double(taskInfo.resident_size) / 1024 / 1024
        #else
        return nil
        #endif
    }

    static func taskThreadCount() -> Int? {
        #if os(macOS)
        var threads: thread_act_array_t?
        var count: mach_msg_type_number_t = 0
        let result = task_threads(mach_task_self_, &threads, &count)
        guard result == KERN_SUCCESS, let threads else { return nil }
        let threadCount = Int(count)
        vm_deallocate(
            mach_task_self_,
            vm_address_t(bitPattern: threads),
            vm_size_t(count) * vm_size_t(MemoryLayout<thread_act_t>.size)
        )
        return threadCount
        #else
        return nil
        #endif
    }
}
