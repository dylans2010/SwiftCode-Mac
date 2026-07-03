import SwiftUI

struct GitNotInstalledView: View {
    var body: some View {
        ContentUnavailableView {
            Label("Git Not Found", systemImage: "exclamationmark.triangle")
        } description: {
            Text("Please install Git or check your PATH to use source control features.")
        } actions: {
            Button("How to install?") {
                NSWorkspace.shared.open(URL(string: "https://git-scm.com/downloads")!)
            }
        }
    }
}
