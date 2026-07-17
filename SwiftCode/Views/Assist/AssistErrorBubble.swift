import SwiftUI

public struct AssistErrorBubble: View {
    public let error: String

    public init(error: String) {
        self.error = error
    }

    public var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.octagon.fill")
                .font(.system(size: 16))
                .foregroundStyle(.red)

            VStack(alignment: .leading, spacing: 4) {
                Text("Assist Error")
                    .font(.subheadline.bold())
                    .foregroundStyle(.red)
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            Spacer()
        }
        .padding(12)
        .background(Color.red.opacity(0.08))
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.red.opacity(0.15), lineWidth: 1)
        )
        .padding(.horizontal, 12)
    }
}
