import SwiftUI

@MainActor
struct GitHubErrorView: View {
    let title: String
    let errorDescription: String
    var retryAction: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            VStack(spacing: 16) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(.red)

                Text(title)
                    .font(.headline)
                    .foregroundStyle(.primary)

                Text(errorDescription)
                    .font(.subheadline)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: 320)
                    .lineSpacing(4)

                if let retryAction = retryAction {
                    Button {
                        retryAction()
                    } label: {
                        Label("Retry Operation", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.blue)
                    .controlSize(.regular)
                    .padding(.top, 8)
                }
            }
            .padding(24)
            .frame(maxWidth: 400)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
