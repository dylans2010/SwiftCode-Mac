import SwiftUI

struct ThreadInspectorView: View {
    var body: some View {
        List {
            Section("Active Threads") {
                Text("Main Thread (Running)")
                Text("Background Task 1 (Sleeping)")
            }
        }
        .liquidGlass(style: .subtle, cornerRadius: 12)
        .navigationTitle("Thread Inspector")
    }
}
