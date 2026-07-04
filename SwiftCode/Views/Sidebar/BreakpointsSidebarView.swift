import SwiftUI

struct BreakpointsSidebarView: View {
    var body: some View {
        VStack {
            List {
                Text("No breakpoints set")
                    .foregroundStyle(.secondary)
            }

            HStack {
                Toggle("All Exceptions", isOn: .constant(false))
                Spacer()
            }
            .padding()
        }
    }
}
