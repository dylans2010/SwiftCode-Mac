import SwiftUI

struct CrashDebuggerView: View {
    var body: some View {
        List {
            Button("Simulate Crash", role: .destructive) {
                fatalError("Simulated crash")
            }
        }
        .navigationTitle("Crash Debugger")
    }
}
