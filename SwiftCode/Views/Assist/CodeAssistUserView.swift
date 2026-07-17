import SwiftUI

/// A native macOS card view that displays the current Code Review status, user explanation, and confidence.
/// This view represents the lifecycle of the code_review tool rather than being a permanent component of the interface.
public struct CodeAssistUserView: View {
    @ObservedObject private var manager = AssistManager.shared

    public init() {}

    public var body: some View {
        if manager.hasCodeReviewBeenInvoked {
            GroupBox {
                VStack(alignment: .leading, spacing: 14) {
                    // Header Area
                    HStack(spacing: 10) {
                        Image(systemName: headerIcon)
                            .font(.title2)
                            .foregroundColor(headerColor)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Independent AI Code Review")
                                .font(.headline)
                            Text(statusSubtitle)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        Spacer()

                        // Confidence rating indicator (exposed only when code review is finished and confidence exists)
                        if let review = manager.currentCodeReview, !manager.isCodeReviewRunning {
                            HStack(spacing: 4) {
                                Image(systemName: "shield.checkered")
                                    .font(.caption)
                                Text(String(format: "Confidence: %.0f%%", review.confidence * 100))
                                    .font(.system(size: 10, weight: .bold))
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.secondary.opacity(0.12), in: Capsule())
                        }
                    }

                    Divider()

                    // Main content area
                    if manager.isCodeReviewRunning {
                        // Display reviewing state
                        HStack(spacing: 12) {
                            ProgressView()
                                .scaleEffect(0.7)
                                .tint(.orange)
                            Text("Independent software reviewer is analyzing implementation, checking Swift correctness, verifying architecture constraints, and running diagnostics...")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 8)
                    } else if let review = manager.currentCodeReview {
                        // Display review results (only user_see)
                        VStack(alignment: .leading, spacing: 8) {
                            Text(review.userSee)
                                .font(.subheadline)
                                .lineSpacing(4)
                                .foregroundColor(.primary)
                                .textSelection(.enabled)
                        }
                        .padding(.vertical, 4)
                    } else {
                        // Fallback/loading
                        Text("Awaiting code review results...")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(14)
            }
            .groupBoxStyle(ModernGroupBoxStyle())
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .transition(.opacity.combined(with: .move(edge: .top)))
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
