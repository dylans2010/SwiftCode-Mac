import SwiftUI

struct BuildPipelineDebuggerView: View {
    var body: some View {
        Text("Build Pipeline State")
            .padding()
            .liquidGlass(style: .subtle, cornerRadius: 12)
            .navigationTitle("Build Pipeline Debugger")
    }
}
