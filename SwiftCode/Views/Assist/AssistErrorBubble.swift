import SwiftUI

public struct AssistErrorBubble: View {
    public let error: String

    public init(error: String) {
        self.error = error
    }

    public var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 12))
                .foregroundStyle(.red)

            VStack(alignment: .leading, spacing: 2) {
                Text("Error")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.red)
                Text(error)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            Spacer()
        }
        .padding(8)
        .background(Color.red.opacity(0.06))
        .cornerRadius(6)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.red.opacity(0.12), lineWidth: 1)
        )
        .padding(.horizontal, 12)
    }
}
