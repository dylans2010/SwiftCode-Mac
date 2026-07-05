import SwiftUI

struct MemoryInspectorView: View {
    @State private var memoryUsage: String = "Calculating..."
    let timer = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    var body: some View {
        List {
            Section("App Memory") {
                HStack {
                    Text("Memory Usage")
                    Spacer()
                    Text(memoryUsage)
                        .monospacedDigit()
                }
            }
        }
        .navigationTitle("Memory Inspector")
        .onAppear(perform: updateMemory)
        .onReceive(timer) { _ in updateMemory() }
    }

    private func updateMemory() {
        var taskInfo = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        let kerr: kern_return_t = withUnsafeMutablePointer(to: &taskInfo) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }

        if kerr == KERN_SUCCESS {
            let usedMB = Double(taskInfo.resident_size) / 1024.0 / 1024.0
            memoryUsage = String(format: "%.2f MB", usedMB)
        } else {
            memoryUsage = "Error"
        }
    }
}
