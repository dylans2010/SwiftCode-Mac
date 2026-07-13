import SwiftUI

@MainActor
struct GitHubLoadingView: View {
    let message: String

    var body: some View {
        VStack(spacing: 16) {
            Spacer()

            ProgressView()
                .controlSize(.large)
                .scaleEffect(1.2)

            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
