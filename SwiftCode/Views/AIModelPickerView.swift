import SwiftUI

struct AIModelPickerView: View {
    @State private var selectedModel = "openai/gpt-4o"

    var body: some View {
        Picker("Model", selection: $selectedModel) {
            Text("GPT-4o").tag("openai/gpt-4o")
            Text("Claude 3.5 Sonnet").tag("anthropic/claude-3.5-sonnet")
        }
        .pickerStyle(.menu)
        .padding(8)
        Divider()
    }
}
