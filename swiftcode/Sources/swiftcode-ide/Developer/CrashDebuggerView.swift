// Ported from SwiftCode-Legacy (Dylan's own code, MIT-authorised direct port).
// Rebuilt in SwiftCode style: default accent, no Legacy liquid-glass/orange styling.

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
