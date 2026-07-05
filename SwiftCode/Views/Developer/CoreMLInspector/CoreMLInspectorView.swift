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
        .navigationTitle("CoreML Inspector")
    }
}
