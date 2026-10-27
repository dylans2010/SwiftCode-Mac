import SwiftUI

struct IssueNavigatorView: View {
    @State var viewModel: BuildViewModel

    var body: some View {
        List(viewModel.diagnostics) { diag in
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: diag.severity == .error ? "exclamationmark.octagon.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(diag.severity == .error ? .red : .yellow)
                    .font(.system(size: 14))
                    .padding(.top, 2)
                VStack(alignment: .leading, spacing: 3) {
                    Text(diag.message)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)
                    Text("\(diag.filePath):\(diag.line)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(10)
            .liquidGlass(style: .subtle, cornerRadius: 8, tint: diag.severity == .error ? .red : .yellow)
            .listRowInsets(EdgeInsets(top: 4, leading: 8, bottom: 4, trailing: 8))
            .listRowBackground(Color.clear)
        }
        .scrollContentBackground(.hidden)
        .background(VisualEffectView(material: .sidebar, blendingMode: .withinWindow))
    }
}
