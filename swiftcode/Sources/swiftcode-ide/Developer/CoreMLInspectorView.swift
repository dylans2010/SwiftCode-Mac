// Ported from SwiftCode-Legacy `SwiftCode/Views/Developer/CoreMLInspector/CoreMLInspectorView.swift` (Dylan's own code; direct port authorised under MIT).
// Audit A: MISSING at bc28f653. Static port only — no Swift toolchain here; build verification pending on Dylan's Mac.
import SwiftUI
import SwiftCodeUI

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
