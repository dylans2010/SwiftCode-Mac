import SwiftUI

struct AIChatInputView: View {
    @Binding var text: String
    let onSend: () -> Void

    var body: some View {
        HStack {
            TextField("Ask AI...", text: $text)
                .textFieldStyle(.roundedBorder)
            Button(action: onSend) {
                Image(systemName: "paperplane.fill")
            }
            .disabled(text.isEmpty)
        }
        .padding()
    }
}
