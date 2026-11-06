import SwiftUI

struct CoreMLInspectorView: View {
    var body: some View {
        List {
            Section("Loaded Models") {
                Text("CodeCompletionModel.mlmodel")
            }
            Section("Metrics") {
                Text("Inference Time: 45ms")
            }
        }
        .liquidGlass(style: .subtle, cornerRadius: 12)
        .navigationTitle("CoreML Inspector")
    }
}
