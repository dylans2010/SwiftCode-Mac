import SwiftUI

struct IssueNavigatorView: View {
    @State var viewModel: BuildViewModel

    var body: some View {
        List(viewModel.diagnostics) { diag in
            HStack {
                Image(systemName: diag.severity == .error ? "exclamationmark.octagon.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(diag.severity == .error ? .red : .yellow)
                VStack(alignment: .leading) {
                    Text(diag.message)
                        .font(.subheadline)
                    Text("\(diag.filePath):\(diag.line)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}
