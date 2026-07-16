import SwiftUI
import os

private let logger = Logger(subsystem: "com.swiftcode.app", category: "AIChatInputView")

struct AIChatInputView: View {
    @Binding var text: String
    let onSend: () -> Void

    var body: some View {
        HStack {
            TextField("Ask AI...", text: $text)
                .textFieldStyle(.roundedBorder)
                .onSubmit {
                    logger.log("[onSubmit] Return key pressed. Triggering send.")
                    onSend()
                }
            Button(action: {
                logger.log("[Button] Send button pressed. Triggering send.")
                onSend()
            }) {
                Image(systemName: "paperplane.fill")
            }
            .disabled(text.isEmpty)
        }
        .padding()
    }
}
