import SwiftUI

struct GitBranchesView: View {
    let branches: [GitBranch]

    var body: some View {
        List(branches) { branch in
            HStack {
                Image(systemName: "branch")
                Text(branch.name)
                if branch.isCurrent {
                    Image(systemName: "checkmark")
                        .foregroundStyle(.blue)
                }
                Spacer()
                if branch.isRemote {
                    Text("remote").font(.caption).padding(2).background(Color.secondary.opacity(0.2))
                }
            }
        }
    }
}
