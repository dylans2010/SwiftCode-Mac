import SwiftUI

/// A native macOS card view that displays the current Code Review status, user explanation, and confidence.
/// This view represents the lifecycle of the code_review tool rather than being a permanent component of the interface.
public struct CodeAssistUserView: View {
    @ObservedObject private var manager = AssistManager.shared

    public init() {}

    public var body: some View {
        if manager.hasCodeReviewBeenInvoked {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: headerIcon)
                        .font(.caption)
                        .foregroundStyle(headerColor)

                    Text("Code Review")
                        .font(.caption.weight(.medium))

                    if let review = manager.currentCodeReview, !manager.isCodeReviewRunning {
                        Text(String(format: "%.0f%%", review.confidence * 100))
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(.secondary)
                    }

                    Spacer()
                }

                if manager.isCodeReviewRunning {
                    HStack(spacing: 6) {
                        ProgressView()
                            .scaleEffect(0.5)
                            .tint(.secondary)
                        Text("Reviewing implementation...")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else if let review = manager.currentCodeReview {
                    Text(review.userSee)
                        .font(.caption)
                        .lineSpacing(3)
                        .foregroundStyle(.primary)
                        .textSelection(.enabled)
                } else {
                    Text("Awaiting review...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
    }

    // MARK: - Helpers

    private var isReady: Bool {
        manager.currentCodeReview?.status == "task_ready"
    }

    private var headerIcon: String {
        if manager.isCodeReviewRunning {
            return "ellipsis.bubble.fill"
        }
        return isReady ? "checkmark.seal.fill" : "exclamationmark.triangle.fill"
    }

    private var headerColor: Color {
        if manager.isCodeReviewRunning {
            return .orange
        }
        return isReady ? .green : .red
    }

    private var statusSubtitle: String {
        if manager.isCodeReviewRunning {
            return "Reviewer analyzing workspace..."
        }
        return isReady ? "Task is ready" : "Task is not ready, agent will continue working"
    }
}
