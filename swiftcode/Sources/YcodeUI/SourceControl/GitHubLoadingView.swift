import SwiftUI

@MainActor
struct GitHubLoadingView: View {
    let message: String

    var body: some View {
        VStack(spacing: 16) {
            Spacer()

            VStack(spacing: 16) {
                ProgressView()
                    .controlSize(.large)
                    .scaleEffect(1.2)

                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(24)
            .liquidGlass(style: .subtle, cornerRadius: 16)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
