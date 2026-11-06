import SwiftUI

struct BinaryToolsViews: View {
    var body: some View {
        List {
            Text("ripgrep")
            Text("git")
            Text("swiftlint")
        }
        .liquidGlass(style: .subtle, cornerRadius: 12)
        .navigationTitle("Binary Tools")
    }
}
