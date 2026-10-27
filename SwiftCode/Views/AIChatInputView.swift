import SwiftUI
import os

private let logger = Logger(subsystem: "com.swiftcode.app", category: "AIChatInputView")

struct AIChatInputView: View {
    @Binding var text: String
    let onSend: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            TextField("Ask AI...", text: $text)
                .textFieldStyle(.plain)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .liquidGlass(style: .subtle, cornerRadius: 8)
                .onSubmit {
                    logger.log("[onSubmit] Return key pressed. Triggering send.")
                    onSend()
                }
            Button(action: {
                logger.log("[Button] Send button pressed. Triggering send.")
                onSend()
            }) {
                Image(systemName: "paperplane.fill")
                    .padding(6)
                    .foregroundStyle(.white)
                    .background(Color.accentColor)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .disabled(text.isEmpty)
        }
        .padding(10)
        .background(VisualEffectView(material: .headerView, blendingMode: .withinWindow))
    }
}
