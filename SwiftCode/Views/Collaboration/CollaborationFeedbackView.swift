import SwiftUI

struct CollaborationFeedbackView: View {
    let message: String
    let icon: String
    let color: Color

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.headline)
            Text(message)
                .font(.subheadline.bold())
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 20)
        .foregroundStyle(color)
        .background(.ultraThinMaterial)
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .stroke(color.opacity(0.3), lineWidth: 1)
        )
        .shadow(color: color.opacity(0.2), radius: 10, x: 0, y: 5)
    }
}

private struct CollaborationFeedbackModifier: ViewModifier {
    let message: String?
    let icon: String
    let color: Color

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .bottom) {
                if let message, !message.isEmpty {
                    CollaborationFeedbackView(message: message, icon: icon, color: color)
                        .padding(.bottom, 24)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
    }
}

extension View {
    func collaborationFeedback(message: String?, icon: String = "info.circle", color: Color = .blue) -> some View {
        modifier(CollaborationFeedbackModifier(message: message, icon: icon, color: color))
    }
}
