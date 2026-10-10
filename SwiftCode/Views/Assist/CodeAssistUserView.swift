import SwiftUI

/// Plain inline row displaying Code Review status, user explanation, and confidence.
public struct CodeAssistUserView: View {
    @ObservedObject private var manager = AssistManager.shared

    public init() {}

    public var body: some View {
        if manager.hasCodeReviewBeenInvoked {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: headerIcon)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(headerColor)

                    Text("Code Review")
                        .font(.system(size: 11, weight: .medium))

                    if let review = manager.currentCodeReview, !manager.isCodeReviewRunning {
                        Text(String(format: "%.0f%%", review.confidence * 100))
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }

                    Spacer()
                }

                if manager.isCodeReviewRunning {
                    HStack(spacing: 6) {
                        ProgressView()
                            .scaleEffect(0.4)
                            .frame(width: 12, height: 12)
                            .tint(.secondary)
                        Text("Running automated review")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                } else if let review = manager.currentCodeReview {
                    Text(review.userSee)
                        .font(.system(size: 11))
                        .lineSpacing(2)
                        .foregroundStyle(.primary)
                        .textSelection(.enabled)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
        }
    }

    // MARK: - Helpers

    private var isReady: Bool {
        manager.currentCodeReview?.status == "task_ready"
    }

    private var headerIcon: String {
        if manager.isCodeReviewRunning {
            return "checkmark.shield"
        }
        return isReady ? "checkmark.seal.fill" : "exclamationmark.triangle.fill"
    }

    private var headerColor: Color {
        if manager.isCodeReviewRunning {
            return .accentColor
        }
        return isReady ? .green : .red
    }
}
