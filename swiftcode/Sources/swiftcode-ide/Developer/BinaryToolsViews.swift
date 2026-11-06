// Ported from SwiftCode-Legacy `SwiftCode/Views/Developer/BinaryTools/BinaryToolsViews.swift` (Dylan's own code; direct port authorised under MIT).
// Audit A: MISSING at bc28f653. Static port only — no Swift toolchain here; build verification pending on Dylan's Mac.
import SwiftUI
import SwiftCodeUI

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
