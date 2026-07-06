import SwiftUI

struct ProjectTreeRowView: View {
    let node: ProjectNode

    var body: some View {
        HStack {
            Image(systemName: node.kind == .folder ? "folder" : "doc")
                .foregroundStyle(node.kind == .folder ? .blue : .secondary)
            Text(node.url.lastPathComponent)
        }
    }
}

