import SwiftUI

struct GitHistoryView: View {
    let commits: [GitCommit]

    var body: some View {
        List(commits) { commit in
            VStack(alignment: .leading) {
                Text(commit.message).font(.headline).lineLimit(1)
                HStack {
                    Text(commit.author).bold()
                    Text(commit.id.prefix(7)).foregroundStyle(.secondary)
                    Spacer()
                    Text(commit.date, style: .date)
                }
                .font(.caption)
            }
        }
    }
}
