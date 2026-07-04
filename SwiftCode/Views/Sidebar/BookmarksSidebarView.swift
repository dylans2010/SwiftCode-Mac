import SwiftUI

struct BookmarksSidebarView: View {
    var body: some View {
        VStack {
            List {
                Text("No bookmarks")
                    .foregroundStyle(.secondary)
            }
        }
    }
}
