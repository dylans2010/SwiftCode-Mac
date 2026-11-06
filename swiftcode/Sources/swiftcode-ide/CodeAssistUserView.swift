// STAGED PORT — SwiftCode-Legacy `SwiftCode/Views/Assist/CodeAssistUserView.swift` (main ab03f681; Dylan's own code, direct port authorised under MIT).
// Staged by migration subagent A3 (Assist systems / tools / execution) — NOT yet landed in the repo.
// Target: swiftcode-ide (`swiftcode/Sources/swiftcode-ide/CodeAssistUserView.swift`).
// Body is Legacy verbatim unless noted under ADAPTATIONS below. No Swift toolchain exists
// in this environment: static checks only — never claim a build passed.
// Audit gap this port closes (claimed-covered-audit):
//   - reviewer progress/status display (Reviewing implementation… / Awaiting review… / Task is ready / Task is not ready)
// ADAPTATIONS:
//   - Observation adaptation (wiring-views): @ObservedObject/@StateObject over
//     @Observable models replaced with @State (@Bindable where `$` bindings are used).
//   - Added `import SwiftCodeAssistant` (views consume Assist models; module is a swiftcode-ide dependency).
// UNRESOLVED DEPENDENCIES (no definition in the destination yet; resolve as the owning ports land):
//   - AssistManager — A6 (ALL-MISSING) (`SwiftCode/Backend/Assist/AssistManager.swift`)
// WIRING / REGISTRATION: Wire into the swiftcode-ide assistant UI (AssistantPane / AssistMainView) once the models it observes land. Remaining in-file work: @Observable adaptation (see ADAPTATIONS).

import SwiftUI
import SwiftCodeAssistant

/// A native macOS card view that displays the current Code Review status, user explanation, and confidence.
/// This view represents the lifecycle of the code_review tool rather than being a permanent component of the interface.
public struct CodeAssistUserView: View {
    @State private var manager = AssistManager.shared

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
            .liquidGlass(style: .subtle, cornerRadius: 8)
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
