import SwiftUI

struct AIAssistantPanelView: View {
    @State var viewModel: AIAssistantViewModel
    @State var editorViewModel: EditorViewModel
    @State private var inputText = ""

    var body: some View {
        VStack(spacing: 0) {
            AIModelPickerView()
            AIChatMessageListView(messages: viewModel.conversation.messages)

            if let lastMsg = viewModel.conversation.messages.last, lastMsg.role == .assistant {
                AISuggestionActionBar { action in
                    handleAIAction(action, content: lastMsg.content)
                }
            }

            AIChatInputView(text: $inputText) {
                Task {
                    await viewModel.sendMessage(inputText, model: "openai/gpt-4o")
                    inputText = ""
                }
            }
        }
        .background(Color.secondary.opacity(0.05))
    }

    private func handleAIAction(_ action: AIAction, content: String) {
        switch action {
        case .insert:
            editorViewModel.activeDocument?.content += content
        case .replace:
            editorViewModel.activeDocument?.content = content
        case .apply:
            if let url = editorViewModel.activeDocument?.url {
                let newURL = url.deletingLastPathComponent().appendingPathComponent("Generated_" + url.lastPathComponent)
                Task {
                    try? await FileSystemService.shared.createFile(at: newURL, content: content)
                    await editorViewModel.openFile(url: newURL)
                }
            }
        }
    }
}

enum AIAction {
    case insert, replace, apply
}
