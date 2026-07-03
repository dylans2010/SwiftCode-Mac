import SwiftUI

struct GitConflictBannerView: View {
    let count: Int

    var body: some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill")
            Text("\(count) merge conflicts")
            Spacer()
            Button("Resolve") { }
        }
        .padding(8)
        .background(Color.red.opacity(0.1))
        .foregroundStyle(.red)
    }
}
