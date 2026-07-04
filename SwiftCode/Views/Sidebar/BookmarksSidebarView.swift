import SwiftUI

struct BookmarksSidebarView: View {
    @State private var store = BookmarkStore.shared

    var body: some View {
        VStack {
            List {
                if store.bookmarks.isEmpty {
                    ContentUnavailableView("No Bookmarks", systemImage: "bookmark", description: Text("Add bookmarks to quickly jump to important lines of code."))
                } else {
                    ForEach(store.bookmarks) { bookmark in
                        HStack {
                            Image(systemName: "bookmark.fill")
                                .foregroundColor(.accentColor)
                            VStack(alignment: .leading) {
                                Text(bookmark.fileName).font(.headline)
                                Text("Line \(bookmark.lineNumber)").font(.caption).foregroundColor(.secondary)
                            }
                            Spacer()
                        }
                        .contextMenu {
                            Button("Delete", role: .destructive) {
                                store.remove(id: bookmark.id)
                            }
                        }
                    }
                }
            }
        }
    }
}
