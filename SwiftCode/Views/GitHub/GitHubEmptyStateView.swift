import SwiftUI

@MainActor
struct GitHubEmptyStateView: View {
    let title: String
    let description: String
    let systemImage: String
    var accentColor: Color = .orange
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            VStack(spacing: 16) {
                Image(systemName: systemImage)
                    .font(.system(size: 44))
                    .foregroundStyle(accentColor)
                    .padding(.bottom, 4)

                Text(title)
                    .font(.headline)
                    .foregroundStyle(.primary)

                Text(description)
                    .font(.subheadline)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: 320)
                    .lineSpacing(4)

                if let actionTitle = actionTitle, let action = action {
                    Button(actionTitle, action: action)
                        .buttonStyle(.borderedProminent)
                        .tint(accentColor)
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
